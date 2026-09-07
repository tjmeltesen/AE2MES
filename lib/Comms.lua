---@meta _
---@brief Serialized HTTP, JSON, and TCP helpers for the OpenComputers internet card.
---@version 1.0.0
---@class InternetSocket
---@field read fun(self: InternetSocket, count?: integer): string|nil
---@field write fun(self: InternetSocket, data: string): any
---@field close fun(self: InternetSocket)
---@field finishConnect fun(self: InternetSocket): boolean
---@class BufferedSocket
---@field read fun(self: BufferedSocket, count?: integer): string|nil
---@field write fun(self: BufferedSocket, data: string): any
---@field close fun(self: BufferedSocket)
---@class Comms
---@field _gate { busy: boolean } # Process-wide HTTP request gate shared by all callers.
---@type table
local internet = require("internet")
local JSON = require("JSON")
Comms = {}
Comms.__index = Comms

Comms._gate = { busy = false }

---Add the ngrok browser-warning bypass header when required.
---The supplied header table is reused and may be mutated.
---@param url string
---@param headers? table<string, string>
---@return table<string, string> headers # The original table, or a new table when omitted.
local function mergeHeaders(url, headers)
    headers = headers or {}
    if type(url) == "string" and url:find("ngrok", 1, true) then
        headers["ngrok-skip-browser-warning"] = "1"
    end
    return headers
end

---Wait until the shared request gate is free, then acquire it.
---Sleeps in 50 ms intervals and leaves the gate busy until `_releaseGate` is called.
---@return nil
function Comms:_acquireGate()
    while self._gate.busy do
        os.sleep(0.05)
    end
    self._gate.busy = true
end

---Release the shared request gate.
---@return nil
function Comms:_releaseGate()
    self._gate.busy = false
end

---Consume a response iterator and concatenate all body chunks.
---Iterator failures are caught and returned as strings; chunks already read are discarded on failure.
---@param response fun(): string|nil # Iterator returned by `internet.request`.
---@return string|nil body
---@return string|nil error
function Comms:_readResponse(response)
    local chunks = {}
    local ok, err = pcall(function()
        for chunk in response do
            table.insert(chunks, chunk)
        end
    end)

    if not ok then
        return nil, tostring(err)
    end

    return table.concat(chunks)
end

---Start an HTTP request to the specified URL.
---May mutate `headers` to add ngrok support. Transport errors and invalid arguments are
---reported according to `internet.request` and are not caught by this method.
---@param url string # The URL to send the request to.
---@param data string|table|nil # The POST data to send. If omitted, a GET request is sent.
---@param headers table<string, string>|nil # Additional HTTP headers. Defaults to nil.
---@param method string|nil # The HTTP method to use (e.g., "GET", "POST", "PUT"). Defaults to "GET" or "POST" depending on `data`.
---@return (fun(): string|nil)|nil response # Iterator yielding response-body chunks, or nil on failure.
---@return string|nil error # Error supplied by the internet library when no iterator is returned.
function Comms:send(url, data, headers, method)
    return internet.request(url, data, mergeHeaders(url, headers), method)
end

---Perform a serialized HTTP request and read its complete response body.
---Blocks on the process-wide request gate, mutates ngrok header tables, and always releases
---the gate after request/response processing. Request and iterator exceptions are converted to errors.
---@param url string
---@param data? string|table # Request body; omission lets the internet library choose GET.
---@param headers? table<string, string> # Additional headers; may be mutated for ngrok URLs.
---@param method? string # Explicit HTTP method.
---@return string|nil body
---@return string|nil error
function Comms:request(url, data, headers, method)
    self:_acquireGate()

    local ok, body, err = pcall(function()
        local requestOk, response = pcall(self.send, self, url, data, mergeHeaders(url, headers), method)
        if not requestOk then
            return nil, tostring(response)
        end

        if not response then
            return nil, "HTTP request failed"
        end

        return self:_readResponse(response)
    end)

    self:_releaseGate()

    if not ok then
        return nil, tostring(body)
    end

    return body, err
end


---Open an unbuffered TCP socket to the specified address and port.
---Connection errors are passed through from the OpenComputers internet library.
---@param address string # The address to connect to.
---@param port integer|nil # The port to connect to. Defaults to 80.
---@return InternetSocket|nil socket # Socket-like object providing `read`, `write`, and `close`.
---@return string|nil error
function Comms:socket(address, port) return internet.socket(address, port) end

---Open a buffered TCP stream to the specified address and port.
---Connection errors are passed through from the OpenComputers internet library.
---@param address string # The address to connect to.
---@param port integer|nil # The port to connect to. Defaults to 80.
---@return BufferedSocket|nil stream # Buffered stream-like object with `read`, `write`, and `close`.
---@return string|nil error
function Comms:open(address, port) return internet.open(address, port) end


---Perform an HTTP request and decode the complete response body as JSON.
---Shares the serialized request gate and header-mutation behavior of `request`.
---@param url string
---@param data? string|table
---@param headers? table<string, string>
---@param method? string
---@return any|nil value # Decoded JSON value.
---@return string|nil error # Request failure or JSON decoder exception.
function Comms:requestJSON(url, data, headers, method)
    local body, err = self:request(url, data, headers, method)

    if not body then
        return nil, err
    end

    local ok, result = pcall(JSON.decode, JSON, body)

    if not ok then
        return nil, "JSON decode failed: " .. tostring(result)
    end

    return result
end

---Encode an optional Lua value and start a JSON HTTP request.
---Mutates the supplied headers by setting `Content-Type` and any ngrok bypass header.
---Encoding exceptions are returned; transport errors follow `send`.
---@param url string
---@param data? any # Value to encode; nil sends no body.
---@param headers? table<string, string>
---@param method? string # Defaults to POST when `data` is non-nil.
---@return (fun(): string|nil)|nil response # Response-body iterator.
---@return string|nil error # Encoding or transport error.
function Comms:sendJSON(url, data, headers, method)
    headers = mergeHeaders(url, headers or {})
    headers["Content-Type"] = "application/json"

    local body = nil

    if data ~= nil then
        local ok, encoded = pcall(JSON.encode, JSON, data)

        if not ok then
            return nil, "JSON encode failed: " .. tostring(encoded)
        end

        body = encoded
        method = method or "POST"
    end

    return self:send(url, body, headers, method)
end

---POST a JSON value, read the full response, and decode its JSON body.
---Serializes the network request and mutates the supplied headers to set JSON content type.
---@param url string
---@param data any # Lua value accepted by the bundled JSON encoder.
---@param headers? table<string, string>
---@return any|nil value # Decoded response value.
---@return string|nil error # Encoding, request, response-iteration, or decoding failure.
function Comms:requestJSONPost(url, data, headers)
    headers = mergeHeaders(url, headers or {})
    headers["Content-Type"] = "application/json"

    local ok, encoded = pcall(JSON.encode, JSON, data)
    if not ok then
        return nil, "JSON encode failed: " .. tostring(encoded)
    end

    local body, err = self:request(url, encoded, headers, "POST")
    if not body then
        return nil, err
    end

    local decodeOk, result = pcall(JSON.decode, JSON, body)
    if not decodeOk then
        return nil, "JSON decode failed: " .. tostring(result)
    end

    return result
end

return Comms
