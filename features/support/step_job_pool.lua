package.path = "./src/?.lua;./lib/?.lua;./features/support/?.lua;" .. package.path

local assertions = require("assertions")
local world = require("world")

local function makeWaitJob(jobId, machineAddr)
    local Assignment = require("Assignment")
    return Assignment.fromTable({
        jobId = jobId,
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
    })
end

Given("an empty job pool", function()
    local JobPool = require("JobPool")
    -- Harness mode: no NodeCache, so wait-step concurrency tests can wire via configureFromRegistry.
    world.cache = nil
    world.jobPool = JobPool.new({})
end)

When("I spawn job \"(.+)\" on \"(.+)\"", function(jobId, machineAddr)
    local ok, err = world.jobPool:spawn(makeWaitJob(jobId, machineAddr))
    world.lastValue = ok
    world.lastError = err
end)

Then("spawn should succeed", function()
    assertions.assertTrue(world.lastValue == true, "spawn succeeded")
end)

Then("spawn should fail", function()
    assertions.assertTrue(world.lastValue ~= true, "spawn failed")
end)

Then("active job count should be (%d+)", function(count)
    assertions.assertEqual(tonumber(count), world.jobPool:activeCount(), "active count")
end)

When("I tick the job pool until (%d+) jobs complete", function(expectedDone)
    world.lastTable = { done = {}, faulted = {} }
    for _ = 1, 5 do
        local done, faulted = world.jobPool:tick()
        for _, jobId in ipairs(done) do
            table.insert(world.lastTable.done, jobId)
        end
        for _, jobId in ipairs(faulted) do
            table.insert(world.lastTable.faulted, jobId)
        end
        if #world.lastTable.done >= tonumber(expectedDone) then
            break
        end
    end
end)

Then("completed jobs count should be (%d+)", function(count)
    assertions.assertEqual(tonumber(count), #world.lastTable.done, "completed jobs")
end)

Then("faulted jobs count should be (%d+)", function(count)
    assertions.assertEqual(tonumber(count), #world.lastTable.faulted, "faulted jobs")
end)
