---@meta _
---@brief Façade over ComponentCache (wrappers) and NodeCache (READY node generations).
---@version 1.2.0
---@class Cache
---@field _componentCache ComponentCache # Hardware wrapper identity store.
---@field _nodeCache NodeCache # READY NodeComponent generations.
---@field _components table<string, BaseComponent> # Shared with ComponentCache for compatibility.

local ComponentCache = require("ComponentCache")
local NodeCache = require("NodeCache")

local Cache = {}
Cache.__index = Cache

---Create a cache façade over ComponentCache and NodeCache.
---@return Cache
function Cache.new()
    local self = setmetatable({}, Cache)
    self._componentCache = ComponentCache.new()
    self._components = self._componentCache._components
    self._nodeCache = NodeCache.new(self._componentCache)
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

---Build a READY node generation via NodeCache / fromMapping.
function Cache:buildNode(mapping, globals)
    return self._nodeCache:build(mapping, globals)
end

---Return the current READY node for a machine address.
function Cache:getNode(address)
    return self._nodeCache:get(address)
end

---Retire a non-current node generation when safe.
function Cache:retireGeneration(address, generation)
    return self._nodeCache:retireGeneration(address, generation)
end

return Cache
