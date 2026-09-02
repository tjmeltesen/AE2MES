---@meta _
---@brief API Wrapper for Base Component in OpenComputers
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/libs/component.lua
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/abstracts/common-network-api.lua
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/abstracts/base-component.lua
---@version 1.0.0
---@class BaseComponent
---@field component table # Injected OpenComputers component library.
---@field slot integer # Physical slot in the computer; -1 if not applicable.
---@field address string # The address of the component.

local NetworkItems = require("NetworkItems")
local unpack = table.unpack or unpack

local defaultComponent = require("component")

local BaseComponent = {}
BaseComponent.__index = BaseComponent
BaseComponent.VERSION = 2

local function componentApi(opts)
    if type(opts) == "table" and opts.component then
        return opts.component
    end
    return defaultComponent
end

---============================================================
--- Class-level component library helpers
---============================================================

---@return table
function BaseComponent.component()
    return defaultComponent
end

---@param address string
---@param methodName string
---@return string|nil
function BaseComponent.docFor(address, methodName)
    return defaultComponent.doc(address, methodName)
end

---@param address string
---@param methodName string
---@vararg any
---@return any
function BaseComponent.invokeFor(address, methodName, ...)
    return defaultComponent.invoke(address, methodName, ...)
end

---@param filter? string
---@param exact? boolean
---@return table<string, string>
function BaseComponent.list(filter, exact)
    return defaultComponent.list(filter, exact)
end

---@param address string
---@return table<string, boolean>
function BaseComponent.methodsFor(address)
    return defaultComponent.methods(address)
end

---@param address string
---@param componentType? string
---@return any|nil
function BaseComponent.proxyFor(address, componentType)
    if componentType ~= nil then
        return defaultComponent.proxy(address, componentType)
    end
    return defaultComponent.proxy(address)
end

---@param address string
---@return string|nil
function BaseComponent.typeFor(address)
    return defaultComponent.type(address)
end

---@param address string
---@return integer
function BaseComponent.slotFor(address)
    local slot = defaultComponent.slot(address)
    if slot == nil then
        return -1
    end
    return slot
end

---@param address string
---@param componentType? string
---@return string|nil
function BaseComponent.resolve(address, componentType)
    return defaultComponent.get(address, componentType)
end

---@param componentType string
---@return boolean
function BaseComponent.isAvailable(componentType)
    return defaultComponent.isAvailable(componentType)
end

---@param componentType string
---@return any
function BaseComponent.getPrimary(componentType)
    return defaultComponent.getPrimary(componentType)
end

---@param componentType string
---@param address string|nil
function BaseComponent.setPrimary(componentType, address)
    return defaultComponent.setPrimary(componentType, address)
end

---============================================================
--- Instance lifecycle
---============================================================

---@param address string
---@param opts? table|nil # Optional { component = require("component") } for test injection.
---@return BaseComponent|nil
---@return string|nil
function BaseComponent:new(address, opts)
    if type(address) ~= "string" or address == "" then
        return nil, "BaseComponent:new() — invalid address"
    end

    local component = componentApi(opts)
    local self = setmetatable({}, self)
    self.component = component
    self.address = address
    self.slot = component.slot(address) or -1
    self._proxy = nil
    return self
end

function BaseComponent:getAddress()
    return self.address
end

---@return string|nil
function BaseComponent:getType()
    return self.component.type(self.address)
end

---@return integer
function BaseComponent:getSlot()
    return self.slot
end

---@return table|nil
---@return string|nil
function BaseComponent:getProxy()
    if self._proxy then
        return self._proxy
    end

    local ok, proxy = pcall(self.component.proxy, self.address)
    if not ok or not proxy then
        return nil, "BaseComponent:getProxy() — failed for " .. tostring(self.address)
    end

    self._proxy = proxy
    return self._proxy
end

function BaseComponent:invalidate()
    self._proxy = nil
end

