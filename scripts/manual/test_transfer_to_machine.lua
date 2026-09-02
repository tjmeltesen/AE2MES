-- test_transfer_to_machine.lua
-- Standalone in-game smoke test for NodeComponent:transferToMachine()
--
-- PURPOSE
--   Exercise transferToMachine() in a real world without cloud jobs, Executor,
--   or any other runtime wiring. Useful for validating physical layout,
--   transposer side mapping, database contents, and machine sensor polling.
--
-- PHYSICAL SETUP (minimum)
--   [ME Interface] <---pull---> [Transposer] <---input---> [GT Input Bus]
--   [Database]  attached to the same OC computer (recipe inputs pre-stored)
--   [GT Machine adapter] on the computer network (for sensor polling)
--   [Return chest] optional, on transposer returnSide for rollback tests
--
-- DATABASE PREP
--   Transfer mode clears the database and pulls recipe inputs from ME automatically.
--   Configure databaseSetup.items/fluids below, or set autoFromNetwork = true.
--
-- INSTALL
--   1. Copy lib/ (and JSON.lua dependency) onto the OC computer.
--   2. Copy this script next to lib/ or adjust package.path below.
--   3. Edit CONFIG addresses and transposer sides.
--
-- USAGE
--   discover  -> safe hardware map only (no item movement)
--   transfer  -> setup database from ME, then run transferToMachine()
--
--   lua test_transfer_to_machine.lua
--
-- TIP: Run discover first, copy addresses/sides into CONFIG, then set mode = "transfer".

package.path = "./lib/?.lua;./src/?.lua;" .. package.path

local component = require("component")
local BaseComponent = require("BaseComponent")
local NodeComponent = require("NodeComponent")
local DatabaseComponent = require("DatabaseComponent")

--------------------------------------------------------------------------------
-- CONFIG — edit these values for your test world
--------------------------------------------------------------------------------

local CONFIG = {
    -- Component addresses (from component.list()).
    -- Leave blank in discover mode to print everything that looks relevant.
    machineAddress = "e8b9066a-e6ff-4dae-b033-275fa283e38e",
    transposerAddress = "7c529aee-8913-42c1-9fc7-696a77b8f4f6",
    interfaceAddress = "b4b53e68-8262-40a4-9aaf-b1c9d9ca55a2",
    databaseAddress = "aebdc662-9cb1-4611-b360-0fcdd33d8aba",

    -- CommonNetworkAPI source for database setup (me_interface or me_controller).
    -- Defaults to interfaceAddress when blank.
    networkAddress = "",

    -- Transposer OC side indices.
    -- Run mode = "discover" first to see which side faces each inventory.
    transposerSides = {
        pull = 5,   -- ME interface side
        input = 0,  -- GT machine input bus side
        returnSide = 2, -- return chest side (used on rollback)
    },

    -- Database slot count (defaults to 9 when nil).
    databaseSize = 9,

    -- Recipe inputs pulled from ME into the database during transfer.
    databaseSetup = {
        clearFirst = true,
        autoFromNetwork = true,
        items = {},
        fluids = {},
    },

    -- "discover" | "transfer"
    mode = "transfer",

    -- Transfer mode: set false when testing item movement without a valid machine recipe.
    requireProcessing = true,

    -- After a successful transfer, wait for the machine recipe to finish.
    waitForProcess = true,
    processTimeout = 30,
}

--------------------------------------------------------------------------------
-- Output helpers
--------------------------------------------------------------------------------

local function printHeader(title)
    print("")
    print("== " .. title .. " ==")
end

local function printLine(label, value)
    print(string.format(" %-18s %s", label .. ":", tostring(value)))
end

local function isRelevantComponentType(ctype)
    return ctype == "transposer"
        or ctype == "me_interface"
        or ctype == "me_controller"
        or ctype == "database"
        or ctype == "gt_machine"
end

local function listRelevantComponents()
    printHeader("Relevant components")
    local count = 0
    for address, ctype in component.list() do
        if isRelevantComponentType(ctype) then
            count = count + 1
            print(string.format("  [%s] %s", ctype, address))
        end
    end
    if count == 0 then
        print("  (none found — check adapters and chunk loading)")
    end
end

local function printDatabaseSlots(database)
    printHeader("Database slots")
    if not database then
        print("  (no database wrapper)")
        return
    end

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
        print("  (all slots empty — stock inputs before transfer mode)")
    end
