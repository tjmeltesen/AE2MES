---@meta _

local BaseComponent = require("BaseComponent")
local NetworkItems = require("NetworkItems")

--- Wrapper for an ME Interface component, providing access to the ME network's
--- item/fluid contents as well as the interface's own stocking and pattern
--- configuration (via the underlying `me_interface` component API).
---@class Interface: BaseComponent
local Interface = setmetatable({}, {__index = BaseComponent})
Interface.__index = Interface

---Creates a new Interface wrapper for the component at the given address.
---@param address string # The component address of the ME Interface.
---@return Interface | nil, string | nil # A new Interface instance, or nil and an error message if the address is invalid.
function Interface:new(address)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    return self
end

---Gets the list of items currently stored in the ME network.
---@param filter? table # Optional item filter to narrow down the results.
---@return table # A list of items (and their counts) present in the network.
function Interface:getItemsInNetwork(filter)
    if filter ~= nil then
        return self:callNetwork("getItemsInNetwork", filter)
    end
    return self:callNetwork("getItemsInNetwork")
end

---Gets the list of fluids currently stored in the ME network.
---@return table # A list of fluids (and their amounts) present in the network.
function Interface:getFluidsInNetwork()
    return self:callNetwork("getFluidsInNetwork")
end

---Gets a combined, formatted view of both the items and fluids in the network.
---@return table # The combined/formatted contents of the network, as produced by NetworkItems.formatContents.
function Interface:getContents()
    return NetworkItems.formatContents(
        self:getItemsInNetwork(),
        self:getFluidsInNetwork()
    )
end

---Sets the item being stocked in a specific slot of the interface.
---@param slot integer # The slot index to configure.
---@param dbAddress string # The address of a database that contains the item to stock.
---@param dbSlot integer # The index of the item within the database.
---@param count? integer # The amount of items to stock in the interface. (defaults to 1)
---@return boolean # Whether the configuration was applied successfully.
function Interface:setConfiguration(slot, dbAddress, dbSlot, count)
    return self:callNetwork(
        "setInterfaceConfiguration",
        slot,
        dbAddress,
        dbSlot,
        count
    )
end

---Clears the item being stocked in the specified slot.
---@param slot integer # The slot index to clear.
---@return boolean # Whether the slot was cleared successfully.
function Interface:clearConfiguration(slot)
    return self:callNetwork(
        "setInterfaceConfiguration",
        slot
    )
end

---Sets the fluid being stocked on a given side of the interface.
---@param side integer # The side to configure.
---@param dbAddress string # The address of a database that contains the fluid to stock (stored as an ae2fc drop).
---@param dbSlot integer # The index of the fluid entry within the database.
---@return boolean # Whether the configuration was applied successfully.
function Interface:setFluidConfiguration(side, dbAddress, dbSlot)
    return self:callNetwork(
        "setFluidInterfaceConfiguration",
        side,
        dbAddress,
        dbSlot
    )
end

---Clears the fluid being stocked on a given side of the interface.
---@param side integer # The side to clear of fluids.
---@return boolean # Whether the side was cleared successfully.
function Interface:clearFluidConfiguration(side)
    return self:callNetwork(
        "setFluidInterfaceConfiguration",
        side
    )
end

---Stores a single matching item/fluid from the network into a database slot.
---@param filter table # A filter describing the item/fluid to store.
---@param databaseAddress string # The address of the database to store the result in.
---@param databaseSlot integer # The index within the database to store the result at.
---@return boolean # Whether the item/fluid was stored successfully.
function Interface:store(filter, databaseAddress, databaseSlot)
    return self:callNetwork(
        "store",
        filter,
        databaseAddress,
        databaseSlot,
        1
    )
end

return Interface