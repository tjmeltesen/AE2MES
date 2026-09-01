---@class Comms
---@function send fun(self: Comms, url: string, data: string|table|nil, headers: table<string, string>|nil, method: string|nil): fun():string|nil
---@function socket fun(self: Comms, address: string, port: integer|nil): InternetSocket
---@function open fun(self: Comms, address: string, port: integer|nil): BufferedSocket
local internet = require("internet")
local JSON = require("JSON")
Comms = {}
Comms.__index = Comms

Comms._gate = { busy = false }

local function mergeHeaders(url, headers)
    headers = headers or {}
    if type(url) == "string" and url:find("ngrok", 1, true) then
        headers["ngrok-skip-browser-warning"] = "1"
    end
    return headers
end

function Comms:_acquireGate()
    while self._gate.busy do
        os.sleep(0.05)
    end
    self._gate.busy = true
end

function Comms:_releaseGate()
    self._gate.busy = false
end

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

---Sends an HTTP request to the specified URL.
---@param url string # The URL to send the request to.
---@param data string|table|nil # The POST data to send. If omitted, a GET request is sent.
---@param headers table<string, string>|nil # Additional HTTP headers. Defaults to nil.
---@param method string|nil # The HTTP method to use (e.g., "GET", "POST", "PUT"). Defaults to "GET" or "POST" depending on `data`.
---@return fun():string|nil # An iterator that returns chunks of the response body.
function Comms:send(url, data, headers, method)
    return internet.request(url, data, mergeHeaders(url, headers), method)
end

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


---Opens a TCP socket to the specified address and port.
---@param address string # The address to connect to.
---@param port integer|nil # The port to connect to. Defaults to 80.
---@return InternetSocket # A socket-like table providing `read`, `write`, and `close` methods.
function Comms:socket(address, port) return internet.socket(address, port) end

---Opens a buffered TCP stream to the specified address and port.
---@param address string # The address to connect to.
---@param port integer|nil # The port to connect to. Defaults to 80.
---@return BufferedSocket # A buffered stream-like object with `read`, `write`, and `close` methods.
function Comms:open(address, port) return internet.open(address, port) end


function Comms:requestJSON(url, data, headers, method)
    local body, err = self:request(url, data, headers, method)

    if not body then
        return nil, err
    end

    local ok, result = pcall(JSON.decode, body)

    if not ok then
        return nil, "JSON decode failed: " .. tostring(result)
    end

    return result
end

function Comms:sendJSON(url, data, headers, method)
    headers = mergeHeaders(url, headers or {})
    headers["Content-Type"] = "application/json"

    local body = nil

    if data ~= nil then
        local ok, encoded = pcall(JSON.encode, data)

        if not ok then
            return nil, "JSON encode failed: " .. tostring(encoded)
        end

        body = encoded
        method = method or "POST"
    end

    return self:send(url, body, headers, method)
end

function Comms:requestJSONPost(url, data, headers)
    headers = mergeHeaders(url, headers or {})
    headers["Content-Type"] = "application/json"

    local ok, encoded = pcall(JSON.encode, data)
    if not ok then
        return nil, "JSON encode failed: " .. tostring(encoded)
    end

    local body, err = self:request(url, encoded, headers, "POST")
    if not body then
        return nil, err
    end

    local decodeOk, result = pcall(JSON.decode, body)
    if not decodeOk then
        return nil, "JSON decode failed: " .. tostring(result)
    end

    return result
end

return Comms
