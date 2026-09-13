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

test("fromMapping builds READY node from machine mapping + ComponentCache Globals", function()
    mock_oc.reset()
    package.loaded.ComponentCache = nil
    package.loaded.NodeComponent = nil
    package.loaded.Interface = nil
    package.loaded.Machine = nil
    package.loaded.TransposerComponent = nil
    package.loaded.DatabaseComponent = nil
    package.loaded.RedstoneComponent = nil

    local ComponentCache = require("ComponentCache")
    local NodeComponent = require("NodeComponent")
    local cache = ComponentCache.new()

    local database = assert(cache:getComponent("db-staging", "DatabaseComponent", 9))
    assert(cache:getComponent("redstone-001", "RedstoneComponent"))
    assert(cache:getComponent("machine-lathe", "Machine"))
    assert(cache:getComponent("transposer-001", "TransposerComponent"))

    local mapping = {
        machineAddress = "machine-lathe",
        interfaceAddress = "iface-lathe",
        transposerAddress = "transposer-001",
        transposerSides = { pull = 3, input = 2, returnSide = 4 },
        mappingRevision = 3,
        status = "READY",
    }
    local globals = {
        databaseAddress = "db-staging",
        databaseSize = 9,
        redstoneAddress = "redstone-001",
        redstoneSides = { start = 0, stop = 1 },
    }

    local node, err = NodeComponent:fromMapping(mapping, globals, cache)
    assert(node, err)
    eq(database, node.database, "sticky Global database identity")
    eq("machine-lathe", node.machine and node.machine.address, "machine from mapping")
    eq("iface-lathe", node.interface and node.interface.address, "interface from mapping")
    eq("transposer-001", node.transposer and node.transposer.address, "transposer from mapping")
    eq(3, node.transposerSides.pull, "transposer sides applied")
    eq(0, node.redstoneSides.start, "cluster redstone sides from Globals")
    eq(3, node.mappingRevision, "mappingRevision retained")
    eq("machine-lathe", node.machineAddress, "address fields for mergeRegistry")
end)

test("NodeCache build/get/retire generations; Cache façades node APIs", function()
    mock_oc.reset()
    package.loaded.ComponentCache = nil
    package.loaded.NodeCache = nil
    package.loaded.Cache = nil
    package.loaded.NodeComponent = nil

    local Cache = require("Cache")
    local cache = Cache.new()
    assert(cache:getComponent("db-staging", "DatabaseComponent", 9))
    assert(cache:getComponent("redstone-001", "RedstoneComponent"))
    assert(cache:getComponent("machine-lathe", "Machine"))
    assert(cache:getComponent("transposer-001", "TransposerComponent"))

    local mapping = {
        machineAddress = "machine-lathe",
        interfaceAddress = "iface-lathe",
        transposerAddress = "transposer-001",
        transposerSides = { pull = 3, input = 2 },
        mappingRevision = 1,
        status = "READY",
    }
    local globals = {
        databaseAddress = "db-staging",
        databaseSize = 9,
        redstoneAddress = "redstone-001",
        redstoneSides = { start = 0, stop = 1 },
    }

    eq(nil, cache:getNode("machine-lathe"), "no node before READY build")

    local first, err = cache:buildNode(mapping, globals)
    assert(first, err)
    eq(first, cache:getNode("machine-lathe"), "get current after build")
    eq(1, first.cacheGeneration, "first generation")
    eq(1, first.mappingRevision, "mappingRevision on node")

    mapping.mappingRevision = 2
    mapping.interfaceAddress = "iface-lathe-b"
    local second = assert(cache:buildNode(mapping, globals))
    eq(second, cache:getNode("machine-lathe"), "rebuild replaces current")
    eq(2, second.cacheGeneration, "second generation")
    eq(true, first ~= second, "new generation is distinct node")
    eq(1, first.cacheGeneration, "prior generation retained until retire")

    cache:retireGeneration("machine-lathe", 1)
    eq(second, cache:getNode("machine-lathe"), "current survives retire of prior")
    -- Retiring current is a no-op for getNode semantics until a newer build.
    cache:retireGeneration("machine-lathe", 2)
    eq(second, cache:getNode("machine-lathe"), "current generation is not dropped by retire")

    assert(cache._nodeCache ~= nil, "Cache façades NodeCache")
    eq(second, cache._nodeCache:get("machine-lathe"), "façade shares NodeCache store")
end)

