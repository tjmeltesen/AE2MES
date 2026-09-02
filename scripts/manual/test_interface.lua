package.path = "./lib/?.lua;./src/?.lua;" .. package.path

local component = require("component")
local BaseComponent = require("BaseComponent")
local TransposerComponent = require("TransposerComponent")
local DatabaseComponent = require("DatabaseComponent")
local Interface = require("Interface")
local Machine = require("Machine")

local CONFIG = {
    databaseAddress = "aebdc662-9cb1-4611-b360-0fcdd33d8aba",
    transposerAddress = "7c529aee-8913-42c1-9fc7-696a77b8f4f6",
    machineAddress = "e8b9066a-e6ff-4dae-b033-275fa283e38e",
    interfaceAddress = "b4b53e68-8262-40a4-9aaf-b1c9d9ca55a2",
    networkAddress = "", -- defaults to interfaceAddress

    databaseSetup = {
        autoFromNetwork = true,
        items = {
            -- { name = "minecraft:iron_ingot", count = 64, damage = 0 },
        },
        fluids = {
            -- { label = "Water" },
        },
    },
}

local function printHeader(title)
    print("")
    print("== " .. title .. " ==")
end

local function resolveNetworkAddress()
    if CONFIG.networkAddress ~= "" then
        return CONFIG.networkAddress
    end
    return CONFIG.interfaceAddress
end

local function printDatabaseSlots(database)
    printHeader("Database slots")
    local any = false
    for slot = 1, database:getSize() do
        local stack = database:get(slot)
        if stack then
            any = true
            local kind = stack.fluidDrop and "fluid" or "item"
            print(string.format(
                "  slot %d: %s (%s) x%s",
                slot,
                stack.label or stack.name or "?",
                kind,
                tostring(stack.size or stack.amount or "?")
            ))
        end
    end
    if not any then
        print("  (all slots empty)")
    end
end

local function printNetworkSnapshot(network)
    printHeader("ME network snapshot")
    local snapshot = network:getSnapshot()
    if #snapshot.items == 0 then
        print("  (no items in network)")
    else
        for index, item in ipairs(snapshot.items) do
            print(string.format(
                "  item [%d] %s x%d damage=%d (%s)",
                index,
                item.name or "?",
                item.size or 0,
                item.damage or 0,
                item.label or "?"
            ))
        end
    end
    if #snapshot.fluids == 0 then
        print("  (no fluids in network)")
    else
        for index, fluid in ipairs(snapshot.fluids) do
            print(string.format(
                "  fluid [%d] %s %d mB (%s)",
                index,
                fluid.name or "?",
                fluid.amount or 0,
                fluid.label or "?"
            ))
        end
    end
    return snapshot
end

local function findNetworkItem(snapshot, name, damage)
    damage = damage or 0
    for _, item in ipairs(snapshot.items or {}) do
        if item.name == name and (item.damage or 0) == damage then
            return item
        end
    end
    return nil
end

local function findNetworkFluid(snapshot, labelOrName)
    for _, fluid in ipairs(snapshot.fluids or {}) do
        if fluid.label == labelOrName or fluid.name == labelOrName then
            return fluid
        end
    end
    return nil
end

local function buildStorePlan(snapshot, dbSize)
    local setup = CONFIG.databaseSetup
    local items = setup.items or {}
    local fluids = setup.fluids or {}

    if setup.autoFromNetwork and #items == 0 and #fluids == 0 then
        items = {}
        fluids = {}
        local used = 0

        for _, item in ipairs(snapshot.items or {}) do
            if used >= dbSize then
                break
            end
            items[#items + 1] = {
                name = item.name,
                damage = item.damage or 0,
                count = item.size,
                label = item.label,
            }
            used = used + 1
        end

        for _, fluid in ipairs(snapshot.fluids or {}) do
            if used >= dbSize then
                break
            end
            fluids[#fluids + 1] = {
                name = fluid.name,
                label = fluid.label,
                amount = fluid.amount,
            }
            used = used + 1
        end
    end

    return items, fluids
end

