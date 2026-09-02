---@meta _
---@brief API Wrapper for Transposer component in OpenComputers for GTNH
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/transposer.lua
---@version 1.0.0
---@class TransposerComponent : BaseComponent
---@field address string

local BaseComponent = require("BaseComponent")

local TransposerComponent = setmetatable({}, { __index = BaseComponent })
TransposerComponent.__index = TransposerComponent


---Creates a new TransposerComponent instance with the specified address.
---@param address string # The address of the transposer component.
---@return TransposerComponent | nil, string | nil # A new instance of TransposerComponent. Will return nil and an error message if the address is invalid.
function TransposerComponent:new(address)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    return self
end


---============================================================
--- Base Transposer API Functions 
---============================================================

--- Transfer items between two adjacent inventories via transposer.
---@param fromSide number
---@param toSide number
---@param count number|nil
---@param fromSlot number|nil
---@param toSlot number|nil
---@return number|nil moved, string|nil error
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

---Get the number of slots in the inventory on a specific side.
---@param side integer # The side of the device.
---@return integer # The number of slots in the inventory.
function TransposerComponent:getInventorySize(side)
    return self:call("getInventorySize", side)
end

--- Get stack metadata for every occupied slot on a side.
--- @param side number
--- @return table|nil stacks
function TransposerComponent:getAllStacks(side)
    return self:call("getAllStacks", side)
end

---Get the name of the inventory on a specific side.
---@param side integer # The side of the device.
---@return string # The name of the inventory.
function TransposerComponent:getInventoryName(side)
    return self:call("getInventoryName", side)
end


---============================================================
--- Custom Transposer Functions
---============================================================

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

--- Snapshot all non-empty stacks on a side using getAllStacks.
--- @param side number
--- @return table[]|nil contents array of {slot, name, label, size, maxSize, hasNBT}
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



---Discovers what inventories are on the sides of the transposer for easy mapping, returns a table containing: side,
---side_name, container_name, and slots. Only returns sides that have an inventory.
---@return table
function TransposerComponent:discoverSides()
    local sides = {}
    local side_map = {
        [0] = "Down",
        [1] = "Up",
        [2] = "North",
        [3] = "South",
        [4] = "West",
        [5] = "East"
    }
    for side = 1, 6 do
        local slots = self:getInventorySize(side)
        local container_name = self:getInventoryName(side)
        if slots and container_name then
            local side_name = tostring(side_map[side])
            sides[side_map[side]] = {
                side = side,
                side_name = side_name,
                container_name = container_name,
                slots = slots
            }
        end
    end
    return sides
end


return TransposerComponent
