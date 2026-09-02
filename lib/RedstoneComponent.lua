---@meta _
---@brief API Wrapper for Redstone component in OpenComputers for GTNH
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/redstone.lua
---@version 1.0.0
---@class RedstoneComponent : BaseComponent
---@field address string

local BaseComponent = require("BaseComponent")

local RedstoneComponent = setmetatable({}, { __index = BaseComponent })
RedstoneComponent.__index = RedstoneComponent


---Creates a new RedstoneComponent instance with the specified address.
---@param address string # The address of the redstone component.
---@return RedstoneComponent | nil, string | nil # A new instance of RedstoneComponent. Will return nil and an error message if the address is invalid.
function RedstoneComponent:new(address)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    return self
end


---Sets the strength of the redstone signal to emit on a specific side.
---@param side integer # The side to set the output on.
---@param value integer # The value to output on the specified side.
---@return integer | nil, string | nil # Returns the old output value on that side. This can be an arbitrarily large number for mods that support this. If the output was not set successfully, returns nil and an error message.
function RedstoneComponent:setOutput(side, value)
    local result, err = self:call(
        "setOutput",
        side,
        value
    )
    
    return result, err
end


---Pulses the redstone signal on the specified side for the specified duration.
---@param side integer # The side to pulse the redstone signal on.
---@param duration number # The duration in seconds to pulse the redstone signal for.
---@return boolean | nil, string | nil # True if the redstone signal was pulsed successfully, false and an error message if the redstone signal was not pulsed successfully.
function RedstoneComponent:pulse(side, duration)
    local result, err = self:setOutput(side, 15)
    if not result then
        return nil, err
    end

    os.sleep(duration)

    result, err = self:setOutput(side, 0)
    if not result then
        return nil, err
    end

    return true, nil
end

return RedstoneComponent
