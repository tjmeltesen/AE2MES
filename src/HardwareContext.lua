---@class HardwareContext

local HardwareContext = {}
HardwareContext.__index = HardwareContext

function HardwareContext.fromRegistry(registry, cache)
    if not registry or not cache then
        return nil, "HardwareContext.fromRegistry() — missing registry or cache"
    end

    local self = setmetatable({}, HardwareContext)
    self._registry = registry
    self._cache = cache
    return self
end

function HardwareContext:machineAddress()
    return self._registry:get("machineAddress")
end

function HardwareContext:resolve(key)
    if type(key) ~= "string" then
        return nil
    end

    local value = self._registry:get(key)
    if type(value) == "string" and value ~= "" then
        return value
    end

    if key:match("^[0-9a-f%-]+$") then
        return key
    end

    return nil
end

function HardwareContext:machine()
    local address = self:resolve("machineAddress")
    return self._cache:getComponent(address, "Machine")
end

function HardwareContext:transposer()
    local address = self:resolve("transposerAddress")
    return self._cache:getComponent(address, "TransposerComponent")
end

function HardwareContext:interface(which)
    local key = which == "stock" and "stockInterfaceAddress" or "storeInterfaceAddress"
    local address = self:resolve(key)
    return self._cache:getComponent(address, "Interface")
end

function HardwareContext:database()
    local address = self:resolve("databaseAddress")
    return self._cache:getComponent(address, "DatabaseComponent")
end

function HardwareContext:redstone()
    local address = self:resolve("redstoneAddress")
    return self._cache:getComponent(address, "RedstoneComponent")
end

function HardwareContext:side(name)
    local sides = self._registry:get("sides")
    if type(sides) ~= "table" then
        return nil
    end
    return sides[name]
end

---Resolve a cloud registry key to the appropriate component wrapper.
---@param target string registry key from sequence step (e.g. "transposerAddress")
function HardwareContext:componentForTarget(target)
    if target == "machineAddress" then
        return self:machine()
    elseif target == "transposerAddress" then
        return self:transposer()
    elseif target == "storeInterfaceAddress" then
        return self:interface("store")
    elseif target == "stockInterfaceAddress" then
        return self:interface("stock")
    elseif target == "databaseAddress" then
        return self:database()
    elseif target == "redstoneAddress" then
        return self:redstone()
    end

    return nil
end

return HardwareContext
