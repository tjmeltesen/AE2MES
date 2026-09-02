---@meta _
---@brief Deprecated — use BaseComponent class methods instead.
---@see BaseComponent
---@version 1.0.0

local BaseComponent = require("BaseComponent")

---@class ComponentLibrary
local ComponentLibrary = {
    doc = BaseComponent.docFor,
    invoke = BaseComponent.invokeFor,
    list = BaseComponent.list,
    methods = BaseComponent.methodsFor,
    proxy = BaseComponent.proxyFor,
    type = BaseComponent.typeFor,
    slot = BaseComponent.slotFor,
    get = BaseComponent.resolve,
    isAvailable = BaseComponent.isAvailable,
    getPrimary = BaseComponent.getPrimary,
    setPrimary = BaseComponent.setPrimary,
}

return ComponentLibrary
