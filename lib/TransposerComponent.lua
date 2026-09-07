---@meta _
---@brief API wrapper for the OpenComputers transposer component in GTNH.
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/transposer.lua
---@version 1.0.0
---@class TransposerInventoryEntry
---@field slot integer # Position reported by the normalized stack array.
---@field name string|nil
---@field label string|nil
---@field size number
---@field maxSize number|nil
---@field hasNBT boolean
---@class TransposerSideInfo
---@field side integer
---@field side_name string
---@field container_name string
---@field slots integer
---@class TransposerComponent : BaseComponent
---@field address string # OpenComputers component address inherited from BaseComponent.

local BaseComponent = require("BaseComponent")

local TransposerComponent = setmetatable({}, { __index = BaseComponent })
TransposerComponent.__index = TransposerComponent


---Create a transposer wrapper for the specified component address.
---@param address string # The address of the transposer component.
---@return TransposerComponent|nil transposer
---@return string|nil error # Invalid addresses are rejected by BaseComponent.
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

---Transfer items between two inventories adjacent to the transposer.
---@param fromSide integer # Source side.
---@param toSide integer # Destination side.
---@param count? number # Maximum item count; component default when omitted.
---@param fromSlot? integer # Source slot; component default when omitted.
---@param toSlot? integer # Destination slot; component default when omitted.
---@return number|nil moved
---@return string|nil error
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

---Get the number of inventory slots exposed on a side.
---@param side integer # The side of the device.
---@return integer|nil size
---@return string|nil error
function TransposerComponent:getInventorySize(side)
    return self:call("getInventorySize", side)
end

---Get the component's stack collection for an inventory side.
---@param side integer
---@return table|userdata|fun():table|nil stacks # Shape depends on the installed transposer API.
---@return string|nil error
function TransposerComponent:getAllStacks(side)
    return self:call("getAllStacks", side)
end

---Get the inventory name exposed on a side.
---@param side integer # The side of the device.
---@return string|nil name
---@return string|nil error
function TransposerComponent:getInventoryName(side)
    return self:call("getInventoryName", side)
end


---============================================================
--- Custom Transposer Functions
---============================================================

---Normalize `getAllStacks` output to a plain array of item stacks.
---Accepts an array directly, a stack-slot object with `getAll`, or an iterator. Iterator
---and `getAll` exceptions propagate to the caller.
---@param raw any # Table and iterator values are normalized; unsupported values, including userdata, return nil.
---@return table[]|nil stacks # Nil when the value has an unsupported type.
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

---Snapshot all non-empty stacks on a side using `getAllStacks`.
---Yields to the OpenComputers scheduler after each visited array entry when `os.sleep` exists.
---@param side integer
---@return TransposerInventoryEntry[]|nil contents
---@return string|nil error # Component failure or unsupported stack-collection shape.
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

---Request one transfer for each reported non-empty stack.
---Each request uses the stack's reported size without specifying a source slot, yields after
---each entry when possible, and stops on the first failed transfer. A partial moved count is
---returned with that error when nonzero.
---@param fromSide integer
---@param toSide integer
---@return number|nil moved
---@return string|nil error
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



---Discover inventories exposed on the six transposer sides.
---Sides for which either size or name is nil are omitted; component errors are not returned.
---@return table<string, TransposerSideInfo> sides # Map keyed by `Down`, `Up`, `North`, `South`, `West`, or `East`.
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
    for side = 0, 5 do
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
