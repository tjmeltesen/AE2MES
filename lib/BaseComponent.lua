---@meta _
---@brief API Wrapper for Base Component in OpenComputers
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/libs/component.lua
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/abstracts/common-network-api.lua
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/abstracts/base-component.lua
---@version 1.0.0
---@class BaseComponent
---@field slot integer # Physical slot in the computer; -1 if not applicable.
---@field address string # The address of the component.

local ComponentLibrary = require("ComponentLibrary")
local NetworkItems = require("NetworkItems")
local unpack = table.unpack or unpack

local BaseComponent = {}
BaseComponent.__index = BaseComponent

function BaseComponent:new(address)
    if type(address) ~= "string" or address == "" then
        return nil, "BaseComponent:new() — invalid address"
    end

    local self = setmetatable({}, self)
    self.address = address
    self.slot = ComponentLibrary.slot(address)
    self.proxy = nil
    return self
end

function BaseComponent:getAddress()
    return self.address
end

function BaseComponent:getType()
    return ComponentLibrary.type(self.address)
end

function BaseComponent:getProxy()
    if self.proxy then
        return self.proxy
    end

    local proxy, err = ComponentLibrary.proxy(self.address)
    if not proxy then
        return nil, err
    end

    self.proxy = proxy
    return self.proxy
end

function BaseComponent:invalidate()
    self.proxy = nil
end

---Invoke a standard OC component method (colon-call: proxy passed as first arg).
function BaseComponent:call(method, ...)
    local proxy, err = self:getProxy()
    if not proxy then
        return nil, err
    end

    local fn = proxy[method]
    if type(fn) ~= "function" then
        return nil, "BaseComponent:call() — method unavailable: " .. tostring(method)
    end

    local args = { ... }
    local ok, result = pcall(function()
        return fn(proxy, unpack(args))
    end)

    if not ok then
        self:invalidate()
        return nil, tostring(result)
    end

    return result
end

---Invoke a CommonNetworkAPI method (dot-call only — never pass proxy as self).
function BaseComponent:callNetwork(method, ...)
    local args = { ... }
    local nargs = select("#", ...)

    local ok, result = pcall(function()
        if nargs == 0 then
            return ComponentLibrary.invoke(self.address, method)
        end
        return ComponentLibrary.invoke(self.address, method, unpack(args))
    end)

    if ok then
        return result
    end

    local proxy, err = self:getProxy()
    if not proxy then
        return nil, err
    end

    local fn = proxy[method]
    if type(fn) ~= "function" then
        return nil, "BaseComponent:callNetwork() — method unavailable: " .. tostring(method)
    end

    ok, result = pcall(function()
        if nargs == 0 then
            return fn()
        end
        return fn(unpack(args))
    end)

    if not ok then
        self:invalidate()
        return nil, tostring(result)
    end

    return result
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
