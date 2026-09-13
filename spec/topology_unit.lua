package.path = "./src/?.lua;./lib/?.lua;./features/support/?.lua;" .. package.path

local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("PASS: " .. name)
    else
        failures = failures + 1
        print("FAIL: " .. name .. " - " .. tostring(err))
    end
end
local function eq(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local mock_oc = require("mock_oc")

test("hardware observation puts machineAddresses on globals for initialize", function()
    mock_oc.reset()
    mock_oc.set_proxy_override("transposer-001", {
        getInventorySize = function(side) return side == 2 and 16 or nil end,
        getInventoryName = function(side) return side == 2 and "input bus" or nil end,
    })

    package.loaded.ComponentDiscovery = nil
    package.loaded.HardwareDiscovery = nil
    package.loaded.CloudClient = nil
    package.loaded.Comms = nil

    local posted
    package.loaded.Comms = {
        requestJSONPost = function(_, url, payload)
            posted = { url = url, payload = payload }
            return {
                ready = false,
                topologyRevision = 1,
                clusterStatus = "INITIALIZING",
                machines = {},
            }
        end,
        requestJSON = function()
            error("unexpected GET")
        end,
    }

    local Discovery = require("HardwareDiscovery")
    local observation = assert(Discovery.discover({ clusterId = "cluster-a" }))

    eq("table", type(observation.globals.machineAddresses), "globals.machineAddresses present")
    eq(2, #observation.globals.machineAddresses, "machine address count")
    eq("machine-assembler", observation.globals.machineAddresses[1], "sorted first machine")
    eq("machine-lathe", observation.globals.machineAddresses[2], "sorted second machine")
    eq(2, #observation.components.machines, "components.machines retained")
    eq(2, #observation.components.interfaces, "components.interfaces retained")
    eq(1, #observation.components.transposers, "components.transposers retained")
    eq(true, observation.components.transposers[1].sides ~= nil
        and #observation.components.transposers[1].sides > 0, "transposer side hints")

    local CloudClient = require("CloudClient")
    local client = CloudClient.new({
        clusterId = "cluster-a",
        cloudBaseUrl = "https://mes",
        useMockAssignment = false,
    })
    assert(client:initialize(observation))
    eq("https://mes/clusters/cluster-a/initialize", posted.url, "initialize URL")
    eq(observation.globals.machineAddresses, posted.payload.globals.machineAddresses, "posted globals.machineAddresses")
    eq(2, #posted.payload.components.machines, "posted machines")
    eq(2, #posted.payload.components.interfaces, "posted interfaces")
    eq(1, #posted.payload.components.transposers, "posted transposers")
end)

test("discovers full topology and produces stable fingerprints", function()
    mock_oc.reset()
    mock_oc.set_proxy_override("transposer-001", {
        getInventorySize = function(side) return side == 2 and 16 or nil end,
        getInventoryName = function(side) return side == 2 and "input bus" or nil end,
    })
    package.loaded.ComponentDiscovery = nil
    package.loaded.HardwareDiscovery = nil
    local ComponentDiscovery = require("ComponentDiscovery")
    local first = assert(ComponentDiscovery.discover({ clusterId = "cluster-a" }))
    local second = assert(ComponentDiscovery.discover({ clusterId = "cluster-a" }))
    eq("me-controller", first.globals.meControllerAddress, "ME address")
    eq(2, #first.components.machines, "machine count")
    eq(1, #first.components.transposers, "transposer count")
    eq(2, first.components.transposers[1].sides[1].side, "discovered side")
    eq(first.fingerprint, second.fingerprint, "fingerprint stability")
    eq(2, #first.globals.machineAddresses, "globals.machineAddresses in fingerprint inputs")
end)

if failures > 0 then
    os.exit(1)
end
print("OK: topology_unit")
