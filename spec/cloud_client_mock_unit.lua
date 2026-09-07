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

test("mock submitJobRequest loads fixture and injects buffer materials", function()
    package.loaded["CloudClient"] = nil
    package.loaded["Comms"] = {
        requestJSONPost = function()
            error("HTTP should not run in mock mode")
        end,
        requestJSON = function()
            error("HTTP should not run in mock mode")
        end,
    }

    local CloudClient = require("CloudClient")
    local client = CloudClient.new({
        nodeId = "broker-alpha",
        useMockAssignment = true,
        mockAssignmentPath = "fixtures/mock_assignment.json",
    })

    local assignments, err = client:submitJobRequest({
        buffer = {
            items = {
                { name = "minecraft:iron_ingot", label = "Iron Ingot", size = 64 },
            },
            fluids = {
                { name = "water", label = "Water", amount = 1000 },
            },
        },
    })

    assertEqual(nil, err, "mock submit should succeed")
    assertTrue(assignments and #assignments == 1, "one assignment")
    local flow = assignments[1]:sequenceFlow()
    assertEqual("minecraft:iron_ingot", flow.items[1].name, "item name")
    assertEqual(64, flow.items[1].count, "item count from buffer size")
    assertEqual("water", flow.fluids[1].name, "fluid name")
    assertEqual(1000, flow.fluids[1].amount, "fluid amount")
    assertEqual("REPLACE_MACHINE_ADDRESS", assignments[1]:machineAddress(), "fixture machine")
end)

test("mock reportStatus and reportCompletion succeed without HTTP", function()
    package.loaded["CloudClient"] = nil
    package.loaded["Comms"] = {
        requestJSONPost = function()
            error("HTTP should not run in mock mode")
        end,
    }

    local CloudClient = require("CloudClient")
    local client = CloudClient.new({ useMockAssignment = true })

    local okStatus, statusErr = client:reportStatus({})
    assertEqual(true, okStatus, statusErr or "status ok")
    local okDone, doneErr = client:reportCompletion("job-mock-001", { success = true })
    assertEqual(true, okDone, doneErr or "completion ok")
end)

if failures > 0 then
    os.exit(1)
end
