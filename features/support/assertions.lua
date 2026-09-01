local JSON = require("JSON")

local assertions = {}

function assertions.deepEqual(a, b)
    if a == b then
        return true
    end

    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end

    local seen = {}
    for key, value in pairs(a) do
        if not assertions.deepEqual(value, b[key]) then
            return false
        end
        seen[key] = true
    end

    for key in pairs(b) do
        if not seen[key] then
            return false
        end
    end

    return true
end

function assertions.assertEqual(expected, actual, message)
    if expected ~= actual then
        error(string.format(
            "%s: expected %s, got %s",
            message or "assertEqual",
            tostring(expected),
            tostring(actual)
        ))
    end
end

function assertions.assertTrue(value, message)
    if not value then
        error(message or "expected truthy value")
    end
end

function assertions.assertDeepEqual(expected, actual, message)
    if not assertions.deepEqual(expected, actual) then
        error(string.format(
            "%s: tables differ\n  expected: %s\n  actual:   %s",
            message or "assertDeepEqual",
            JSON.encode(expected),
            JSON.encode(actual)
        ))
    end
end

function assertions.assertThrows(fn, message)
    local ok = pcall(fn)
    if ok then
        error(message or "expected error but call succeeded")
    end
end

return assertions
