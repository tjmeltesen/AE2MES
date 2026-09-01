local BaseComponent = require("BaseComponent")

local TransposerComponent = setmetatable({}, BaseComponent)
TransposerComponent.__index = TransposerComponent

function TransposerComponent:new(address)
    return BaseComponent.new(self, address)
end

--- Normalize getAllStacks() output to a plain array of item stacks.
-- OC may return an array directly, a stack-slot object with getAll(), or an iterator.
local function normalizeStacks(raw)
    if raw == nil then
        return nil
    end

    if type(raw) == "function" then
        local stacks = {}
        for stack in raw do
            if type(stack) == "table" then
                table.insert(stacks, stack)
            end
        end
        return stacks
    end

    if type(raw) == "table" then
        if type(raw.getAll) == "function" then
            return raw.getAll()
        end
        return raw
    end

    return nil
end

--- Transfer items between two adjacent inventories via transposer.
-- @param fromSide number
-- @param toSide number
-- @param count number|nil
-- @param fromSlot number|nil
-- @param toSlot number|nil
-- @return number|nil moved, string|nil error
function TransposerComponent:transferItem(fromSide, toSide, count, fromSlot, toSlot)
    return self:call(
        "transferItem",
        fromSide,
        toSide,
        count,
        fromSlot,
        toSlot
    )
end

function TransposerComponent:getInventorySize(side)
    return self:call("getInventorySize", side)
end

--- Get stack metadata for every occupied slot on a side.
-- @param side number
-- @return table|nil stacks
function TransposerComponent:getAllStacks(side)
    return self:call("getAllStacks", side)
end

function TransposerComponent:getStackInSlot(side, slot)
    return self:call("getStackInSlot", side, slot)
end

function TransposerComponent:getSlotStackSize(side, slot)
    return self:call("getSlotStackSize", side, slot)
end

--- Snapshot all non-empty stacks on a side using getAllStacks.
-- @param side number
-- @return table[]|nil contents array of {slot, name, label, size, maxSize, hasNBT}
function TransposerComponent:getInventoryContents(side)
    local raw, err = self:getAllStacks(side)
    if not raw then
        return nil, err
    end

    local stacks = normalizeStacks(raw)
    if not stacks then
        return nil, "TransposerComponent:getInventoryContents() — invalid getAllStacks result"
    end

    local contents = {}

    for slot, stack in ipairs(stacks) do
        if stack and stack.size and stack.size > 0 then
            table.insert(contents, {
                slot = slot,
                name = stack.name,
                label = stack.label,
                size = stack.size,
                maxSize = stack.maxSize,
                hasNBT = stack.hasNBT or false,
            })
        end

        if os.sleep then
            os.sleep(0)
        end
    end

    return contents
end

--- Move every stack from one side to another (chest ↔ bus pattern).
-- Iterates getAllStacks results and transfers each stack.size in full.
-- @param fromSide number
-- @param toSide number
-- @return number|nil total moved, string|nil error
function TransposerComponent:drainInventory(fromSide, toSide)
    local raw, err = self:getAllStacks(fromSide)
    if not raw then
        return nil, err
    end

    local stacks = normalizeStacks(raw)
    if not stacks then
        return nil, "TransposerComponent:drainInventory() — invalid getAllStacks result"
    end

    local total = 0

    for _, stack in ipairs(stacks) do
        if stack and stack.size and stack.size > 0 then
            local moved, moveErr = self:transferItem(fromSide, toSide, stack.size)
            if moved == nil then
                return total > 0 and total or nil, moveErr
            end
            total = total + moved
        end

        if os.sleep then
            os.sleep(0)
        end
    end

    return total
end

function TransposerComponent:getTankCount(side)
    return self:call("getTankCount", side)
end

function TransposerComponent:getFluidInTank(side, tank)
    return self:call("getFluidInTank", side, tank)
end

function TransposerComponent:getTankLevel(side, tank)
    return self:call("getTankLevel", side, tank)
end

function TransposerComponent:getTankCapacity(side, tank)
    return self:call("getTankCapacity", side, tank)
end

function TransposerComponent:getTankContents(side)
    local count, err = self:getTankCount(side)

    if not count then
        return nil, err
    end

    local contents = {}

    for tank = 1, count do
        local fluid = self:getFluidInTank(side, tank)
        local level = self:getTankLevel(side, tank)
        local capacity = self:getTankCapacity(side, tank)

        table.insert(contents, {
            tank = tank,
            label = fluid and fluid.label or nil,
            amount = level or 0,
            capacity = capacity or 0,
            has = fluid ~= nil,
        })

        if os.sleep then
            os.sleep(0)
        end
    end

    return contents
end

return TransposerComponent
