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

test("ComponentCache reuses wrapper identity; Cache façades getComponent", function()
    mock_oc.reset()
    package.loaded.ComponentCache = nil
    package.loaded.Cache = nil

    local ComponentCache = require("ComponentCache")
    local components = ComponentCache.new()
    local first, err = components:getComponent("machine-lathe", "Machine")
    assert(first, err)
    local second = assert(components:getComponent("machine-lathe", "Machine"))
    eq(first, second, "ComponentCache identity")

    local Cache = require("Cache")
    local cache = Cache.new()
    local viaCache = assert(cache:getComponent("machine-assembler", "Machine"))
    local again = assert(cache:getComponent("machine-assembler", "Machine"))
    eq(viaCache, again, "Cache façade identity")
    eq("table", type(cache._components), "façade exposes or holds components via ComponentCache")
    -- Façade must own a ComponentCache (or be one); wrapper store is not duplicated as raw tables only.
    assert(cache._componentCache ~= nil or cache.getComponent == ComponentCache.getComponent,
        "Cache should wrap or share ComponentCache")
    local underlying = cache._componentCache or cache
    eq(viaCache, underlying:getComponent("machine-assembler", "Machine"), "façade shares ComponentCache store")

    cache:invalidate("machine-assembler")
    local rebuilt = assert(cache:getComponent("machine-assembler", "Machine"))
    eq(true, rebuilt ~= viaCache, "invalidate drops wrapper")
end)

test("NodeSensor owns buffer and machine-scan snapshots without Cache snapshot APIs", function()
    mock_oc.reset()
    package.loaded.Cache = nil
    package.loaded.ComponentCache = nil
    package.loaded.NodeSensor = nil

    local Cache = require("Cache")
    eq(nil, Cache.setLastBuffer, "Cache no longer stores buffer snapshots")
    eq(nil, Cache.getLastBuffer, "Cache no longer reads buffer snapshots")
    eq(nil, Cache.setLastMachineScan, "Cache no longer stores machine scans")
    eq(nil, Cache.getLastMachineScan, "Cache no longer reads machine scans")

    local cache = Cache.new()
    local NodeSensor = require("NodeSensor")
    local sensor = NodeSensor.new({
        meControllerAddr = "me-controller",
        machineFilter = "gt_machine",
        jobRequestCooldown = 0,
    }, cache)

    mock_oc.set_buffer(
        { { name = "minecraft:iron_ingot", label = "Iron Ingot", size = 64 } },
        {}
    )
    sensor:tick()
    local snap = sensor:bufferSnapshot()
    assert(snap and snap.items and #snap.items >= 1, "sensor owns buffer snapshot")
    local availability = sensor:machineAvailability()
    eq(true, #availability >= 1, "sensor owns machine scan")

    -- Second tick with same buffer must not treat cache as source of truth.
    sensor:markRequestSent()
    sensor:tick()
    eq(false, sensor:hasPendingRequest(), "unchanged buffer does not re-pend without cache snapshots")
end)

if failures > 0 then
    os.exit(1)
end
print("OK: topology_unit")