test("interfaces are created lazily on READY mapping, not at discovery", function()
    mock_oc.reset()
    package.loaded.ComponentCache = nil
    package.loaded.Cache = nil
    package.loaded.ComponentDiscovery = nil
    package.loaded.HardwareDiscovery = nil
    package.loaded.Interface = nil
    package.loaded.NodeComponent = nil
    package.loaded.NodeCache = nil

    local Interface = require("Interface")
    local constructions = 0
    local originalNew = Interface.new
    Interface.new = function(self, address, databaseObj)
        constructions = constructions + 1
        return originalNew(self, address, databaseObj)
    end

    local Cache = require("Cache")
    local cache = Cache.new()
    mock_oc.set_proxy_override("transposer-001", {
        getInventorySize = function(side) return side == 2 and 16 or nil end,
        getInventoryName = function(side) return side == 2 and "input bus" or nil end,
    })

    local Discovery = require("HardwareDiscovery")
    local observation = assert(Discovery.discover({ clusterId = "cluster-a" }, cache))
    eq(0, constructions, "discovery does not construct interface wrappers")

    assert(cache:getComponent("machine-lathe", "Machine"))
    assert(cache:getComponent(observation.globals.meControllerAddress, "MeControllerComponent"))
    assert(cache:getComponent(observation.globals.databaseAddress, "DatabaseComponent",
        observation.globals.databaseSize))
    assert(cache:getComponent(observation.globals.redstoneAddress, "RedstoneComponent"))
    eq(0, constructions, "eager Globals do not construct interfaces")

    local mapping = {
        machineAddress = "machine-lathe",
        interfaceAddress = "iface-store",
        transposerAddress = "transposer-001",
        transposerSides = { pull = 3, input = 2 },
        mappingRevision = 1,
        status = "READY",
    }
    local globals = {
        databaseAddress = observation.globals.databaseAddress,
        databaseSize = observation.globals.databaseSize,
        redstoneAddress = observation.globals.redstoneAddress,
        redstoneSides = { start = 0, stop = 1 },
    }

    local node = assert(cache:buildNode(mapping, globals))
    eq(1, constructions, "READY mapping creates interface wrapper once")
    eq("iface-store", node.interface.address, "interface wired on node")

    mapping.status = "UNMAPPED"
    local rejected, rejectErr = cache:buildNode(mapping, globals)
    eq(nil, rejected, "non-READY mapping does not build")
    eq(true, type(rejectErr) == "string" and rejectErr:find("READY", 1, true) ~= nil,
        "non-READY build reports READY requirement")
    eq(1, constructions, "non-READY path does not construct another interface")

    Interface.new = originalNew
end)

local function seedGlobals(cache)
    assert(cache:getComponent("db-staging", "DatabaseComponent", 9))
    assert(cache:getComponent("redstone-001", "RedstoneComponent"))
    assert(cache:getComponent("machine-lathe", "Machine"))
    assert(cache:getComponent("transposer-001", "TransposerComponent"))
    assert(cache:getComponent("transposer-002", "TransposerComponent"))
end

local function baseGlobals(redstoneSides)
    return {
        databaseAddress = "db-staging",
        databaseSize = 9,
        redstoneAddress = "redstone-001",
        redstoneSides = redstoneSides or { start = 0, stop = 1 },
        meControllerAddress = "me-controller",
    }
end

local function readyMapping(overrides)
    local mapping = {
        machineAddress = "machine-lathe",
        interfaceAddress = "iface-lathe",
        transposerAddress = "transposer-001",
        transposerSides = { pull = 3, input = 2, returnSide = 4 },
        mappingRevision = 1,
        status = "READY",
    }
    for key, value in pairs(overrides or {}) do
        mapping[key] = value
    end
    return mapping
end

local function assignmentFor(mapping, jobId)
    return {
        jobId = jobId or "job-1",
        machineAddress = mapping.machineAddress,
        registry = {
            machineAddress = mapping.machineAddress,
            interfaceAddress = mapping.interfaceAddress,
            transposerAddress = mapping.transposerAddress,
            transposerSides = mapping.transposerSides,
        },
        sequenceFlow = {
            items = {},
            fluids = {},
            steps = { { method = "wait", params = { ticks = 99 } } },
        },
    }
