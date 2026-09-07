---@meta _
---@brief Reuses OpenComputers hardware wrappers by class name and component address.
---@version 1.0.0
---@class Cache
---@field _components table<string, BaseComponent> # Wrapper instances keyed by `className:address`.
---@field _lastBuffer table | nil # Most recently accepted ME buffer snapshot.
---@field _lastMachineScan table | nil # Most recently completed machine availability scan.

local Cache = {}
Cache.__index = Cache

local WRAPPER_CLASSES = {
    Machine = "Machine",
    TransposerComponent = "TransposerComponent",
    Interface = "Interface",
    DatabaseComponent = "DatabaseComponent",
    RedstoneComponent = "RedstoneComponent",
    MeControllerComponent = "MeControllerComponent",
}

---Create an empty component and sensor-data cache.
---@return Cache # New cache with no wrappers or snapshots.
function Cache.new()
    local self = setmetatable({}, Cache)
    self._components = {}
    self._lastBuffer = nil
    self._lastMachineScan = nil
    return self
end

---Resolve or construct a cached component wrapper.
---Constructor arguments are used when creating a wrapper. A cached interface is
---rebound when a database argument is supplied. A cached database reconciles a
---changed size and refreshes its index while preserving wrapper identity.
---Rebinding or resizing mutates the cached wrapper; failed database refresh restores
---its previous size and index. Requiring a wrapper module may raise a Lua error.
---@param address string # Non-empty OpenComputers component address.
---@param className string # Supported wrapper module name.
---@vararg any # Constructor arguments, also used to refresh cached interface/database state.
---@return BaseComponent | nil component # Cached or newly constructed wrapper; nil for invalid addresses or failures.
---@return string | nil error # Unknown-class, refresh, binding, or wrapper-construction error.
function Cache:getComponent(address, className, ...)
    if type(address) ~= "string" or address == "" then
        return nil
    end

    if type(className) ~= "string" or not WRAPPER_CLASSES[className] then
        return nil, "Cache:getComponent() — unknown class: " .. tostring(className)
    end

    local key = className .. ":" .. address
    if self._components[key] then
        local cached = self._components[key]
        local constructorArg = select(1, ...)
        if className == "Interface" and constructorArg ~= nil then
            local ok, bindResult, bindErr = pcall(cached.bindDatabase, cached, constructorArg)
            if not ok or not bindResult then
                return nil, "Cache:getComponent() — failed to refresh interface database binding: "
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
                return nil, "Cache:getComponent() — failed to refresh resized database: "
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
---A non-string value does nothing; an empty string matches and removes every wrapper.
---@param address string # Address text to search for in cache keys.
---@return nil
function Cache:invalidate(address)
    if type(address) ~= "string" then
        return
    end

    for key in pairs(self._components) do
        if key:find(address, 1, true) then
            self._components[key] = nil
        end
    end
end

---Store the latest ME buffer snapshot by reference.
---@param snapshot table | nil # Snapshot to cache, or nil to clear it.
---@return nil
function Cache:setLastBuffer(snapshot)
    self._lastBuffer = snapshot
end

---Return the last cached ME buffer snapshot.
---@return table | nil # Same snapshot table previously supplied, if any.
function Cache:getLastBuffer()
    return self._lastBuffer
end

---Store the latest machine availability scan by reference.
---@param scan table | nil # Availability array to cache, or nil to clear it.
---@return nil
function Cache:setLastMachineScan(scan)
    self._lastMachineScan = scan
end

---Return the last cached machine availability scan.
---@return table | nil # Same scan table previously supplied, if any.
function Cache:getLastMachineScan()
    return self._lastMachineScan
end

return Cache
