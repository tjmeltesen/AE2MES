-- test_transposer.lua
-- Quick smoke test for TransposerComponent, DatabaseComponent, and Machine wrappers.
-- Copy lib/ to the OC computer, then run: tests/test_transposer
--
-- Restart the computer after copying lib/ so Lua reloads BaseComponent.

package.path = "./lib/?.lua;./src/?.lua;" .. package.path

local RELOAD_MODULES = {
    "BaseComponent",
    "TransposerComponent",
    "DatabaseComponent",
    "Machine",
    "ComponentLibrary",
}

for _, name in ipairs(RELOAD_MODULES) do
    package.loaded[name] = nil
end

local component = require("component")
local BaseComponent = require("BaseComponent")
local TransposerComponent = require("TransposerComponent")
local DatabaseComponent = require("DatabaseComponent")
local Machine = require("Machine")

local CONFIG = {
    databaseAddress = "aebdc662-9cb1-4611-b360-0fcdd33d8aba",
    transposerAddress = "7c529aee-8913-42c1-9fc7-696a77b8f4f6",
    machineAddress = "", -- auto-filled from component.list("gt_machine") when empty
}

local function printResult(label, ...)
    print(label, ...)
end

print("== BaseComponent version ==")
if BaseComponent.VERSION ~= 2 then
    print("FAIL: expected BaseComponent.VERSION == 2")
    print("Copy the latest lib/BaseComponent.lua and restart the computer.")
    return
end
print("BaseComponent.VERSION:", BaseComponent.VERSION)

print("== raw component.invoke sanity ==")
printResult("db type:", component.type(CONFIG.databaseAddress))
printResult("tr type:", component.type(CONFIG.transposerAddress))
printResult("raw db get:", component.invoke(CONFIG.databaseAddress, "get", 1))
printResult("raw tr getAllStacks(1):", component.invoke(CONFIG.transposerAddress, "getAllStacks", 1))

local database, dbErr = DatabaseComponent:new(CONFIG.databaseAddress)
if not database then
    print("database init failed:", dbErr)
    return
end

local transposer, trErr = TransposerComponent:new(CONFIG.transposerAddress)
if not transposer then
    print("transposer init failed:", trErr)
    return
end

print("== discoverSides ==")
local sides = transposer:discoverSides()
local sideCount = 0
for sideName, info in pairs(sides) do
    sideCount = sideCount + 1
    print(sideName, info.side, info.side_name, info.container_name, info.slots)
end
if sideCount == 0 then
    print("(no inventories found on transposer sides)")
end

print("== database:get(1) ==")
local stack, getErr = database:get(1)
printResult("result:", stack, getErr)

print("== transposer address ==")
print(transposer:getAddress())

print("== transposer:getInventoryContents per discovered side ==")
if sideCount == 0 then
    for side = 0, 5 do
        local contents, contentsErr = transposer:getInventoryContents(side)
        printResult("side", side, ":", contents, contentsErr)
    end
else
    for _, info in pairs(sides) do
        local contents, contentsErr = transposer:getInventoryContents(info.side)
        printResult("side", info.side, "(" .. info.side_name .. "):", contents, contentsErr)
    end
end

local machineAddress = CONFIG.machineAddress
if machineAddress == "" then
    for address in component.list("gt_machine") do
        machineAddress = address
        break
    end
end

if machineAddress ~= "" then
    local machine, machineErr = Machine:new(machineAddress)
    if not machine then
        print("machine init failed:", machineErr)
        return
    end

    print("== machine:setWorkAllowed(true) ==")
    printResult("machine:", machineAddress)
    local allowed, allowErr = machine:setWorkAllowed(true)
    printResult("result:", allowed, allowErr)
else
    print("== machine (skipped) ==")
    print("No gt_machine component found on this computer.")
end

print("== done ==")
