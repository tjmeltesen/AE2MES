---@meta _
---@brief API Wrapper for Base Components in OpenComputers
---@version 1.0.0
---@class BaseComponent
---@field address string
---@field slot integer
---@field proxy any

local component = require("component")

local unpack = table.unpack or unpack

local BaseComponent = {}
BaseComponent.__index = BaseComponent

function BaseComponent:new(address)
    if type(address) ~= "string" or address == "" then
        return nil, "BaseComponent:new() — invalid address"
    end

    local self = setmetatable({}, self)
    self.address = address
    self.slot = -1
    self.proxy = nil
    return self
end

function BaseComponent:getAddress()
    return self.address
end

function BaseComponent:getType()
    return component.type(self.address)
end

function BaseComponent:getProxy()
    if self.proxy then
        return self.proxy
    end

    local ok, proxy = pcall(component.proxy, self.address)
    if not ok or not proxy then
        return nil, "BaseComponent:getProxy() — component.proxy failed for " .. self.address
    end

    self.proxy = proxy
    return self.proxy
end

function BaseComponent:invalidate()
    self.proxy = nil
end

function BaseComponent:isAvailable()
    return component.isAvailable(self.address)
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

    if component.invoke then
        local ok, result = pcall(function()
            if nargs == 0 then
                return component.invoke(self.address, method)
            end
            return component.invoke(self.address, method, unpack(args))
        end)

        if ok then
            return result
        end
    end

    local proxy, err = self:getProxy()
    if not proxy then
        return nil, err
    end

    local fn = proxy[method]
    if type(fn) ~= "function" then
        return nil, "BaseComponent:callNetwork() — method unavailable: " .. tostring(method)
    end

    local ok, result = pcall(function()
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

return BaseComponent