end

local function resolveNetworkAddress()
    if CONFIG.networkAddress and CONFIG.networkAddress ~= "" then
        return CONFIG.networkAddress
    end
    return CONFIG.interfaceAddress or ""
end

local function printNetworkSnapshot(snapshot)
    printHeader("ME network snapshot")
    if not snapshot then
        print("  (no snapshot)")
        return
    end

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
            table.insert(items, {
                name = item.name,
                damage = item.damage or 0,
                count = item.size,
                label = item.label,
            })
            used = used + 1
        end

        for _, fluid in ipairs(snapshot.fluids or {}) do
            if used >= dbSize then
                break
            end
            table.insert(fluids, {
                name = fluid.name,
                label = fluid.label,
                amount = fluid.amount,
            })
            used = used + 1
        end
    end

    return items, fluids
end

local function printSideInventory(transposer, side, label)
    if not transposer or not side then
        print(string.format("  %s: (missing transposer or side)", label))
        return
    end

    local contents = transposer:getInventoryContents(side)
    if not contents then
        print(string.format("  %s (side %d): unreadable", label, side))
        return
    end

    if #contents == 0 then
        print(string.format("  %s (side %d): empty", label, side))
        return
    end

    print(string.format("  %s (side %d):", label, side))
    for _, stack in ipairs(contents) do
        print(string.format(
            "    slot %d: %s x%d",
            stack.slot or -1,
            stack.label or stack.name or "?",
            stack.size or 0
        ))
    end
end

local function printTransposerMap(transposer, configuredSides)
    printHeader("Transposer inventory map")
    if not transposer then
        print("  (no transposer wrapper)")
        return
    end

    local discovered = transposer:discoverSides()
    for sideName, info in pairs(discovered) do
        local role = "?"
        if configuredSides then
            for name, side in pairs(configuredSides) do
                if side == info.side then
                    role = name
                end
            end
        end
        print(string.format(
            "  side %d (%s) role=%s -> %s [%d slots]",
            info.side,
            sideName,
            role,
            info.container_name or "?",
            info.slots or 0
        ))
    end
end

local function printMachineStatus(machine)
    printHeader("Machine status")
    if not machine then
        print("  (no machine wrapper)")
        return
    end

    local availability = machine:pollAvailability()
    if not availability then
        print("  pollAvailability returned nil")
        return
    end

    printLine("available", availability.available)
    printLine("active", availability.active)
    printLine("workAllowed", availability.workAllowed)
    printLine("progress", string.format(
        "%s / %s",
        tostring(availability.progressCurrent),
        tostring(availability.progressMax)
    ))
    printLine("reason", availability.unavailableReason or "")

    if availability.sensorLines and #availability.sensorLines > 0 then
        print("  sensor lines:")
        for _, line in ipairs(availability.sensorLines) do
            print("   ", line)
        end
    end
end

--------------------------------------------------------------------------------
-- Node construction
--------------------------------------------------------------------------------

local function buildAssignment()
    return {
        schemaVersion = 1,
        jobId = "manual-transfer-test",
        machineAddress = CONFIG.machineAddress,
        registry = {
            machineAddress = CONFIG.machineAddress,
            transposerAddress = CONFIG.transposerAddress,
            interfaceAddress = CONFIG.interfaceAddress,
            databaseAddress = CONFIG.databaseAddress,
            transposerSides = CONFIG.transposerSides,
        },
        sequenceFlow = {
            items = CONFIG.databaseSetup.items or {},
            fluids = CONFIG.databaseSetup.fluids or {},
            steps = {
                { method = "transferToMachine", params = {} },
            },
        },
    }
end

local function buildNode()
    local node = NodeComponent:new()
    local ok, err = node:readAssignment(buildAssignment())
    if not ok then
        return nil, err
    end
    return node
end

local function buildDatabase()
    if CONFIG.databaseAddress == "" then
        return nil, "CONFIG.databaseAddress is required for database setup"
    end

    local db = DatabaseComponent:new(CONFIG.databaseAddress, CONFIG.databaseSize)
    if not db then
        return nil, "Failed to create DatabaseComponent for " .. CONFIG.databaseAddress
    end
    return db
end

local function buildNetworkApi()
    local addr = resolveNetworkAddress()
    if addr == "" then
        return nil, "networkAddress or interfaceAddress required for ME network access"
    end

    local api, err = BaseComponent:new(addr)
    if not api then
        return nil, err or ("Failed to create network API for " .. addr)
    end
    return api
