---@meta _
---@brief API wrapper for the OpenComputers AE2 ME controller and inherited CommonNetworkAPI.
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/me-controller.lua
---@version 1.0.0
---@class MeControllerComponent : BaseComponent
---@field address string # OpenComputers component address inherited from BaseComponent.

local BaseComponent = require("BaseComponent")


local MeControllerComponent = setmetatable({}, { __index = BaseComponent })
MeControllerComponent.__index = MeControllerComponent

---Create an ME controller wrapper for the specified component address.
---All network operations are inherited from BaseComponent.
---@param address string # The address of the me controller component.
---@return MeControllerComponent|nil controller
---@return string|nil error # Invalid addresses are rejected by BaseComponent.
function MeControllerComponent:new(address)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    return self
end




return MeControllerComponent
