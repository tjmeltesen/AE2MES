---@meta _
---@brief Base OpenComputers component wrapper with inherited AE2 CommonNetworkAPI helpers.
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/libs/component.lua
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/abstracts/common-network-api.lua
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/abstracts/base-component.lua
---@version 1.0.0
---@alias MEItemStackFilter table<string, any>
---@alias MEItemStack table<string, any>
---@alias MEFluidStack table<string, any>
---@alias EssentiaStack table<string, any>
---@alias AECpuMetadata table<string, any>
---@alias AECraftable table<string, any>
---@class ComponentAPI
---@field doc fun(address: string, methodName: string): string|nil
---@field get fun(address: string, componentType?: string): string|nil
---@field getPrimary fun(componentType: string): table
---@field invoke fun(...): ...any
---@field isAvailable fun(componentType: string): boolean
---@field list fun(filter?: string, exact?: boolean): fun(): string|nil, string|nil
---@field methods fun(address: string): table<string, boolean>
---@field proxy fun(address: string, componentType?: string): table|nil
---@field setPrimary fun(componentType: string, address?: string): any
---@field slot fun(address: string): integer|nil
---@field type fun(address: string): string|nil
---@class BaseComponent
---@field component ComponentAPI # Injected OpenComputers component library.
---@field slot integer # Physical slot in the computer; -1 if not applicable.
---@field address string # The address of the component.
---@field _proxy table|nil # Lazily cached component proxy.
---@field VERSION integer # Wrapper API version inherited from the class table.

local NetworkItems = require("NetworkItems")
local unpack = table.unpack or unpack

---@type ComponentAPI
local defaultComponent = require("component")

local BaseComponent = {}
BaseComponent.__index = BaseComponent
BaseComponent.VERSION = 2

---Select an injected component API or the process default.
---@param opts? { component?: ComponentAPI }
---@return ComponentAPI component
local function componentApi(opts)
    if type(opts) == "table" and opts.component then
        return opts.component
    end
    return defaultComponent
end

---============================================================
--- Class-level component library helpers
---============================================================

---Get the default OpenComputers component library used by class-level helpers.
---@return ComponentAPI component
function BaseComponent.component()
    return defaultComponent
end

---Get the component-provided documentation for a method.
---Errors from the default component library propagate.
---@param address string
---@param methodName string
---@return string|nil documentation
function BaseComponent.docFor(address, methodName)
    return defaultComponent.doc(address, methodName)
end

---Invoke a method on an arbitrary component through the default library.
---All component results and exceptions pass through unchanged.
---@param address string
---@param methodName string
---@vararg any
---@return ...any results # All values returned by the component method.
function BaseComponent.invokeFor(address, methodName, ...)
    return defaultComponent.invoke(address, methodName, ...)
end

---List components visible to the computer.
---Errors from the default component library propagate.
---@param filter? string # Optional component-type filter.
---@param exact? boolean
---@return fun(): string|nil, string|nil iterator # Yields component address and type.
function BaseComponent.list(filter, exact)
    return defaultComponent.list(filter, exact)
end

---Get the callable-method map for an arbitrary component.
---@param address string
---@return table<string, boolean>
function BaseComponent.methodsFor(address)
    return defaultComponent.methods(address)
end

---Create a proxy for an arbitrary component.
---Errors from the default component library propagate.
---@param address string
---@param componentType? string
---@return table|nil proxy
function BaseComponent.proxyFor(address, componentType)
    if componentType ~= nil then
        return defaultComponent.proxy(address, componentType)
    end
    return defaultComponent.proxy(address)
end

---Get the registered type of an arbitrary component.
---@param address string
---@return string|nil componentType
function BaseComponent.typeFor(address)
    return defaultComponent.type(address)
end

---Get an arbitrary component's physical computer slot.
---@param address string
---@return integer slot # `-1` when the component library returns nil.
function BaseComponent.slotFor(address)
    local slot = defaultComponent.slot(address)
    if slot == nil then
        return -1
    end
    return slot
end

---Resolve a partial component address, optionally constrained by type.
---Ambiguous-address errors from the component library propagate.
---@param address string
---@param componentType? string
---@return string|nil resolvedAddress
function BaseComponent.resolve(address, componentType)
    return defaultComponent.get(address, componentType)
end

---Check whether at least one component of a type is available.
---@param componentType string
---@return boolean available
function BaseComponent.isAvailable(componentType)
    return defaultComponent.isAvailable(componentType)
end

---Get the primary proxy for a component type.
---Missing-primary errors from the component library propagate.
---@param componentType string
---@return table proxy
function BaseComponent.getPrimary(componentType)
    return defaultComponent.getPrimary(componentType)
end

---Set or clear the primary component address for a type.
---Mutates the default component library's primary selection; errors propagate.
---@param componentType string
---@param address string|nil
---@return any result # Component-library-defined result.
function BaseComponent.setPrimary(componentType, address)
    return defaultComponent.setPrimary(componentType, address)
end

---============================================================
--- Instance lifecycle
---============================================================

---Create a component wrapper without eagerly creating a proxy.
---Invalid addresses return an error. Slot lookup failures from the selected component API propagate.
---@param address string
---@param opts? table|nil # Optional { component = require("component") } for test injection.
---@return BaseComponent|nil component
---@return string|nil error
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

