package.path = "./src/?.lua;./lib/?.lua;./features/support/?.lua;" .. package.path

local assertions = require("assertions")
local world = require("world")

Given("a runtime with mock cloud", function()
    local Runtime = require("Runtime")
    world.runtime = Runtime.new({
        nodeId = "demo-node",
        cloudBaseUrl = "http://mes.local:8080",
        meControllerAddr = "me-controller",
        machineFilter = "gt_machine",
        statusInterval = 0,
        jobRequestCooldown = 0,
    })
end)

When("I tick runtime (%d+) times", function(count)
    for _ = 1, tonumber(count) do
        world.runtime:tick()
    end
    world.lastValue = world.runtime:activeJobCount()
end)

Then("runtime active job count should be (%d+)", function(count)
    assertions.assertEqual(tonumber(count), world.lastValue, "active job count")
end)

Then("runtime tick cycle should complete without error", function()
    assertions.assertTrue(world.runtime ~= nil, "runtime exists")
end)