end

local function makeRuntimeHarness(cache, globals)
    package.loaded.JobPool = nil
    package.loaded.Runtime = nil
    local JobPool = require("JobPool")
    local Runtime = require("Runtime")
    local machineStatuses = { ["machine-lathe"] = "UNMAPPED" }
    local pool = JobPool.new({
        cache = cache,
        globals = globals,
        machineStatus = function(address) return machineStatuses[address] end,
        onTopologyConflict = function(address, reason)
            machineStatuses[address] = "NEEDS_REVIEW"
            pool._lastConflict = { address = address, reason = reason }
        end,
    })
    local runtime = setmetatable({
        _cache = cache,
        _jobPool = pool,
        _machineStatuses = machineStatuses,
        _observation = { globals = globals },
        _topologyRevision = 0,
        _clusterStatus = "INITIALIZING",
        _state = "INITIALIZING",
        _config = {
            meControllerAddr = globals.meControllerAddress,
            databaseAddress = globals.databaseAddress,
            databaseSize = globals.databaseSize,
            redstoneAddress = globals.redstoneAddress,
        },
        _meController = assert(cache:getComponent(globals.meControllerAddress, "MeControllerComponent")),
        _database = assert(cache:getComponent(globals.databaseAddress, "DatabaseComponent", globals.databaseSize)),
        _redstone = assert(cache:getComponent(globals.redstoneAddress, "RedstoneComponent")),
        _topologyProblems = {},
    }, Runtime)
    return runtime, pool, machineStatuses
end

test("JobPool submit reuses NodeCache node; missing node is topology_changed", function()
    mock_oc.reset()
    package.loaded.Cache = nil
    package.loaded.ComponentCache = nil
    package.loaded.NodeCache = nil
    package.loaded.NodeComponent = nil
    package.loaded.JobPool = nil
    package.loaded.Assignment = nil

    local Cache = require("Cache")
    local JobPool = require("JobPool")
    local cache = Cache.new()
    seedGlobals(cache)
    local globals = baseGlobals()
    local mapping = readyMapping()
    local node = assert(cache:buildNode(mapping, globals))

    local statuses = { ["machine-lathe"] = "READY" }
    local pool = JobPool.new({
        cache = cache,
        globals = globals,
        machineStatus = function(address) return statuses[address] end,
    })

    local ok, err = pool:submit(assignmentFor(mapping, "job-reuse"))
    eq(true, ok, "submit accepted: " .. tostring(err))
    local run = pool:get("job-reuse")
    assert(run and run.node, "run has node")
    eq(node, run.node, "assignment reuses topology-owned node")

    local emptyCache = Cache.new()
    seedGlobals(emptyCache)
    local orphanPool = JobPool.new({
        cache = emptyCache,
        globals = globals,
        machineStatus = function() return "READY" end,
    })
    local rejected, rejectErr = orphanPool:submit(assignmentFor(mapping, "job-missing"))
    eq(false, rejected, "missing node rejects submit")
    eq(true, type(rejectErr) == "string" and rejectErr:find("topology_changed", 1, true) ~= nil,
        "missing node reports topology_changed")
    eq(nil, emptyCache:getNode("machine-lathe"), "reject does not invent a NodeCache entry")
end)

test("registry conflict quarantines without overwriting cached mapping", function()
    mock_oc.reset()
    package.loaded.Cache = nil
    package.loaded.JobPool = nil
    package.loaded.Runtime = nil
    package.loaded.NodeComponent = nil

    local Cache = require("Cache")
    local cache = Cache.new()
    seedGlobals(cache)
    assert(cache:getComponent("me-controller", "MeControllerComponent"))
    local globals = baseGlobals()
    local mapping = readyMapping()
    local node = assert(cache:buildNode(mapping, globals))
    local interfaceBefore = node.interfaceAddress
    local transposerBefore = node.transposerAddress

    local runtime, pool, statuses = makeRuntimeHarness(cache, globals)
    statuses["machine-lathe"] = "READY"
    pool._onTopologyConflict = function(address, reason)
        runtime:_quarantineMachine(address, reason)
    end

    local conflicting = assignmentFor({
        machineAddress = "machine-lathe",
        interfaceAddress = "iface-other",
        transposerAddress = mapping.transposerAddress,
        transposerSides = mapping.transposerSides,
    }, "job-conflict")
    local ok, err = pool:submit(conflicting)
    eq(false, ok, "conflicting registry rejected")
    eq(true, type(err) == "string" and err:find("topology_changed", 1, true) ~= nil,
        "conflict reports topology_changed")
    eq("NEEDS_REVIEW", statuses["machine-lathe"], "machine quarantined")
    local still = cache:getNode("machine-lathe")
    eq(node, still, "NodeCache current generation unchanged")
    eq(interfaceBefore, still.interfaceAddress, "interface mapping preserved")
    eq(transposerBefore, still.transposerAddress, "transposer mapping preserved")
end)