end

local function validateConfig()
    local missing = {}
    if CONFIG.machineAddress == "" then table.insert(missing, "machineAddress") end
    if CONFIG.transposerAddress == "" then table.insert(missing, "transposerAddress") end
    if CONFIG.interfaceAddress == "" then table.insert(missing, "interfaceAddress") end
    if CONFIG.databaseAddress == "" then table.insert(missing, "databaseAddress") end
    if resolveNetworkAddress() == "" then table.insert(missing, "networkAddress or interfaceAddress") end
    if not CONFIG.transposerSides.pull then table.insert(missing, "transposerSides.pull") end
    if not CONFIG.transposerSides.input then table.insert(missing, "transposerSides.input") end

    local setup = CONFIG.databaseSetup
    local hasItems = setup.items and #setup.items > 0
    local hasFluids = setup.fluids and #setup.fluids > 0
    if not hasItems and not hasFluids and not setup.autoFromNetwork then
        return false, "CONFIG.databaseSetup needs items, fluids, or autoFromNetwork = true"
    end

    if #missing > 0 then
        return false, "CONFIG missing: " .. table.concat(missing, ", ")
    end
    return true
end

--------------------------------------------------------------------------------
-- Test modes
--------------------------------------------------------------------------------

local function runDiscover()
    print("NodeComponent transfer test — DISCOVER mode")
    listRelevantComponents()

    if CONFIG.transposerAddress == "" then
        print("")
        print("Set CONFIG.transposerAddress, then re-run to inspect transposer sides.")
        return
    end

    local node, err = buildNode()
    if not node then
        printHeader("FAIL")
        print(err)
        return
    end

    printHeader("Loaded node")
    printLine("jobId", node.jobId)
    printLine("machine", node.machine and node.machine:getAddress() or "nil")
    printLine("transposer", node.transposer and node.transposer:getAddress() or "nil")
    printLine("interface", node.interface and node.interface:getAddress() or "nil")
    printLine("database", node.database and node.database:getAddress() or "nil")

    printTransposerMap(node.transposer, CONFIG.transposerSides)
    printDatabaseSlots(node.database)

    local networkAddr = resolveNetworkAddress()
    if networkAddr ~= "" then
        local network, netErr = buildNetworkApi()
        if network then
            printLine("network", network:getAddress())
            printNetworkSnapshot(network:getSnapshot())
        else
            printHeader("ME network")
            print("  FAIL:", netErr)
        end
    end

    printSideInventory(node.transposer, node:transposerSide("pull"), "pull")
    printSideInventory(node.transposer, node:transposerSide("input"), "input")
    printSideInventory(node.transposer, node:transposerSide("returnSide"), "returnSide")
    printMachineStatus(node.machine)

    print("")
    print("DISCOVER complete. Update CONFIG, then set mode = \"transfer\".")
end

local function setupDatabase()
    printHeader("Database setup")

    local db, err = buildDatabase()
    if not db then
        printHeader("FAIL")
        print(err)
        return false
    end

    local network, netErr = buildNetworkApi()
    if not network then
        printHeader("FAIL")
        print(netErr)
        return false
    end

    printLine("address", db:getAddress())
    printLine("size", db:getSize())
    printLine("network", network:getAddress())

    local snapshot = network:getSnapshot()
    printNetworkSnapshot(snapshot)

    local items, fluids = buildStorePlan(snapshot, db:getSize())
    if #items == 0 and #fluids == 0 then
        printHeader("FAIL")
        print("No items or fluids to store — check ME network contents or CONFIG.databaseSetup")
        return false
    end

    if (#items + #fluids) > db:getSize() then
        printHeader("FAIL")
        print(string.format(
            "Need %d database slots but only %d available",
            #items + #fluids,
            db:getSize()
        ))
        return false
    end

    if CONFIG.databaseSetup.clearFirst then
        printHeader("Clearing database")
        printLine("clearedAny", db:clearAll())
    end

    printHeader("Storing from ME network (CommonNetworkAPI.store)")
    local dbAddr = db:getAddress()
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
                    "  slot %d: FAIL %s (damage %d) not found in ME network",
                    slot,
                    name,
                    damage
                ))
            else
                local count = item.count or networkItem.size
                local filter = { name = name, damage = damage }
                local ok, storeErr = network:store(filter, dbAddr, slot, count)
                if ok then
                    print(string.format(
                        "  slot %d: stored %s x%d (damage %d)",
                        slot,
                        name,
                        count,
                        damage
                    ))
                else
                    failures = failures + 1
                    print(string.format(
                        "  slot %d: FAIL store %s — %s",
                        slot,
                        name,
                        tostring(storeErr)
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
                    "  slot %d: FAIL fluid %s not found in ME network",
                    slot,
                    label
                ))
            else
                local filter = { label = "drop of " .. (networkFluid.label or label) }
                local ok, storeErr = network:store(filter, dbAddr, slot)
                if ok then
                    print(string.format(
                        "  slot %d: stored fluid %s (%d mB in network)",
                        slot,
                        networkFluid.label or label,
                        networkFluid.amount or 0
                    ))
                else
                    failures = failures + 1
                    print(string.format(
                        "  slot %d: FAIL store fluid %s — %s",
                        slot,
                        label,
                        tostring(storeErr)
                    ))
                end
            end
        end
        slot = slot + 1
    end

    db:refreshIndex()
    printDatabaseSlots(db)

    if failures > 0 then
        print("")
        print("FAIL: " .. failures .. " slot(s) could not be stored from ME network.")
        return false
    end

    return true
