---@meta _
---@brief API Wrapper for ME Interface component in OpenComputers for GTNH
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/me-interface.lua
---@version 1.0.0
---@class Interface : BaseComponent
---@field address string # OpenComputers component address inherited from BaseComponent.
---@field MAX_SLOTS integer # Number of item configuration slots (9).
---@field MAX_FLUID_SLOTS integer # Number of fluid configuration slots (6).
---@field _configPlan table|nil # Cached database-to-interface configuration plan.
---@field _trackedConfigs table[]|nil # Slots most recently configured by this wrapper.

local BaseComponent = require("BaseComponent")


local Interface = setmetatable({}, { __index = BaseComponent })
Interface.__index = Interface

---Create an Interface wrapper for an ME interface component.
---When databaseObj is provided, pre-builds the interface config plan from its cached index.
---@param address string # The component address of the ME Interface.
---@param databaseObj? DatabaseComponent # Optional database to read slot refs from at construction.
---@return Interface|nil interface
---@return string|nil error # Invalid addresses are rejected by BaseComponent.
function Interface:new(address, databaseObj)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    self.MAX_SLOTS = 9
    self.MAX_FLUID_SLOTS = 6
    self._configPlan = nil
    self._trackedConfigs = nil
    if databaseObj then
        self:bindDatabase(databaseObj)
    end
    return self
end

---============================================================
--- Base Interface API Functions
---============================================================

---Set the item stocked in an interface configuration slot.
---The wrapper accepts zero-based slots 0 through 8 and forwards component failures as `nil, error`.
---@param slot integer # Zero-based configuration slot (0-8).
---@param dbAddress string # The address of a database that contains the item to stock.
---@param dbSlot integer # The index of the item within the database.
---@param count? integer # The amount of items to stock in the interface. (defaults to 1)
---@return boolean|nil applied
---@return string|nil error
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

---Clear the item stocked in an interface configuration slot.
---@param slot integer # Zero-based configuration slot.
---@return boolean|nil cleared
---@return string|nil error
function Interface:clearConfiguration(slot)
    return self:callNetwork(
        "setInterfaceConfiguration",
        slot
    )
end

---Set the fluid stocked on an interface side.
---@param side integer # The side to configure.
---@param dbAddress string # The address of a database that contains the fluid to stock (stored as an ae2fc drop).
---@param dbSlot integer # The index of the fluid entry within the database.
---@return boolean|nil applied
---@return string|nil error
function Interface:setFluidConfiguration(side, dbAddress, dbSlot)
    return self:callNetwork(
        "setFluidInterfaceConfiguration",
        side,
        dbAddress,
        dbSlot
    )
end

---Clear the fluid stocked on an interface side.
---@param side integer # The side to clear of fluids.
---@return boolean|nil cleared
---@return string|nil error
function Interface:clearFluidConfiguration(side)
    return self:callNetwork(
        "setFluidInterfaceConfiguration",
        side
    )
end

---============================================================
--- Custom Interface Functions
---============================================================

---Return whether a component configuration query produced a non-false value.
---@param value any
---@return boolean
local function isConfigured(value)
    return value ~= nil and value ~= false
end