---Get this wrapper's component address.
---@return string address
function BaseComponent:getAddress()
    return self.address
end

---Get this wrapper's currently registered component type.
---Component-library errors propagate.
---@return string|nil componentType
function BaseComponent:getType()
    return self.component.type(self.address)
end

---Get the physical computer slot cached at construction.
---@return integer slot
function BaseComponent:getSlot()
    return self.slot
end

---Get and cache a proxy for this wrapper's component.
---Proxy exceptions are caught, the original detail is discarded, and a wrapper error is returned.
---@return table|nil proxy
---@return string|nil error
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

---Discard the cached proxy so the next `getProxy` call resolves it again.
---@return nil
function BaseComponent:invalidate()
    self._proxy = nil
end

---============================================================
--- Instance component invocation
---============================================================

---Invoke a component method and convert invocation exceptions to `nil, error`.
---Successful component return values are passed through unchanged. A failed call also invalidates
---the cached proxy, although invocation itself uses the component library directly.
---@param method string
---@vararg any
---@return ...any results # Component results, or `nil, error` when invocation raises.
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

---Get component-provided documentation for one method.
---Component-library errors propagate.
---@param method string
---@return string|nil documentation
function BaseComponent:doc(method)
    return self.component.doc(self.address, method)
end

---Get the callable-method map for this component.
---Component-library errors propagate.
---@return table<string, boolean> methods
function BaseComponent:methods()
    return self.component.methods(self.address)
end

---Invoke a standard OC component method via component.invoke.
---Invocation exceptions are returned as `nil, error`.
---@param method string
---@vararg any
---@return ...any results # Component results, or `nil, error` when invocation raises.
function BaseComponent:call(method, ...)
    return self:invoke(method, ...)
end

---Invoke a CommonNetworkAPI method via component.invoke (dot-call semantics).
---Invocation exceptions are returned as `nil, error`.
---@param method string
---@vararg any
---@return ...any results # Component results, or `nil, error` when invocation raises.
function BaseComponent:callNetwork(method, ...)
    return self:call(method, ...)
end

---Get an iterator object for the list of the items in the network.
---@return fun():MEItemStack|nil iterator
---@return string|nil error
function BaseComponent:allItems()
    return self:callNetwork("allItems")
end

---Get a list of the stored items in the network.
---@param filter? MEItemStackFilter
---@return MEItemStack[]|nil items
---@return string|nil error
function BaseComponent:getItemsInNetwork(filter)
    if filter ~= nil then
        return self:callNetwork("getItemsInNetwork", filter)
    end
    return self:callNetwork("getItemsInNetwork")
end

---Get a list of the stored fluids in the network.
---@return MEFluidStack[]|nil fluids
---@return string|nil error
function BaseComponent:getFluidsInNetwork()
    return self:callNetwork("getFluidsInNetwork")
end

---Get a list of the stored essentia in the network.
---@return EssentiaStack[]|nil essentia
---@return string|nil error
function BaseComponent:getEssentiaInNetwork()
    return self:callNetwork("getEssentiaInNetwork")
end

---Store items in the network matching the specified filter in the database.
---@param filter MEItemStackFilter
---@param dbAddress string
---@param startSlot? integer
---@param count? integer
---@return boolean|nil stored
---@return string|nil error
function BaseComponent:store(filter, dbAddress, startSlot, count)
    return self:callNetwork("store", filter, dbAddress, startSlot, count)
end

---Get a list of all available cpus on the network.
---@return AECpuMetadata[]|nil cpus
---@return string|nil error
function BaseComponent:getCpus()
    return self:callNetwork("getCpus")
end

---Get a list of known item recipes.
---@param filter? MEItemStackFilter
---@return AECraftable[]|nil craftables
---@return string|nil error
function BaseComponent:getCraftables(filter)
    if filter ~= nil then
        return self:callNetwork("getCraftables", filter)
    end
    return self:callNetwork("getCraftables")
end

---Get the average power injection into the network.
---@return number|nil averageInjection
---@return string|nil error
function BaseComponent:getAvgPowerInjection()
    return self:callNetwork("getAvgPowerInjection")
end

---Get the average power usage of the network.
---@return number|nil averageUsage
---@return string|nil error
function BaseComponent:getAvgPowerUsage()
    return self:callNetwork("getAvgPowerUsage")
end

---Get the maximum stored power in the network.
---@return number|nil maximumPower
---@return string|nil error
function BaseComponent:getMaxStoredPower()
    return self:callNetwork("getMaxStoredPower")
end

---Get the stored power in the network.
---@return number|nil storedPower
---@return string|nil error
function BaseComponent:getStoredPower()
    return self:callNetwork("getStoredPower")
end

---Get the idle power usage of the network.
---@return number|nil idleUsage
---@return string|nil error
function BaseComponent:getIdlePowerUsage()
    return self:callNetwork("getIdlePowerUsage")
end

---Format current ME item and fluid results into a plain snapshot table.
---Errors returned by either component call are discarded and that category formats as empty.
---@return { items: table[], fluids: table[] } snapshot
function BaseComponent:getSnapshot()
    return NetworkItems.formatContents(
        self:getItemsInNetwork(),
        self:getFluidsInNetwork()
    )
end

return BaseComponent
