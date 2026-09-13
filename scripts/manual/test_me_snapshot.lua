-- test_me_snapshot.lua
-- In-game smoke test for ME controller buffer snapshot + machine discovery.
-- Copy to OC computer and run: test_me_snapshot

package.path = "./src/?.lua;./lib/?.lua;" .. package.path

local ComponentCache = require("ComponentCache")
local component = require("component")

local ME_CONTROLLER_ADDR = "61df706b-463f-453f-ba71-c2c43a79e12a"
local MACHINE_FILTER = "gt_machine"

local function printHeader(title)
    print("")
    print("== " .. title .. " ==")
end

local function printComponentType(address)
    printHeader("Component")
    local found = false
    for addr, ctype in component.list() do
        if addr == address then
            print(" address:", addr)
            print(" type:   ", ctype)
            found = true
            break
        end
    end
    if not found then
        print(" FAIL: address not found in component.list()")
    end
end

local function printRawNetwork(address)
    printHeader("Raw proxy (dot-call only)")
    local proxy = component.proxy(address)
    if not proxy then
        print(" FAIL: component.proxy returned nil")
        return
    end

    local ok, items = pcall(function()
        return proxy.getItemsInNetwork()
    end)
    print(" getItemsInNetwork ok:", ok, "type:", type(items), "len:", items and #items or "n/a")
    if ok and items and items[1] then
        print("  [1]", items[1].name, items[1].size, items[1].label)
    end

    ok, items = pcall(function()
        return proxy.allItems()
    end)
    print(" allItems ok:", ok, "type:", type(items), "len:", items and #items or "n/a")

    ok, items = pcall(function()
        return proxy.getFluidsInNetwork()
    end)
    print(" getFluidsInNetwork ok:", ok, "type:", type(items), "len:", items and #items or "n/a")
end

local function printWrapper(controller)
    printHeader("Wrapper methods")
    local raw = controller:getItemsInNetwork()
    print(" getItemsInNetwork type:", type(raw), "len:", raw and #raw or "n/a")
    local NetworkItems = require("NetworkItems")
    local formatted = NetworkItems.formatItems(raw)
    print(" formatItems count:", #formatted)

    local snap, err = controller:getSnapshot()
    if not snap then
        print(" getSnapshot FAIL:", err)
        return false
    end

    print(" snapshot items:", #snap.items, "fluids:", #snap.fluids)
    return snap
end

local function printSnapshot(snap)
    printHeader("MeControllerComponent:getSnapshot()")

    if #snap.items == 0 then
        print(" (no items in snapshot)")
    else
        for index, item in ipairs(snap.items) do
            print(string.format(
                "  [%d] %s x%d (%s)",
                index,
                item.name or "?",
                item.size or 0,
                item.label or "?"
            ))
        end
    end

    if #snap.fluids == 0 then
        print(" (no fluids in snapshot)")
    else
        for index, fluid in ipairs(snap.fluids) do
            print(string.format(
                "  [%d] %s %d mB (%s)",
                index,
                fluid.name or "?",
                fluid.amount or 0,
                fluid.label or "?"
            ))
        end
    end

    return true
end

local function printMachines()
    printHeader("Machines (" .. MACHINE_FILTER .. ")")
    local count = 0
    for address, ctype in component.list(MACHINE_FILTER) do
        count = count + 1
        print(" ", address, ctype)
    end
    if count == 0 then
        print(" (none found)")
    end
end

-- main
print("ME snapshot test")
printComponentType(ME_CONTROLLER_ADDR)
printRawNetwork(ME_CONTROLLER_ADDR)

local components = ComponentCache.new()
local controller = components:getComponent(ME_CONTROLLER_ADDR, "MeControllerComponent")
if not controller then
    print("")
    print("FAIL: could not create MeControllerComponent wrapper")
    return
end

if printSnapshot(printWrapper(controller)) then
    print("")
    print("PASS: buffer snapshot OK")
else
    print("")
    print("FAIL: buffer snapshot")
end

printMachines()
