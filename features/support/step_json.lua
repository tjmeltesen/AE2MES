package.path = "./src/?.lua;./lib/?.lua;./features/support/?.lua;" .. package.path

local assertions = require("assertions")
local mock_oc = require("mock_oc")
local world = require("world")
local JSON = require("JSON")

Before(function()
    mock_oc.reset()
    world.reset()
end)

Given("JSON null", function()
    world.lastValue = JSON.null
end)

Given("JSON input \"(.+)\"", function(input)
    world.lastValue = input
end)

Given("JSON value (.+)", function(encoded)
    world.lastValue = JSON.decode(encoded)
end)

When("I decode the JSON input", function()
    world.lastValue = JSON.decode(world.lastValue)
end)

When("I encode the JSON value", function()
    world.lastEncoded = JSON.encode(world.lastValue)
    world.lastValue = world.lastEncoded
end)

When("I round%-trip the JSON value", function()
    local encoded = JSON.encode(world.lastValue)
    world.lastValue = JSON.decode(encoded)
end)

Then("the decoded value should equal (.+)", function(expectedEncoded)
    assertions.assertDeepEqual(JSON.decode(expectedEncoded), world.lastValue, "decoded value")
end)

Then("the encoded value should be \"(.+)\"", function(expected)
    assertions.assertEqual(expected, world.lastEncoded, "encoded value")
end)

Then("the round%-tripped value should equal the original", function()
    assertions.assertDeepEqual(world.lastTable, world.lastValue, "round-trip")
end)

Given("a JSON table", function()
    world.lastTable = world.lastTable or {}
    world.lastValue = world.lastTable
end)

Given("table field \"(.+)\" is (.+)", function(key, encoded)
    world.lastTable = world.lastTable or {}
    world.lastTable[key] = JSON.decode(encoded)
    world.lastValue = world.lastTable
end)

Given("table array element (.+) is (.+)", function(index, encoded)
    world.lastTable = world.lastTable or {}
    world.lastTable[tonumber(index)] = JSON.decode(encoded)
    world.lastValue = world.lastTable
end)

Given("nested table \"(.+)\" with field \"(.+)\" = (.+)", function(parentKey, childKey, encoded)
    world.lastTable = world.lastTable or {}
    world.lastTable[parentKey] = world.lastTable[parentKey] or {}
    world.lastTable[parentKey][childKey] = JSON.decode(encoded)
    world.lastValue = world.lastTable
end)

Given("nested table \"(.+)\" array element (.+) is (.+)", function(parentKey, index, encoded)
    world.lastTable = world.lastTable or {}
    world.lastTable[parentKey] = world.lastTable[parentKey] or {}
    world.lastTable[parentKey][tonumber(index)] = JSON.decode(encoded)
    world.lastValue = world.lastTable
end)

When("decoding should fail", function()
    assertions.assertThrows(function()
        JSON.decode(world.lastValue)
    end, "decode should fail")
end)

When("encoding should fail", function()
    assertions.assertThrows(function()
        JSON.encode(world.lastValue)
    end, "encode should fail")
end)

Given("an unsupported JSON value type", function()
    world.lastValue = function() end
end)
