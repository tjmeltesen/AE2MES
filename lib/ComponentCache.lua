---@meta _
---@brief Reuses OpenComputers hardware wrappers by class name and component address.
---@version 1.0.0
---@class ComponentCache
---@field _components table<string, BaseComponent> # Wrapper instances keyed by `className:address`.

local ComponentCache = {}
ComponentCache.__index = ComponentCache

local WRAPPER_CLASSES = {
    Machine = "Machine",
    TransposerComponent = "TransposerComponent",
    Interface = "Interface",
    DatabaseComponent = "DatabaseComponent",
    RedstoneComponent = "RedstoneComponent",
    MeControllerComponent = "MeControllerComponent",
}

---Create an empty hardware-wrapper cache.
---@return ComponentCache
function ComponentCache.new()
    local self = setmetatable({}, ComponentCache)
    self._components = {}
    return self
end

---Resolve or construct a cached component wrapper.
---Constructor arguments are used when creating a wrapper. A cached interface is
---rebound when a database argument is supplied. A cached database reconciles a
---changed size and refreshes its index while preserving wrapper identity.
---@param address string # Non-empty OpenComputers component address.
---@param className string # Supported wrapper module name.
---@vararg any # Constructor arguments, also used to refresh cached interface/database state.
---@return BaseComponent | nil component
---@return string | nil error
function ComponentCache:getComponent(address, className, ...)
    if type(address) ~= "string" or address == "" then
        return nil
    end

    if type(className) ~= "string" or not WRAPPER_CLASSES[className] then
        return nil, "ComponentCache:getComponent() — unknown class: " .. tostring(className)
    end

    local key = className .. ":" .. address
    if self._components[key] then
        local cached = self._components[key]
        local constructorArg = select(1, ...)
        if className == "Interface" and constructorArg ~= nil then
            local ok, bindResult, bindErr = pcall(cached.bindDatabase, cached, constructorArg)
            if not ok or not bindResult then
                return nil, "ComponentCache:getComponent() — failed to refresh interface database binding: "
                    .. tostring(ok and bindErr or bindResult)
            end
        elseif className == "DatabaseComponent"
            and type(constructorArg) == "number"
            and type(cached.getSize) == "function"
            and cached:getSize() ~= constructorArg then
            local oldSize = cached.size
            local oldIndex = cached.index
            cached.size = constructorArg
            local ok, refreshResult = pcall(cached.refreshIndex, cached)
            if not ok or type(refreshResult) ~= "table" then
                cached.size = oldSize
                cached.index = oldIndex
                return nil, "ComponentCache:getComponent() — failed to refresh resized database: "
                    .. tostring(refreshResult)
            end
        end
        return cached
    end

    local Wrapper = require(className)
    local instance, err = Wrapper:new(address, ...)
    if not instance then
        return nil, err
    end

    self._components[key] = instance
    return instance
end

---Remove every cached wrapper whose composite cache key contains an address substring.
---@param address string # Address text to search for in cache keys.
---@return nil
function ComponentCache:invalidate(address)
    if type(address) ~= "string" then
        return
    end

    for key in pairs(self._components) do
        if key:find(address, 1, true) then
            self._components[key] = nil
        end
    end
end

return ComponentCache