---Build interface slot references from a database index, assigning items before fluids.
---At most nine item entries and six fluid entries are included; additional entries are ignored.
---@param databaseObj DatabaseComponent|{ address: string, index: DatabaseIndexEntry[]|nil, refreshIndex: fun(self: any): DatabaseIndexEntry[] }
---@return { dbAddress: string, items: table[], fluids: table[], tracked: table[] } plan
local function buildConfigPlan(databaseObj)
    local plan = {
        dbAddress = databaseObj.address,
        items = {},
        fluids = {},
        tracked = {},
    }

    local itemSlot = 1
    local fluidSlot = 1
    local index = databaseObj.index or databaseObj:refreshIndex()

    for _, entry in ipairs(index) do
        if entry.fluid then
            if fluidSlot <= 6 then
                plan.fluids[#plan.fluids + 1] = {
                    side = fluidSlot,
                    dbSlot = entry.dbSlot,
                }
                plan.tracked[#plan.tracked + 1] = {
                    slot = fluidSlot,
                    fluid = true,
                    dbSlot = entry.dbSlot,
                }
                fluidSlot = fluidSlot + 1
            end
        elseif itemSlot <= 9 then
            plan.items[#plan.items + 1] = {
                slot = itemSlot,
                dbSlot = entry.dbSlot,
                count = 64,
            }
            plan.tracked[#plan.tracked + 1] = {
                slot = itemSlot,
                fluid = false,
                dbSlot = entry.dbSlot,
            }
            itemSlot = itemSlot + 1
        end

        if itemSlot > 9 and fluidSlot > 6 then
            break
        end
    end

    return plan
end

---Attach a database and cache its slot-to-interface mapping for `setAllConfigurations`.
---Refreshes the database index only when `databaseObj.index` is false or nil.
---@param databaseObj DatabaseComponent
---@return { dbAddress: string, items: table[], fluids: table[], tracked: table[] } plan
function Interface:bindDatabase(databaseObj)
    self._configPlan = buildConfigPlan(databaseObj)
    self._trackedConfigs = self._configPlan.tracked
    return self._configPlan
end

---Clear interface item and fluid configurations.
---Uses tracked slots when available; otherwise scans all zero-based slots and, by default,
---queries each slot before clearing it. Component errors are ignored and no status is returned.
---@param opts? { tracked?: { slot: integer, fluid: boolean }[], skipEmpty?: boolean }
---@return nil
function Interface:clearAllConfigurations(opts)
    opts = type(opts) == "table" and opts or {}
    local skipEmpty = opts.skipEmpty ~= false
    local tracked = opts.tracked or self._trackedConfigs

    if tracked and #tracked > 0 then
        for _, entry in ipairs(tracked) do
            if entry.fluid then
                self:clearFluidConfiguration(entry.slot)
            else
                self:clearConfiguration(entry.slot)
            end
        end
        self._trackedConfigs = nil
        return
    end

    for i = 0, self.MAX_SLOTS - 1 do
        if not skipEmpty or isConfigured(self:callNetwork("getInterfaceConfiguration", i)) then
            self:clearConfiguration(i)
        end
    end
    for i = 0, self.MAX_FLUID_SLOTS - 1 do
        if not skipEmpty or isConfigured(self:callNetwork("getFluidInterfaceConfiguration", i)) then
            self:clearFluidConfiguration(i)
        end
    end
end

---Apply all item and fluid configurations from a bound database plan.
---Returns false only when no plan exists. Individual component-call failures are ignored,
---and tracked slots are updated after all configuration attempts.
---@param databaseObj? DatabaseComponent # Optional; refreshes the plan when address differs.
---@return boolean attempted # True after attempting a complete plan, false when no plan is bound.
function Interface:setAllConfigurations(databaseObj)
    if databaseObj then
        if not self._configPlan or self._configPlan.dbAddress ~= databaseObj.address then
            self:bindDatabase(databaseObj)
        end
    elseif not self._configPlan then
        return false
    end

    local plan = self._configPlan
    local dbAddress = plan.dbAddress

    for _, entry in ipairs(plan.items) do
        self:setConfiguration(entry.slot, dbAddress, entry.dbSlot, entry.count)
    end
    for _, entry in ipairs(plan.fluids) do
        self:setFluidConfiguration(entry.side, dbAddress, entry.dbSlot)
    end

    self._trackedConfigs = plan.tracked
    return true
end

---Check whether the interface's normalized network snapshot contains no items or fluids.
---@return boolean empty
function Interface:isEmpty() 
    local snapshot = self:getSnapshot()
    if #snapshot.items ~= 0 or #snapshot.fluids ~= 0 then
        return false
    end
    return true
end

return Interface
