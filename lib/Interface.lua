---@meta _
---@brief API Wrapper for ME Interface component in OpenComputers for GTNH
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/me-interface.lua
---@version 1.0.0
---@class Interface : BaseComponent
---@field address string

local BaseComponent = require("BaseComponent")


local Interface = setmetatable({}, { __index = BaseComponent })
Interface.__index = Interface

---Creates a new Interface instance with the specified address.
---@param address string # The component address of the ME Interface.
---@return Interface | nil, string | nil # A new Interface instance, or nil and an error message if the address is invalid.
function Interface:new(address)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    self.MAX_SLOTS = 9
    self.MAX_FLUID_SLOTS = 6
    return self
end

---============================================================
--- Base Interface API Functions
---============================================================

---Sets the item being stocked in a specific slot of the interface.
---@param slot integer # The slot index to configure. (0-8)
---@param dbAddress string # The address of a database that contains the item to stock.
---@param dbSlot integer # The index of the item within the database.
---@param count? integer # The amount of items to stock in the interface. (defaults to 1)
---@return boolean # Whether the configuration was applied successfully.
function Interface:setConfiguration(slot, dbAddress, dbSlot, count)
    if slot < 0 or slot >= self.MAX_SLOTS then
        return nil, "Interface:setConfiguration() — invalid slot index: " .. slot
    end
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

---============================================================
--- Custom Interface Functions
---============================================================

function Interface:clearAllConfigurations()
    for i = 0, self.MAX_SLOTS - 1 do
        self:clearConfiguration(i)
    end
    for i = 0, self.MAX_FLUID_SLOTS - 1 do
        self:clearFluidConfiguration(i)
    end
end

--- Sets all configurations for the interface from what is stored in the database
---@param databaseObj DatabaseComponent # The database object to get the configurations from
---@return boolean True if the configurations were set successfully, false otherwise
function Interface:setAllConfigurations(databaseObj)
    local dbAddress = databaseObj.address
    local dbSlots = databaseObj.size

    local itemSlot = 0
    local fluidSlot = 0

    for dbSlot = 1, dbSlots do
        local itemStack = databaseObj:get(dbSlot)

        if itemStack then
            if itemStack.fluidDrop ~= nil then
                -- Fluid configuration
                if fluidSlot < self.MAX_FLUID_SLOTS then
                    self:setFluidConfiguration(
                        fluidSlot,
                        dbAddress,
                        dbSlot
                    )

                    fluidSlot = fluidSlot + 1
                end
            else
                -- Item configuration
                if itemSlot < self.MAX_SLOTS then
                    self:setConfiguration(
                        itemSlot,
                        dbAddress,
                        dbSlot
                    )

                    itemSlot = itemSlot + 1
                end
            end
        end

        -- Stop once both configuration areas are full.
        if itemSlot >= self.MAX_SLOTS
            and fluidSlot >= self.MAX_FLUID_SLOTS then
            break
        end
    end

    return true
end

--- Checks if the interface is empty (checks network for items and fluids)
---@return boolean True if the interface is empty, false otherwise

function Interface:isEmpty() 
    local snapshot = self:getSnapshot()
    if #snapshot.items ~= 0 or #snapshot.fluids ~= 0 then
        return false
    end
    return true
end

return Interface
