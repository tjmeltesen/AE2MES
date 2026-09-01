package.path = "./src/?.lua;./lib/?.lua;./features/support/?.lua;" .. package.path

local assertions = require("assertions")
local world = require("world")

local DEMO_ASSIGNMENT_JSON = [[{
  "assignments": [{
    "jobId": "job-7f3a",
    "machineAddress": "abc-123",
    "registry": {
      "machineAddress": "abc-123",
      "transposerAddress": "def-456"
    },
    "sequenceFlow": {
      "steps": [
        { "type": "wait", "target": "machineAddress", "params": {} },
        { "type": "transfer", "target": "transposerAddress", "params": { "fromSide": 1 } }
      ]
    }
  }]
}]]

local function defaultRegistry()
    return {
        machineAddress = "machine-001",
        transposerAddress = "transposer-001",
        storeInterfaceAddress = "iface-store",
        stockInterfaceAddress = "iface-stock",
        databaseAddress = "db-001",
        redstoneAddress = "rs-001",
        sides = { transposerStore = 1, transposerStock = 2 },
    }
end

Given("cloud assignment JSON", function()
    world.lastValue = DEMO_ASSIGNMENT_JSON
end)

When("I parse assignment list from JSON", function()
    local Assignment = require("Assignment")
    world.assignments, world.lastError = Assignment.listFromJSON(world.lastValue)
end)

