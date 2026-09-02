---@meta _
---@brief API Wrapper for database component in OpenComputers Applied Energistics 2
---@version 1.0.0
---@class DatabaseComponent: BaseComponent
---@field size integer
---@field address string


local BaseComponent = require("BaseComponent")

local DatabaseComponent = setmetatable({}, { __index = BaseComponent })
DatabaseComponent.__index = DatabaseComponent

---Creates a new DatabaseComponent instance with the specified size (number of slots,type).
---@param address string # The address of the database component.
---@param size integer # The size of the database. If nil, it will be inferred as base size of 9.
---@return DatabaseComponent | nil, string | nil # A new instance of DatabaseComponent. Will return nil and an error message if the address is invalid.
function DatabaseComponent:new(address, size)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    if size == nil then
        size = 9
    end
    self.size = size

    return self
end


---Get the representation of the item stack stored in the specified slot.
---@param slot integer # The slot to get an item from.
---@return ItemStack|nil # The item stack's descriptor if a value was found.
function DatabaseComponent:get(slot)
    return self:call("get", slot)
end

---Gets the index of an item stack with the specified hash. Returns a negative value if no such stack was found.
---@param hash string # The hash of the item you are looking for.
---@return number # slot of the item or -1 if not found
function DatabaseComponent:indexOf(hash)
    return self:call("indexOf", hash)
end

---Set an item into the specified database slot. NBT tag is expected in JSON format
---@param slot integer # The slot to write an item to
---@param id string  # The unlocalized name of the item eg: minecraft:stone
---@param damage integer # The damage/metadata of the item
---@param nbt? string # The nbt of the item, formatted using JSON
---@return boolean # True if the item was successfully written.
---@return nil|string # An error telling you what went wrong.
function DatabaseComponent:set(slot, id, damage, nbt)
    return self:call("set", slot, id, damage, nbt)
end

---Clears the specified slot. Returns true if there was something in the slot before.
---@param slot integer
---@return boolean # Returns true if there was something in the slot before.
function DatabaseComponent:clear(slot)
    return self:call("clear", slot)
end

---Copies the data stored in this database to another database with the specified address.
---Will error if the database has empty slots.
---@param dbAddress string # The address of the database to copy to.
---@return integer # how many slots were overwritten.
function DatabaseComponent:clone(dbAddress)
    return self:call("clone", dbAddress)
end

---Computes a hash value for the item stack in the specified slot.
---@param slot integer # The slot to compute the hash for
---@return string
function DatabaseComponent:computeHash(slot)
    return self:call("computeHash", slot)
end

---Copies an entry to another slot, optionally to another database. Returns true if something was overwritten.
---@param fromSlot integer # The slot to copy from
---@param toSlot integer # The slot to copy to
---@param dbAddress? string # (Optional) The address of the database to copy to.
---@return boolean # True if something was overwritten.
function DatabaseComponent:copy(fromSlot, toSlot, dbAddress) 
    return self:call("copy", fromSlot, toSlot, dbAddress)
end

--- Gets the size of the database.
---@return integer # The size of the database. Default 9 if not set.
function DatabaseComponent:getSize()
    return self.size
end

--- Clears all slots in the database. Returns true if any slot was cleared. (0 index or 1 index not sure yet.)
---@return boolean # True if any slot was cleared.
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