---============================================================
--- Instance component invocation
---============================================================

---@param method string
---@vararg any
---@return any
---@return string|nil
function BaseComponent:invoke(method, ...)
    local address = self.address
    local component = self.component
    local args = { ... }
    local nargs = select("#", ...)

    local results = { pcall(function()
        if nargs == 0 then
            return component.invoke(address, method)
        end
        return component.invoke(address, method, unpack(args))
    end) }

    local ok = table.remove(results, 1)
    if not ok then
        self:invalidate()
        return nil, tostring(results[1])
    end

    return unpack(results)
end

---@param method string
---@return string|nil
function BaseComponent:doc(method)
    return self.component.doc(self.address, method)
end

---@return table<string, boolean>
function BaseComponent:methods()
    return self.component.methods(self.address)
end

---Invoke a standard OC component method via component.invoke.
---@param method string
---@vararg any
---@return any
---@return string|nil
function BaseComponent:call(method, ...)
    return self:invoke(method, ...)
end

---Invoke a CommonNetworkAPI method via component.invoke (dot-call semantics).
---@param method string
---@vararg any
---@return any
---@return string|nil
function BaseComponent:callNetwork(method, ...)
    return self:call(method, ...)
end

---Get an iterator object for the list of the items in the network.
---@return fun():MEItemStack|nil
function BaseComponent:allItems()
    return self:callNetwork("allItems")
end

---Get a list of the stored items in the network.
---@param filter? MEItemStackFilter
---@return MEItemStack[]
function BaseComponent:getItemsInNetwork(filter)
    if filter ~= nil then
        return self:callNetwork("getItemsInNetwork", filter)
    end
    return self:callNetwork("getItemsInNetwork")
end

---Get a list of the stored fluids in the network.
---@return MEFluidStack[]
function BaseComponent:getFluidsInNetwork()
    return self:callNetwork("getFluidsInNetwork")
end

---Get a list of the stored essentia in the network.
---@return EssentiaStack[]
function BaseComponent:getEssentiaInNetwork()
    return self:callNetwork("getEssentiaInNetwork")
end

---Store items in the network matching the specified filter in the database.
---@param filter MEItemStackFilter
---@param dbAddress string
---@param startSlot? integer
---@param count? integer
---@return boolean
function BaseComponent:store(filter, dbAddress, startSlot, count)
    return self:callNetwork("store", filter, dbAddress, startSlot, count)
end

---Get a list of all available cpus on the network.
---@return AECpuMetadata[]
function BaseComponent:getCpus()
    return self:callNetwork("getCpus")
end

---Get a list of known item recipes.
---@param filter? MEItemStackFilter
---@return AECraftable[]
function BaseComponent:getCraftables(filter)
    if filter ~= nil then
        return self:callNetwork("getCraftables", filter)
    end
    return self:callNetwork("getCraftables")
end

---Get the average power injection into the network.
---@return number
function BaseComponent:getAvgPowerInjection()
    return self:callNetwork("getAvgPowerInjection")
end

---Get the average power usage of the network.
---@return number
function BaseComponent:getAvgPowerUsage()
    return self:callNetwork("getAvgPowerUsage")
end

---Get the maximum stored power in the network.
---@return number
function BaseComponent:getMaxStoredPower()
    return self:callNetwork("getMaxStoredPower")
end

---Get the stored power in the network.
---@return number
function BaseComponent:getStoredPower()
    return self:callNetwork("getStoredPower")
end

---Get the idle power usage of the network.
---@return number
function BaseComponent:getIdlePowerUsage()
    return self:callNetwork("getIdlePowerUsage")
end

---Normalized snapshot packaged as a lua table (items + fluids in ME network).
---@return table
function BaseComponent:getSnapshot()
    return NetworkItems.formatContents(
        self:getItemsInNetwork(),
        self:getFluidsInNetwork()
    )
end

return BaseComponent