test("topology apply rebuilds on binding, mappingRevision, and Global fingerprint change", function()
    mock_oc.reset()
    package.loaded.Cache = nil
    package.loaded.JobPool = nil
    package.loaded.Runtime = nil
    package.loaded.NodeComponent = nil

    local Cache = require("Cache")
    local cache = Cache.new()
    seedGlobals(cache)
    assert(cache:getComponent("me-controller", "MeControllerComponent"))
    local globals = baseGlobals()
    local runtime = makeRuntimeHarness(cache, globals)

    local mapping = readyMapping()
    assert(runtime:_applyTopologyResponse({
        ready = true,
        topologyRevision = 1,
        clusterStatus = "READY",
        cluster = { redstoneSides = globals.redstoneSides },
        machines = { mapping },
    }))
    local first = assert(cache:getNode("machine-lathe"))
    eq(1, first.mappingRevision, "initial revision")
    eq("iface-lathe", first.interfaceAddress, "initial interface")

    -- Same mappingRevision, different bindings → rebuild (not quarantine).
    local rebound = readyMapping({
        interfaceAddress = "iface-lathe-b",
        mappingRevision = 1,
    })
    assert(runtime:_applyTopologyResponse({
        ready = true,
        topologyRevision = 2,
        clusterStatus = "READY",
        cluster = { redstoneSides = globals.redstoneSides },
        machines = { rebound },
    }))
    local afterBinding = assert(cache:getNode("machine-lathe"))
    eq(true, afterBinding ~= first, "binding change rebuilds node")
    eq("iface-lathe-b", afterBinding.interfaceAddress, "new interface applied")
    eq("READY", runtime._machineStatuses["machine-lathe"], "binding rebuild stays READY")

    -- mappingRevision bump → rebuild.
    local revised = readyMapping({
        interfaceAddress = "iface-lathe-b",
        mappingRevision = 2,
    })
    assert(runtime:_applyTopologyResponse({
        ready = true,
        topologyRevision = 3,
        clusterStatus = "READY",
        cluster = { redstoneSides = globals.redstoneSides },
        machines = { revised },
    }))
    local afterRevision = assert(cache:getNode("machine-lathe"))
    eq(true, afterRevision ~= afterBinding, "mappingRevision bump rebuilds")
    eq(2, afterRevision.mappingRevision, "revision updated")

    -- Global fingerprint change (redstone sides) → rebuild even with same mapping.
    assert(runtime:_applyTopologyResponse({
        ready = true,
        topologyRevision = 4,
        clusterStatus = "READY",
        cluster = { redstoneSides = { start = 2, stop = 3 } },
        machines = { revised },
    }))
    local afterGlobal = assert(cache:getNode("machine-lathe"))
    eq(true, afterGlobal ~= afterRevision, "Global fingerprint change rebuilds")
    eq(2, afterGlobal.redstoneSides.start, "cluster redstone sides applied")
end)

