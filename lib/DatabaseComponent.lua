---@meta _
---@brief API wrapper for the OpenComputers Applied Energistics 2 database component.
---@version 1.0.0
---@class ItemStack
---@field name string|nil
---@field label string|nil
---@field fluidDrop any|nil # Present for AE2FC fluid-drop entries.
---@field damage integer|nil
---@field size number|nil
---@class DatabaseIndexEntry
---@field dbSlot integer # One-based database slot.
---@field name string|nil # Unlocalized stack name.
---@field label string|nil # Display label, falling back to the name.
---@field fluid boolean # True when the entry represents an AE2FC fluid drop.
---@class DatabaseComponent : BaseComponent
---@field size integer # Number of slots scanned by this wrapper.
---@field address string # OpenComputers component address inherited from BaseComponent.
---@field index DatabaseIndexEntry[] # Cached non-empty slot metadata.
---@field refreshIndex fun(self: DatabaseComponent): DatabaseIndexEntry[] # Rebuild the cached slot index.


local BaseComponent = require("BaseComponent")

local DatabaseComponent = setmetatable({}, { __index = BaseComponent })
DatabaseComponent.__index = DatabaseComponent

---Create a database wrapper and immediately cache its non-empty slot index.
---Index refresh component errors are treated as empty slots and do not fail construction.
---@param address string # The address of the database component.
---@param size? integer # Number of database slots; defaults to 9.
---@return DatabaseComponent|nil database
---@return string|nil error # Invalid addresses are rejected by BaseComponent.
function DatabaseComponent:new(address, size)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    if size == nil then
        size = 9
    end
    self.size = size
    self:refreshIndex()

    return self
end

---Scan one-based database slots and cache metadata for every non-empty entry.
---Per-slot component errors are indistinguishable from empty slots and are skipped.
---@return DatabaseIndexEntry[] index # The new cache, also assigned to `self.index`.
function DatabaseComponent:refreshIndex()
    local index = {}
    for slot = 1, self.size do
        local stack = self:get(slot)
        if stack then
            index[#index + 1] = {
                dbSlot = slot,
                name = stack.name,
                label = stack.label or stack.name,
                fluid = stack.fluidDrop ~= nil,
            }
        end
    end
    self.index = index
    return index
end


---Get the item-stack descriptor stored in a database slot.
---@param slot integer # The slot to get an item from.
---@return ItemStack|nil stack # Nil for an empty slot or component failure.
---@return string|nil error
function DatabaseComponent:get(slot)
    return self:call("get", slot)
end

---Find the slot containing an item stack with the specified hash.
---@param hash string # The hash of the item you are looking for.
---@return integer|nil slot # Negative when not found; nil on component failure.
---@return string|nil error
function DatabaseComponent:indexOf(hash)
    return self:call("indexOf", hash)
end

---Write an item descriptor into a database slot.
---This mutates the component but does not refresh the wrapper's cached index.
---@param slot integer # The slot to write an item to
---@param id string  # The unlocalized name of the item eg: minecraft:stone
---@param damage integer # The damage/metadata of the item
---@param nbt? string # The nbt of the item, formatted using JSON
---@return boolean|nil written
---@return string|nil error
function DatabaseComponent:set(slot, id, damage, nbt)
    return self:call("set", slot, id, damage, nbt)
end

---Clear a database slot without refreshing the cached index.
---@param slot integer
---@return boolean|nil hadValue # True when the slot contained a value before clearing.
---@return string|nil error
function DatabaseComponent:clear(slot)
    return self:call("clear", slot)
end

---Copy this database's contents to another database component.
---The underlying component rejects databases containing empty slots; failures are returned.
---@param dbAddress string # The address of the database to copy to.
---@return integer|nil overwritten # Number of destination slots overwritten.
---@return string|nil error
function DatabaseComponent:clone(dbAddress)
    return self:call("clone", dbAddress)
end

---Compute the hash of the item stack in a database slot.
---@param slot integer # The slot to compute the hash for
---@return string|nil hash
---@return string|nil error
function DatabaseComponent:computeHash(slot)
    return self:call("computeHash", slot)
end

---Copy an entry to another slot, optionally in another database.
---This does not refresh the wrapper's cached index.
---@param fromSlot integer # The slot to copy from
---@param toSlot integer # The slot to copy to
---@param dbAddress? string # (Optional) The address of the database to copy to.
---@return boolean|nil overwritten
---@return string|nil error
function DatabaseComponent:copy(fromSlot, toSlot, dbAddress) 
    return self:call("copy", fromSlot, toSlot, dbAddress)
end

---Get the configured slot count used by wrapper scans.
---@return integer # The size of the database. Default 9 if not set.
function DatabaseComponent:getSize()
    return self.size
end

---Clear every one-based slot from 1 through `getSize`.
---Continues after component errors, does not refresh `self.index`, and returns whether any
---clear call reported that a value had existed.
---@return boolean clearedAny
function DatabaseComponent:clearAll()
    local clearedAny = false
    for i = 1, self:getSize() do
        if self:clear(i) then
            clearedAny = true
        end
    end
    return clearedAny
end

return DatabaseComponent
