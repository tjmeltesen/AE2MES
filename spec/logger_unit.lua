package.path = "./src/?.lua;./lib/?.lua;./features/support/?.lua;" .. package.path

local failures = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("PASS: " .. name)
        return
    end
    failures = failures + 1
    print("FAIL: " .. name .. " - " .. tostring(err))
end

local function assertEqual(expected, actual, message)
    if expected ~= actual then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected truthy")
    end
end

---Reload Logger and capture print output during fn.
---@return string[] lines
local function withCapture(fn)
    package.loaded["Logger"] = nil
    local lines = {}
    local realPrint = print
    _G.print = function(...)
        local n = select("#", ...)
        local parts = {}
        for i = 1, n do
            parts[i] = tostring(select(i, ...))
        end
        lines[#lines + 1] = table.concat(parts, "\t")
    end
    local ok, err = pcall(fn)
    _G.print = realPrint
    if not ok then
        error(err)
    end
    return lines
end

test("info emits [INFO][tag] message after configure", function()
    local lines = withCapture(function()
        local Logger = require("Logger")
        Logger.configure({ level = "info" })
        Logger.info("Runtime", "boot complete")
    end)
    assertEqual(1, #lines, "one line")
    assertEqual("[INFO][Runtime] boot complete", lines[1], "format")
end)

test("varargs are tostring'd and space-joined", function()
    local lines = withCapture(function()
        local Logger = require("Logger")
        Logger.configure({ level = "info" })
        Logger.error("Runtime", "staging failed:", nil, 42)
    end)
    assertEqual(1, #lines, "one line")
    assertEqual("[ERROR][Runtime] staging failed: nil 42", lines[1], "varargs join")
end)

test("info minimum suppresses debug and allows info/warn/error", function()
    local lines = withCapture(function()
        local Logger = require("Logger")
        Logger.configure({ level = "info" })
        Logger.debug("Runtime", "heartbeat ok")
        Logger.info("Runtime", "state running")
        Logger.warn("Runtime", "quarantine")
        Logger.error("Runtime", "uplink failed")
    end)
    assertEqual(3, #lines, "debug suppressed")
    assertEqual("[INFO][Runtime] state running", lines[1], "info")
    assertEqual("[WARN][Runtime] quarantine", lines[2], "warn")
    assertEqual("[ERROR][Runtime] uplink failed", lines[3], "error")
end)

test("error minimum emits only error", function()
    local lines = withCapture(function()
        local Logger = require("Logger")
        Logger.configure({ level = "error" })
        Logger.debug("Runtime", "d")
        Logger.info("Runtime", "i")
        Logger.warn("Runtime", "w")
        Logger.error("Runtime", "e")
    end)
    assertEqual(1, #lines, "only error")
    assertEqual("[ERROR][Runtime] e", lines[1], "error line")
end)

test("debug minimum emits all levels", function()
    local lines = withCapture(function()
        local Logger = require("Logger")
        Logger.configure({ level = "debug" })
        Logger.debug("Runtime", "d")
        Logger.info("Runtime", "i")
        Logger.warn("Runtime", "w")
        Logger.error("Runtime", "e")
    end)
    assertEqual(4, #lines, "all levels")
    assertEqual("[DEBUG][Runtime] d", lines[1], "debug")
    assertEqual("[INFO][Runtime] i", lines[2], "info")
    assertEqual("[WARN][Runtime] w", lines[3], "warn")
    assertEqual("[ERROR][Runtime] e", lines[4], "error")
end)

test("omitted configure opts and nil level default to info", function()
    local lines = withCapture(function()
        local Logger = require("Logger")
        Logger.configure()
        Logger.debug("Runtime", "hidden")
        Logger.info("Runtime", "visible")
    end)
    assertEqual(1, #lines, "debug suppressed under default info")
    assertEqual("[INFO][Runtime] visible", lines[1], "info emits")

    lines = withCapture(function()
        local Logger = require("Logger")
        Logger.configure({ level = nil })
        Logger.debug("Runtime", "hidden")
        Logger.info("Runtime", "visible")
    end)
    assertEqual(1, #lines, "nil level is info")
    assertEqual("[INFO][Runtime] visible", lines[1], "info emits")
end)

test("unknown level falls back to info and emits one Logger warn", function()
    local lines = withCapture(function()
        local Logger = require("Logger")
        Logger.configure({ level = "verbose" })
        Logger.debug("Runtime", "hidden")
        Logger.info("Runtime", "visible")
    end)
    assertEqual(2, #lines, "warn plus info")
    assertTrue(lines[1]:find("%[WARN%]%[Logger%]", 1) == 1, "first line is Logger warn")
    assertTrue(lines[1]:find("verbose", 1, true) ~= nil, "warn mentions unknown value")
    assertEqual("[INFO][Runtime] visible", lines[2], "info after fallback")
end)

if failures > 0 then
    os.exit(1)
end
print("OK: logger_unit")
