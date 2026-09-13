---@meta _
---@brief Stores READY NodeComponent generations keyed by machine address.
---@version 1.0.0
---@class NodeCache
---@field _componentCache ComponentCache|Cache # Sticky Global / wrapper identity store.
---@field _entries table<string, { current: integer, byGeneration: table<integer, NodeComponent> }>
---@field _nextGeneration integer

local NodeComponent = require("NodeComponent")

local NodeCache = {}
NodeCache.__index = NodeCache

---Create a node-generation cache that builds through ComponentCache.
---@param componentCache ComponentCache|Cache # Hardware wrapper identity store used by fromMapping.
---@return NodeCache
function NodeCache.new(componentCache)
    local self = setmetatable({}, NodeCache)
    self._componentCache = componentCache
    self._entries = {}
    self._nextGeneration = 1
    return self
end

---Build a new READY node generation from an approved machine mapping.
---The new generation becomes current; prior generations remain until retired.
---@param mapping table # Cloud machine mapping including machineAddress and mappingRevision.
---@param globals? table # Sticky Globals (database/redstone addresses and redstoneSides).
---@return NodeComponent|nil node
---@return string|nil error
function NodeCache:build(mapping, globals)
    if type(mapping) ~= "table" or type(mapping.machineAddress) ~= "string"
        or mapping.machineAddress == "" then
        return nil, "NodeCache:build() — machine mapping requires machineAddress"
    end
    if mapping.status ~= "READY" then
        return nil, "NodeCache:build() — machine mapping is not READY"
    end

    local node, err = NodeComponent:fromMapping(mapping, globals, self._componentCache)
    if not node then
        return nil, err
    end

    local address = mapping.machineAddress
    local generation = self._nextGeneration
    self._nextGeneration = generation + 1
    node.cacheGeneration = generation

    local entry = self._entries[address]
    if not entry then
        entry = { current = generation, byGeneration = {} }
        self._entries[address] = entry
    else
        entry.current = generation
    end
    entry.byGeneration[generation] = node
    return node
end

---Return the current READY node for a machine address, if any.
---@param address string
---@return NodeComponent|nil
function NodeCache:get(address)
    if type(address) ~= "string" then
        return nil
    end
    local entry = self._entries[address]
    if not entry then
        return nil
    end
    return entry.byGeneration[entry.current]
end

---Return whether a specific generation is still retained for an address.
---@param address string
---@param generation integer
---@return boolean
function NodeCache:hasGeneration(address, generation)
    if type(address) ~= "string" or type(generation) ~= "number" then
        return false
    end
    local entry = self._entries[address]
    return entry ~= nil and entry.byGeneration[generation] ~= nil
end

---Drop a non-current generation when active work no longer holds it.
---Retiring the current generation is a no-op so get() stays stable until rebuild.
---@param address string
---@param generation integer
---@return nil
function NodeCache:retireGeneration(address, generation)
    if type(address) ~= "string" or type(generation) ~= "number" then
        return
    end
    local entry = self._entries[address]
    if not entry then
        return
    end
    if entry.current == generation then
        return
    end
    entry.byGeneration[generation] = nil
end

return NodeCache