end

local function runTransfer()
    print("NodeComponent transfer test — TRANSFER mode")

    local valid, configErr = validateConfig()
    if not valid then
        printHeader("FAIL")
        print(configErr)
        return
    end

    if not setupDatabase() then
        return
    end

    local node, err = buildNode()
    if not node then
        printHeader("FAIL")
        print(err)
        return
    end

    printHeader("Pre-transfer state")
    printDatabaseSlots(node.database)
    printSideInventory(node.transposer, node:transposerSide("pull"), "pull")
    printSideInventory(node.transposer, node:transposerSide("input"), "input")
    printMachineStatus(node.machine)

    printHeader("Running transferToMachine()")
    print("  from pull side:", node:transposerSide("pull"))
    print("  to input side:", node:transposerSide("input"))
    print("  requireProcessing:", CONFIG.requireProcessing)

    local started = os.clock()
    local ok = node:transferToMachine(nil, nil, {
        requireProcessing = CONFIG.requireProcessing,
    })
    local elapsed = os.clock() - started

    printHeader("Post-transfer state")
    printLine("result", ok and "PASS" or "FAIL")
    printLine("processingCheck", CONFIG.requireProcessing and "enabled" or "skipped")
    printLine("isDone", node:isDone())
    printLine("elapsedSec", string.format("%.1f", elapsed))
    printSideInventory(node.transposer, node:transposerSide("pull"), "pull")
    printSideInventory(node.transposer, node:transposerSide("input"), "input")
    printSideInventory(node.transposer, node:transposerSide("returnSide"), "returnSide")
    printMachineStatus(node.machine)

    local processOk = true
    if ok and CONFIG.requireProcessing and CONFIG.waitForProcess then
        printHeader("Running waitForProcess()")
        printLine("timeout", CONFIG.processTimeout)

        local waitStarted = os.clock()
        processOk = node:waitForProcess(CONFIG.processTimeout)
        local waitElapsed = os.clock() - waitStarted

        printHeader("Post-process state")
        printLine("result", processOk and "PASS" or "FAIL")
        printLine("isDone", node:isDone())
        printLine("elapsedSec", string.format("%.1f", waitElapsed))
        printMachineStatus(node.machine)
    end

    print("")
    if ok and processOk then
        if CONFIG.requireProcessing and CONFIG.waitForProcess then
            print("PASS: transfer and process wait completed; recipe finished.")
        elseif CONFIG.requireProcessing then
            print("PASS: transferToMachine completed; machine processing, leftovers sent to returnSide.")
        else
            print("PASS: transferToMachine completed (processing check skipped).")
        end
    elseif ok then
        print("FAIL: transfer succeeded but waitForProcess timed out or machine did not finish.")
    else
        print("FAIL: transferToMachine returned false.")
        print("Check database contents, transposer sides, AE2 power, and machine recipe.")
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

if CONFIG.mode == "transfer" then
    runTransfer()
elseif CONFIG.mode == "discover" then
    runDiscover()
else
    print("Unknown CONFIG.mode:", CONFIG.mode)
    print("Use \"discover\" or \"transfer\".")
end
