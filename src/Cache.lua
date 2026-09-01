---@class Cache

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

function Cache.new()
    local self = setmetatable({}, Cache)
    self._components = {}
    self._lastBuffer = nil
    self._lastMachineScan = nil
    return self
end

function Cache:getComponent(address, className)
    if type(address) ~= "string" or address == "" then
        return nil
    end

    if type(className) ~= "string" or not WRAPPER_CLASSES[className] then
        return nil, "Cache:getComponent() — unknown class: " .. tostring(className)
    end

    local key = className .. ":" .. address
    if self._components[key] then
        return self._components[key]
    end

    local Wrapper = require(className)
    local instance, err = Wrapper:new(address)
    if not instance then
        return nil, err
    end

    self._components[key] = instance
    return instance
end

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

function Cache:setLastBuffer(snapshot)
    self._lastBuffer = snapshot
end

function Cache:getLastBuffer()
    return self._lastBuffer
end

function Cache:setLastMachineScan(scan)
    self._lastMachineScan = scan
end

function Cache:getLastMachineScan()
    return self._lastMachineScan
end

return Cache
