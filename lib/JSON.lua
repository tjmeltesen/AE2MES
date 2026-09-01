local JSON = {}

local NULL = {}

JSON.null = NULL

-- ============================================================================
-- Decoder
-- ============================================================================

local function errorAt(message, text, index)
    error(
        string.format(
            "JSON decode error at position %d: %s",
            index,
            message
        )
    )
end

local function skipWhitespace(text, index)
    local length = #text

    while index <= length do
        local c = text:sub(index, index)

        if c == " "
            or c == "\t"
            or c == "\n"
            or c == "\r"
        then
            index = index + 1
        else
            break
        end
    end

    return index
end

local function parseString(text, index)
    if text:sub(index, index) ~= '"' then
        errorAt("expected string", text, index)
    end

    index = index + 1

    local result = {}
    local length = #text

    while index <= length do
        local c = text:sub(index, index)

        -- End of string
        if c == '"' then
            return table.concat(result), index + 1
        end

        -- Escape sequence
        if c == "\\" then
            local escape = text:sub(index + 1, index + 1)

            if escape == '"' then
                table.insert(result, '"')

            elseif escape == "\\" then
                table.insert(result, "\\")

            elseif escape == "/" then
                table.insert(result, "/")

            elseif escape == "b" then
                table.insert(result, "\b")

            elseif escape == "f" then
                table.insert(result, "\f")

            elseif escape == "n" then
                table.insert(result, "\n")

            elseif escape == "r" then
                table.insert(result, "\r")

            elseif escape == "t" then
                table.insert(result, "\t")

            elseif escape == "u" then
                -- Basic \uXXXX support.
                -- Lua/OpenComputers may not have a UTF-8 helper,
                -- so convert the codepoint manually.

                local hex = text:sub(index + 2, index + 5)

                if #hex ~= 4 or not hex:match("^[%da-fA-F]+$") then
                    errorAt("invalid unicode escape", text, index)
                end

                local codepoint = tonumber(hex, 16)

                if codepoint <= 0x7F then
                    table.insert(result, string.char(codepoint))

                elseif codepoint <= 0x7FF then
                    table.insert(
                        result,
                        string.char(
                            0xC0 + math.floor(codepoint / 0x40),
                            0x80 + (codepoint % 0x40)
                        )
                    )

                elseif codepoint <= 0xFFFF then
                    table.insert(
                        result,
                        string.char(
                            0xE0 + math.floor(codepoint / 0x1000),
                            0x80 + (math.floor(codepoint / 0x40) % 0x40),
                            0x80 + (codepoint % 0x40)
                        )
                    )
                end

                index = index + 4

            else
                errorAt("invalid escape sequence", text, index)
            end

            index = index + 2

        else
            table.insert(result, c)
            index = index + 1
        end
    end

    errorAt("unterminated string", text, index)
end

local function parseNumber(text, index)
    local remaining = text:sub(index)
    local length = #remaining
    local position = 1

    if remaining:sub(position, position) == "-" then
        position = position + 1
    end

    if position > length then
        errorAt("invalid number", text, index)
    end

    local first = remaining:sub(position, position)

    if first == "0" then
        position = position + 1

        if position <= length and remaining:sub(position, position):match("%d") then
            errorAt("invalid number", text, index)
        end
    elseif first:match("[1-9]") then
        position = position + 1

        while position <= length and remaining:sub(position, position):match("%d") do
            position = position + 1
        end
    else
        errorAt("invalid number", text, index)
    end

    if position <= length and remaining:sub(position, position) == "." then
        position = position + 1

        if position > length or not remaining:sub(position, position):match("%d") then
            errorAt("invalid number", text, index)
        end

        while position <= length and remaining:sub(position, position):match("%d") do
            position = position + 1
        end
    end

    if position <= length then
        local exponent = remaining:sub(position, position)

        if exponent == "e" or exponent == "E" then
            position = position + 1

            if position <= length then
                local sign = remaining:sub(position, position)

                if sign == "+" or sign == "-" then
                    position = position + 1
                end
            end

            if position > length or not remaining:sub(position, position):match("%d") then
                errorAt("invalid number", text, index)
            end

            while position <= length and remaining:sub(position, position):match("%d") do
                position = position + 1
            end
        end
    end

    local number = remaining:sub(1, position - 1)
    local value = tonumber(number)

    if value == nil then
        errorAt("invalid number", text, index)
    end

    return value, index + position - 1
