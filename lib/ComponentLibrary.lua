---@meta _
---@brief Typed wrapper around OpenComputers component library
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/libs/component.lua
---@version 1.0.0

---@class ComponentLibrary
local ComponentLibrary = {}

local function oc()
    return require("component")
end

---Returns the documentation string for a component method, if any.
---@param address string
---@param methodName string
---@return string|nil
function ComponentLibrary.doc(address, methodName)
    return oc().doc(address, methodName)
end

---Calls a component method by address (dot-call semantics).
---@param address string
---@param methodName string
---@vararg any
---@return any
function ComponentLibrary.invoke(address, methodName, ...)
    return oc().invoke(address, methodName, ...)
end

---Gets a list of all components, optionally filtered by type.
---@param filter? string
---@param exact? boolean
---@return table<string, string>
function ComponentLibrary.list(filter, exact)
    return oc().list(filter, exact)
end

---Returns method names and whether each is called directly (dot-call).
---@param address string
---@return table<string, boolean>
function ComponentLibrary.methods(address)
    return oc().methods(address)
end

---Gets a proxy object for a component address.
---@generic T
---@param address string
---@param type? `T`
---@return T|nil
---@return string|nil
function ComponentLibrary.proxy(address, type)
    local ok, proxy = pcall(oc().proxy, address, type)
    if not ok or not proxy then
        return nil, "ComponentLibrary.proxy() — failed for " .. tostring(address)
    end
    return proxy
end

---Get the component type for an address.
---@param address string
---@return string|nil
---@return string|nil
function ComponentLibrary.type(address)
    return oc().type(address)
end

---Returns the slot number of a component within the machine, or -1.
---@param address string
---@return integer
function ComponentLibrary.slot(address)
    local slot = oc().slot(address)
    if slot == nil then
        return -1
    end
    return slot
end

---Resolves an abbreviated address to a full address.
---@param address string
---@param type? string
---@return string|nil
---@return string|nil
function ComponentLibrary.get(address, type)
    return oc().get(address, type)
end

---Checks if a component of a specific type is available.
---@param type string
---@return boolean
function ComponentLibrary.isAvailable(type)
    return oc().isAvailable(type)
end

---Gets a proxy to the primary component of a given type.
---@generic T
---@param type `T`
---@return T
function ComponentLibrary.getPrimary(type)
    return oc().getPrimary(type)
end

---Sets the primary component for a given type.
---@param type string
---@param address string|nil
function ComponentLibrary.setPrimary(type, address)
    return oc().setPrimary(type, address)
end

return ComponentLibrary
