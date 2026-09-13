---@meta _
---@brief Thin façade over ComponentCache for hardware wrapper identity.
---@version 1.1.0
---@class Cache
---@field _componentCache ComponentCache # Hardware wrapper identity store.

local ComponentCache = require("ComponentCache")

local Cache = {}
Cache.__index = Cache

---Create a cache façade over a ComponentCache.
---@return Cache
function Cache.new()
    local self = setmetatable({}, Cache)
    self._componentCache = ComponentCache.new()
    self._components = self._componentCache._components
    return self
end

---Delegate wrapper identity to ComponentCache.
function Cache:getComponent(address, className, ...)
    return self._componentCache:getComponent(address, className, ...)
end

---Delegate invalidation to ComponentCache.
function Cache:invalidate(address)
    return self._componentCache:invalidate(address)
end

return Cache
