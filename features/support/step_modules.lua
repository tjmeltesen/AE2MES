package.path = "./src/?.lua;./lib/?.lua;./features/support/?.lua;" .. package.path

local assertions = require("assertions")
local mock_oc = require("mock_oc")
local world = require("world")

local MODULES = {
    { file = "lib/JSON.lua", module = "JSON" },
    { file = "lib/BaseComponent.lua", module = "BaseComponent", isClass = true },
    { file = "lib/Machine.lua", module = "Machine", isClass = true },
    { file = "lib/DatabaseComponent.lua", module = "DatabaseComponent", isClass = true },
    { file = "lib/TransposerComponent.lua", module = "TransposerComponent", isClass = true },
    { file = "lib/RedstoneComponent.lua", module = "RedstoneComponent", isClass = true },
    { file = "lib/Interface.lua", module = "Interface", isClass = true },
    { file = "lib/MeControllerComponent.lua", module = "MeControllerComponent", isClass = true },
    { file = "lib/Comms.lua", module = "Comms" },
    { file = "src/Cache.lua", module = "Cache", isClass = true },
    { file = "src/HardwareContext.lua", module = "HardwareContext" },
    { file = "src/Executor.lua", module = "Executor", isClass = true },
    { file = "src/JobPool.lua", module = "JobPool", isClass = true },
    { file = "src/NodeSensor.lua", module = "NodeSensor", isClass = true },
    { file = "src/CloudClient.lua", module = "CloudClient", isClass = true },
    { file = "src/Runtime.lua", module = "Runtime", isClass = true },
}

Given("all AE2%-ES2 modules are loadable", function()
    for _, entry in ipairs(MODULES) do
        local chunk, err = loadfile(entry.file)
        assertions.assertTrue(chunk ~= nil, entry.file .. " syntax: " .. tostring(err))

        local ok, mod = pcall(require, entry.module)
        assertions.assertTrue(ok, entry.module .. " load: " .. tostring(mod))
        assertions.assertTrue(type(mod) == "table", entry.module .. " returns table")

        if entry.isClass then
            assertions.assertTrue(type(mod.new) == "function", entry.module .. " has new()")
        end
    end
end)

Given("a machine with processing sensor lines", function()
    mock_oc.set_proxy_override("mock-machine-001", {
        getSensorInformation = function()
            return {
                "Progress: 32 s / 75 s",
                "Stored Energy: 16,896 EU / 16,896 EU",
                "Currently uses: 1,920 EU/t",
                "Max Energy Income: 2,048 EU/t(*2A) Tier: EV",
                "Problems: 0 Efficiency: 100.0 %",
                "Pollution reduced to: 100 %",
            }
        end,
    })
end)

When("I parse machine sensor information", function()
    local Machine = require("Machine")
    local machine = Machine:new("mock-machine-001")
    world.lastTable = machine:parseSensorInformation()
    world.lastValue = machine:pollAvailability()
end)

Then("machine progress should be (%d+) of (%d+)", function(current, max)
    assertions.assertEqual(tonumber(current), world.lastTable.progress.current, "progress current")
    assertions.assertEqual(tonumber(max), world.lastTable.progress.max, "progress max")
end)

Then("machine availability should be unavailable due to processing", function()
    assertions.assertTrue(world.lastValue.available == false, "should be unavailable")
    assertions.assertTrue(
        world.lastValue.unavailableReason:find("processing", 1, true) ~= nil,
        "reason should mention processing"
    )
end)

Given("a machine with sensor problems (%d+)", function(problems)
    mock_oc.set_proxy_override("mock-machine-001", {
        getSensorInformation = function()
            return { "Problems: " .. problems .. " Efficiency: 50.0 %" }
        end,
    })
end)

Then("machine availability should be unavailable due to problems", function()
    assertions.assertTrue(world.lastValue.available == false, "should be unavailable")
    assertions.assertTrue(
        world.lastValue.unavailableReason:find("problems:", 1, true) ~= nil,
        "reason should mention problems"
    )
end)

When("I format zero%-indexed ME items", function()
    local NetworkItems = require("NetworkItems")
    world.lastTable = NetworkItems.formatItems({
        [0] = { name = "minecraft:cobblestone", size = 1, label = "Cobble" },
        [1] = { name = "minecraft:dirt", size = 2, label = "Dirt" },
    })
end)

Then("formatted items count should be (%d+)", function(count)
    assertions.assertEqual(tonumber(count), #world.lastTable, "formatted items count")
end)

When("I read ME controller buffer snapshot", function()
    local MeControllerComponent = require("MeControllerComponent")
    local controller = MeControllerComponent:new("me-ctrl-test")
    world.lastTable = controller:getBufferSnapshot()
end)

Then("buffer snapshot should have at least (%d+) items and (%d+) fluids", function(items, fluids)
    assertions.assertTrue(world.lastTable ~= nil, "snapshot exists")
    assertions.assertTrue(#world.lastTable.items >= tonumber(items), "items count")
    assertions.assertTrue(#world.lastTable.fluids >= tonumber(fluids), "fluids count")
end)

When("I format zero%-indexed ME fluids", function()
    local NetworkItems = require("NetworkItems")
    world.lastTable = NetworkItems.formatFluids({
        [0] = { name = "lava", label = "Lava", amount = 500 },
        [1] = { name = "water", label = "Water", amount = 1000 },
    })
end)

Then("formatted fluids count should be (%d+)", function(count)
    assertions.assertEqual(tonumber(count), #world.lastTable, "formatted fluids count")
end)

When("I format iterator%-style ME items", function()
    local NetworkItems = require("NetworkItems")
    local items = {
        { name = "minecraft:gold_ingot", label = "Gold Ingot", size = 8, damage = 0 },
    }
    local index = 0
    local iterator = function()
        index = index + 1
        return items[index]
    end
    world.lastTable = NetworkItems.formatItems(iterator)
end)