test("active generation kept across rebuild; retire when safe", function()
    mock_oc.reset()
    package.loaded.Cache = nil
    package.loaded.JobPool = nil
    package.loaded.Runtime = nil
    package.loaded.NodeComponent = nil

    local Cache = require("Cache")
    local cache = Cache.new()
    seedGlobals(cache)
    assert(cache:getComponent("me-controller", "MeControllerComponent"))
    local globals = baseGlobals()
    local runtime, pool, statuses = makeRuntimeHarness(cache, globals)

    local mapping = readyMapping()
    assert(runtime:_applyTopologyResponse({
        ready = true,
        topologyRevision = 1,
        clusterStatus = "READY",
        cluster = { redstoneSides = globals.redstoneSides },
        machines = { mapping },
    }))
    local gen1 = assert(cache:getNode("machine-lathe"))
    statuses["machine-lathe"] = "READY"
    assert(pool:submit(assignmentFor(mapping, "job-active")))
    eq(gen1.cacheGeneration, pool:activeGeneration("machine-lathe"), "active holds gen1")

    local revised = readyMapping({ mappingRevision = 2, interfaceAddress = "iface-next" })
    assert(runtime:_applyTopologyResponse({
        ready = true,
        topologyRevision = 2,
        clusterStatus = "READY",
        cluster = { redstoneSides = globals.redstoneSides },
        machines = { revised },
    }))
    local gen2 = assert(cache:getNode("machine-lathe"))
    eq(true, gen2 ~= gen1, "rebuild creates new current generation")
    eq(gen1, pool:get("job-active").node, "active run still holds prior generation")
    eq(gen1.cacheGeneration, pool:activeGeneration("machine-lathe"), "activeGeneration stays gen1")
    eq(gen2, cache:getNode("machine-lathe"), "getNode returns current gen2")
    eq(true, cache:hasGeneration("machine-lathe", gen1.cacheGeneration),
        "NodeCache retains active prior generation across rebuild")
    eq(true, cache:hasGeneration("machine-lathe", gen2.cacheGeneration),
        "NodeCache retains current generation")

    -- Mistaken early retire must not drop the generation Runtime still considers active;
    -- Runtime skips retire while activeGeneration matches. Direct retire is only safe after remove.
    pool:remove("job-active")
    eq(false, cache:hasGeneration("machine-lathe", gen1.cacheGeneration),
        "prior generation retired when job is removed")
    eq(gen2, cache:getNode("machine-lathe"), "current survives safe retire of prior")
end)

test("mock initialize yields READY mappings consumable by NodeCache", function()
    mock_oc.reset()
    mock_oc.set_proxy_override("transposer-001", {
        getInventorySize = function(side) return side == 2 and 16 or nil end,
        getInventoryName = function(side) return side == 2 and "input bus" or nil end,
    })
    package.loaded.Cache = nil
    package.loaded.ComponentCache = nil
    package.loaded.NodeCache = nil
    package.loaded.NodeComponent = nil
    package.loaded.CloudClient = nil
    package.loaded.Comms = nil
    package.loaded.HardwareDiscovery = nil
    package.loaded.ComponentDiscovery = nil

    package.loaded.Comms = {
        requestJSONPost = function() error("HTTP should not run in mock initialize") end,
        requestJSON = function() error("HTTP should not run in mock initialize") end,
    }

    local Cache = require("Cache")
    local Discovery = require("HardwareDiscovery")
    local CloudClient = require("CloudClient")
    local cache = Cache.new()
    local observation = assert(Discovery.discover({ clusterId = "cluster-a" }, cache))
    local client = CloudClient.new({
        clusterId = "cluster-a",
        useMockAssignment = true,
        mockAssignmentPath = "fixtures/mock_assignment.json",
    })
    local response = assert(client:initialize(observation))
    eq(true, response.ready, "mock initialize ready")
    eq("READY", response.clusterStatus, "mock cluster READY")
    local mapping = response.machines and response.machines[1]
    assert(mapping, "mock returns a machine mapping")
    eq("READY", mapping.status, "mapping READY")
    eq(true, type(mapping.machineAddress) == "string" and not mapping.machineAddress:find("^REPLACE_"),
        "machine address resolved from observation")
    eq(true, type(mapping.interfaceAddress) == "string" and not mapping.interfaceAddress:find("^REPLACE_"),
        "interface address resolved")
    eq(true, type(mapping.transposerAddress) == "string" and not mapping.transposerAddress:find("^REPLACE_"),
        "transposer address resolved")

    local globals = {
        databaseAddress = observation.globals.databaseAddress,
        databaseSize = observation.globals.databaseSize,
        redstoneAddress = observation.globals.redstoneAddress,
        redstoneSides = response.cluster.redstoneSides,
    }
    local node, err = cache:buildNode(mapping, globals)
    assert(node, err)
    eq(mapping.machineAddress, node.machineAddress, "NodeCache consumes mock mapping")
    eq(mapping.mappingRevision, node.mappingRevision, "mappingRevision applied")
end)

if failures > 0 then
    os.exit(1)
end
print("OK: topology_unit")
