---@meta _
---@brief API Wrapper for MEController component combined with CommonNetworkAPI in OpenComputers Applied Energistics 2
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/me-controller.lua
---@version 1.0.0
---@class MeControllerComponent : BaseComponent

local BaseComponent = require("BaseComponent")


local MeControllerComponent = setmetatable({}, { __index = BaseComponent })
MeControllerComponent.__index = MeControllerComponent

---Creates a new MeControllerComponent instance with the specified address.
---@param address string # The address of the me controller component.
---@return MeControllerComponent | nil, string | nil # A new instance of MeControllerComponent. Will return nil and an error message if the address is invalid.
function MeControllerComponent:new(address)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    return self
end




return MeControllerComponent
