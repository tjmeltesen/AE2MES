package.path = "./src/?.lua;./lib/?.lua;./features/support/?.lua;" .. package.path

local assertions = require("assertions")
local world = require("world")

Given("a node sensor with ME controller", function()
    local ComponentCache = require("ComponentCache")
    local NodeSensor = require("NodeSensor")
    world.componentCache = ComponentCache.new()
    world.nodeSensor = NodeSensor.new({
        machineFilter = "gt_machine",
        meControllerAddr = "me-controller",
    }, world.componentCache)
end)

When("I scan machines", function()
    world.lastTable = world.nodeSensor:scanMachines()
end)

Then("discovered machine count should be (%d+)", function(count)
    assertions.assertEqual(tonumber(count), #world.lastTable, "machine count")
end)

When("job pool has busy machine \"(.+)\"", function(machineAddr)
    local JobPool = require("JobPool")
    local Assignment = require("Assignment")
    -- Harness mode: no NodeCache, so wait-step concurrency tests can wire via configureFromRegistry.
    world.jobPool = JobPool.new({})
    world.jobPool:spawn(Assignment.fromTable({
        jobId = "job-busy",
        machineAddress = machineAddr,
        registry = {
            machineAddress = machineAddr,
            transposerAddress = "transposer-shared",
        },
        sequenceFlow = {
            steps = {
                { type = "wait", target = "machineAddress", params = {} },
            },
        },
    }))
end)

When("I merge job pool busy flags", function()
    world.lastTable = world.nodeSensor:machineAvailability(world.jobPool)
end)

Then("machine \"(.+)\" should be busy", function(machineAddr)
    for _, entry in ipairs(world.lastTable) do
        if entry.machineAddress == machineAddr then
            assertions.assertTrue(entry.busy == true, machineAddr .. " busy")
            return
        end
    end
    error("machine not found: " .. machineAddr)
end)

When("I tick node sensor", function()
    world.componentCache:getComponent("me-controller", "MeControllerComponent")
    world.nodeSensor:tick()
end)

Then("node sensor should have pending request", function()
    assertions.assertTrue(world.nodeSensor:hasPendingRequest(), "pending request")
end)

Then("buffer snapshot should have at least (%d+) items", function(count)
    local snap = world.nodeSensor:bufferSnapshot()
    assertions.assertTrue(snap ~= nil, "snapshot exists")
    assertions.assertTrue(#snap.items >= tonumber(count), "buffer items")
end)