local function setupDatabase(database, network)
    printHeader("Database setup")
    print("  database:", database:getAddress())
    print("  network: ", network:getAddress())

    local snapshot = printNetworkSnapshot(network)
    local items, fluids = buildStorePlan(snapshot, database:getSize())

    if #items == 0 and #fluids == 0 then
        print("FAIL: nothing to store — check ME network or CONFIG.databaseSetup")
        return false
    end

    if (#items + #fluids) > database:getSize() then
        print(string.format(
            "FAIL: need %d slots but database only has %d",
            #items + #fluids,
            database:getSize()
        ))
        return false
    end

    printHeader("Clearing database")
    print("  clearedAny:", database:clearAll())

    printHeader("Storing from ME network")
    local dbAddr = database:getAddress()
    local slot = 1
    local failures = 0

    for _, item in ipairs(items) do
        local name = item.name
        if not name then
            failures = failures + 1
            print(string.format("  slot %d: FAIL entry missing name", slot))
        else
            local damage = item.damage or 0
            local networkItem = findNetworkItem(snapshot, name, damage)
            if not networkItem then
                failures = failures + 1
                print(string.format(
                    "  slot %d: FAIL %s (damage %d) not in ME network",
                    slot, name, damage
                ))
            else
                local count = item.count or networkItem.size
                local ok, storeErr = network:store(
                    { name = name, damage = damage },
                    dbAddr,
                    slot,
                    count
                )
                if ok then
                    print(string.format(
                        "  slot %d: stored %s x%d (damage %d)",
                        slot, name, count, damage
                    ))
                else
                    failures = failures + 1
                    print(string.format(
                        "  slot %d: FAIL store %s — %s",
                        slot, name, tostring(storeErr)
                    ))
                end
            end
        end
        slot = slot + 1
    end

    for _, fluid in ipairs(fluids) do
        local label = fluid.label or fluid.name
        if not label then
            failures = failures + 1
            print(string.format("  slot %d: FAIL fluid entry missing label", slot))
        else
            local networkFluid = findNetworkFluid(snapshot, label)
            if not networkFluid then
                failures = failures + 1
                print(string.format(
                    "  slot %d: FAIL fluid %s not in ME network",
                    slot, label
                ))
            else
                local ok, storeErr = network:store(
                    { label = "drop of " .. (networkFluid.label or label) },
                    dbAddr,
                    slot
                )
                if ok then
                    print(string.format(
                        "  slot %d: stored fluid %s",
                        slot, networkFluid.label or label
                    ))
                else
                    failures = failures + 1
                    print(string.format(
                        "  slot %d: FAIL store fluid %s — %s",
                        slot, label, tostring(storeErr)
                    ))
                end
            end
        end
        slot = slot + 1
    end

    database:refreshIndex()
    printDatabaseSlots(database)

    if failures > 0 then
        print("FAIL:", failures, "slot(s) could not be stored")
        return false
    end

    print("PASS: database setup complete")
    return true
end

local function printMachineAvailability(machine)
    printHeader("machine:pollAvailability()")
    if not machine then
        print("  (no machine wrapper)")
        return
    end

    local availability = machine:pollAvailability()
    if not availability then
        print("  pollAvailability returned nil")
        return
    end

    print("  available:      ", availability.available)
    print("  active:         ", availability.active)
    print("  hasWork:        ", availability.hasWork)
    print("  workAllowed:    ", availability.workAllowed)
    print("  problems:       ", availability.problems)
    print("  progress:       ", tostring(availability.progressCurrent), "/",
        tostring(availability.progressMax))
    print("  tier:           ", tostring(availability.tier))
    print("  reason:         ", availability.unavailableReason or "")

    if availability.sensorLines and #availability.sensorLines > 0 then
        print("  sensor lines:")
        for _, line in ipairs(availability.sensorLines) do
            print("   ", line)
        end
    else
        print("  sensor lines:    (none)")
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local database = DatabaseComponent:new(CONFIG.databaseAddress)

local networkAddr = resolveNetworkAddress()
local network, networkErr = BaseComponent:new(networkAddr)
if not network then
    print("network init failed:", networkErr)
    return
end

if not setupDatabase(database, network) then
    return
end

local interface = Interface:new(CONFIG.interfaceAddress, database)
local transposer = TransposerComponent:new(CONFIG.transposerAddress)

local machineAddress = CONFIG.machineAddress
if machineAddress == "" then
    for address in component.list("gt_machine") do
        machineAddress = address
        break
    end
end

local machine, machineErr
if machineAddress ~= "" then
    machine, machineErr = Machine:new(machineAddress)
    if not machine then
        print("machine init failed:", machineErr)
    end
else
    print("No gt_machine found — skipping machine poll")
end

printHeader("Interface clear/set/clear")
print("clearing")
interface:clearAllConfigurations()
print("done clearing")

print("setting")
interface:setAllConfigurations()
print("done setting")

print("clearing again")
interface:clearAllConfigurations()
print("done clearing")

printMachineAvailability(machine)

print("")
print("done")