end

local parseValue

local function parseArray(text, index)
    -- Skip [
    index = index + 1

    local result = {}

    index = skipWhitespace(text, index)

    -- Empty array
    if text:sub(index, index) == "]" then
        return result, index + 1
    end

    while true do
        local value

        value, index = parseValue(text, index)

        table.insert(result, value)

        index = skipWhitespace(text, index)

        local c = text:sub(index, index)

        if c == "]" then
            return result, index + 1
        end

        if c ~= "," then
            errorAt("expected ',' or ']'", text, index)
        end

        index = skipWhitespace(text, index + 1)
    end
end

local function parseObject(text, index)
    -- Skip {
    index = index + 1

    local result = {}

    index = skipWhitespace(text, index)

    -- Empty object
    if text:sub(index, index) == "}" then
        return result, index + 1
    end

    while true do
        index = skipWhitespace(text, index)

        if text:sub(index, index) ~= '"' then
            errorAt("expected object key", text, index)
        end

        local key
        key, index = parseString(text, index)

        index = skipWhitespace(text, index)

        if text:sub(index, index) ~= ":" then
            errorAt("expected ':'", text, index)
        end

        index = skipWhitespace(text, index + 1)

        local value
        value, index = parseValue(text, index)

        result[key] = value

        index = skipWhitespace(text, index)

        local c = text:sub(index, index)

        if c == "}" then
            return result, index + 1
        end

        if c ~= "," then
            errorAt("expected ',' or '}'", text, index)
        end

        index = skipWhitespace(text, index + 1)
    end
end

parseValue = function(text, index)
    index = skipWhitespace(text, index)

    local c = text:sub(index, index)

    if c == "{" then
        return parseObject(text, index)

    elseif c == "[" then
        return parseArray(text, index)

    elseif c == '"' then
        return parseString(text, index)

    elseif text:sub(index, index + 3) == "true" then
        return true, index + 4

    elseif text:sub(index, index + 4) == "false" then
        return false, index + 5

    elseif text:sub(index, index + 3) == "null" then
        return JSON.null, index + 4

    elseif c == "-"
        or c:match("%d")
    then
        return parseNumber(text, index)
    end

    errorAt("unexpected character '" .. c .. "'", text, index)
end

function JSON.decode(text)
    if type(text) ~= "string" then
        error("JSON.decode expected string, got " .. type(text))
    end

    local value, index = parseValue(text, 1)

    index = skipWhitespace(text, index)

    if index <= #text then
        errorAt("unexpected data after JSON value", text, index)
    end

    return value
end

-- ============================================================================
-- Encoder
-- ============================================================================

local function escapeString(value)
    value = value:gsub("\\", "\\\\")
    value = value:gsub('"', '\\"')
    value = value:gsub("\b", "\\b")
    value = value:gsub("\f", "\\f")
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\t", "\\t")

    return '"' .. value .. '"'
end

local function isArray(value)
    local count = 0

    for key in pairs(value) do
        if type(key) ~= "number" then
            return false
        end

        count = count + 1
    end

    for i = 1, count do
        if value[i] == nil then
            return false
        end
    end

    return true
end

local function encodeValue(value)
    local valueType = type(value)

    if value == JSON.null then
        return "null"

    elseif valueType == "nil" then
        return "null"

    elseif valueType == "boolean" then
        return value and "true" or "false"

    elseif valueType == "number" then
        return tostring(value)

    elseif valueType == "string" then
        return escapeString(value)

    elseif valueType == "table" then

        if isArray(value) then
            local result = {}

            for i = 1, #value do
                result[i] = encodeValue(value[i])
            end

            return "[" .. table.concat(result, ",") .. "]"

        else
            local result = {}

            for key, item in pairs(value) do
                if type(key) ~= "string" then
                    error("JSON object keys must be strings")
                end

                table.insert(
                    result,
                    escapeString(key) .. ":" .. encodeValue(item)
                )
            end

            return "{" .. table.concat(result, ",") .. "}"
        end
    end

    error("cannot encode type " .. valueType)
end

function JSON.encode(value)
    return encodeValue(value)
end

return JSON