Then("there should be (%d+) assignment", function(count)
    assertions.assertTrue(world.assignments ~= nil, "assignments parsed")
    assertions.assertEqual(tonumber(count), #world.assignments, "assignment count")
end)

Then("assignment job id should be \"(.+)\"", function(jobId)
    assertions.assertEqual(jobId, world.assignments[1]:id(), "job id")
end)

Then("assignment step count should be (%d+)", function(count)
    assertions.assertEqual(tonumber(count), world.assignments[1]:sequenceFlow():stepCount(), "step count")
end)

Then("assignment step (%d+) type should be \"(.+)\"", function(index, stepType)
    local step = world.assignments[1]:sequenceFlow():stepAt(tonumber(index))
    assertions.assertEqual(stepType, step.type, "step type")
end)

Given("a registry from the parsed assignment", function()
    local Cache = require("Cache")
    local HardwareContext = require("HardwareContext")
    world.cache = Cache.new()
    world.assignment = world.assignments[1]
    world.hardware, world.lastError = HardwareContext.fromRegistry(world.assignment:registry(), world.cache)
end)

Then("hardware context should resolve transposer to \"(.+)\"", function(address)
    assertions.assertTrue(world.hardware ~= nil, "hardware context exists")
    assertions.assertEqual(address, world.hardware:resolve("transposerAddress"), "transposer address")
end)

When("I load machine from hardware context", function()
    world.lastValue = world.hardware:machine()
end)

Then("machine address should be \"(.+)\"", function(address)
    assertions.assertEqual(address, world.lastValue:getAddress(), "machine address")
end)

Given("a wait%-only assignment with (%d+) steps", function(count)
    local Assignment = require("Assignment")
    local steps = {}
    for _ = 1, tonumber(count) do
        table.insert(steps, { type = "wait", target = "machineAddress", params = {} })
    end
    world.assignment = Assignment.fromTable({
        jobId = "job-wait",
        machineAddress = "abc-123",
        registry = {
            machineAddress = "abc-123",
            transposerAddress = "def-456",
        },
        sequenceFlow = { steps = steps },
    })
end)

Given("a transfer assignment missing fromSide and toSide", function()
    local Assignment = require("Assignment")
    world.assignment = Assignment.fromJSON([[{
      "jobId": "job-transfer",
      "machineAddress": "abc-123",
      "registry": { "machineAddress": "abc-123", "transposerAddress": "def-456" },
      "sequenceFlow": {
        "steps": [ { "type": "transfer", "target": "transposerAddress", "params": {} } ]
      }
    }]])
end)

Given("a wait assignment with (%d+) ticks", function(ticks)
    local Assignment = require("Assignment")
    world.assignment = Assignment.fromTable({
        jobId = "job-test",
        machineAddress = "machine-001",
        registry = defaultRegistry(),
        sequenceFlow = {
            steps = {
                { type = "wait", target = "machineAddress", params = { ticks = tonumber(ticks) } },
            },
        },
    })
end)

Given("a transfer assignment with sides", function()
    local Assignment = require("Assignment")
    world.assignment = Assignment.fromTable({
        jobId = "job-test",
        machineAddress = "machine-001",
        registry = defaultRegistry(),
        sequenceFlow = {
            steps = {
                { type = "transfer", target = "transposerAddress", params = { fromSide = 1, toSide = 2, count = 4 } },
            },
        },
    })
end)

Given("a configure and clear assignment", function()
    local Assignment = require("Assignment")
    world.assignment = Assignment.fromTable({
        jobId = "job-test",
        machineAddress = "machine-001",
        registry = defaultRegistry(),
        sequenceFlow = {
            steps = {
                { type = "configure", target = "storeInterfaceAddress", params = { slot = 1, dbAddress = "db-001", dbSlot = 1, count = 1 } },
                { type = "clear", target = "databaseAddress", params = { slot = 1 } },
            },
        },
    })
end)

Given("a process assignment with timeout (%d+)", function(timeout)
    local Assignment = require("Assignment")
    world.assignment = Assignment.fromTable({
        jobId = "job-process",
        machineAddress = "machine-001",
        registry = defaultRegistry(),
        sequenceFlow = {
            steps = {
                { type = "process", target = "machineAddress", params = { timeout = tonumber(timeout) } },
            },
        },
    })
end)

Given("a transfer assignment with sides and zero moved", function()
    local mock_oc = require("mock_oc")
    mock_oc.set_transfer_count(0)
    local Assignment = require("Assignment")
    world.assignment = Assignment.fromTable({
        jobId = "job-test",
        machineAddress = "machine-001",
        registry = defaultRegistry(),
        sequenceFlow = {
            steps = {
                { type = "transfer", target = "transposerAddress", params = { fromSide = 1, toSide = 2 } },
            },
        },
    })
end)

When("I begin the executor", function()
    local Cache = require("Cache")
    local HardwareContext = require("HardwareContext")
    local Executor = require("Executor")

    world.cache = world.cache or Cache.new()
    world.hardware = HardwareContext.fromRegistry(world.assignment:registry(), world.cache)
    world.executor = Executor.new(world.cache, { verbose = false })
    world.executor:begin(
        world.hardware,
        world.assignment:sequenceFlow(),
        world.assignment:id(),
        world.assignment:machineAddress()
    )
end)

When("the executor ticks until inactive", function()
    world.tickCount = 0
    while world.executor:isActive() and world.tickCount < 20 do
        world.executor:tick()
        world.tickCount = world.tickCount + 1
    end
    world.lastPhase = world.executor:phase()
    world.lastResult = world.executor:result() or {}
end)

When("the executor ticks once", function()
    world.executor:tick()
    world.lastPhase = world.executor:phase()
    world.lastResult = world.executor:result() or {}
end)

When("the executor ticks (%d+) times", function(count)
    for _ = 1, tonumber(count) do
        world.executor:tick()
    end
    world.lastPhase = world.executor:phase()
    world.lastResult = world.executor:result() or {}
end)

Then("the executor phase should be \"(.+)\"", function(phase)
    assertions.assertEqual(phase, world.lastPhase, "executor phase")
end)

Then("the result should be ok", function()
    assertions.assertTrue(world.lastResult.ok == true, "result ok")
end)

Given("machine is active during process step", function()
    local mock_oc = require("mock_oc")
    mock_oc.set_machine_active("machine-001", true)
end)

When("machine becomes inactive", function()
    local mock_oc = require("mock_oc")
    mock_oc.set_machine_active("machine-001", false)
end)

Given("transposer returns zero items moved", function()
    local mock_oc = require("mock_oc")
    mock_oc.set_transfer_count(0)
end)
