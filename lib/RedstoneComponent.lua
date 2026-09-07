---@meta _
---@brief API wrapper for the OpenComputers redstone component in GTNH.
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/redstone.lua
---@version 1.0.0
---@class RedstoneComponent : BaseComponent
---@field address string # OpenComputers component address inherited from BaseComponent.

local BaseComponent = require("BaseComponent")

local RedstoneComponent = setmetatable({}, { __index = BaseComponent })
RedstoneComponent.__index = RedstoneComponent


---Create a redstone wrapper for the specified component address.
---@param address string # The address of the redstone component.
---@return RedstoneComponent|nil redstone
---@return string|nil error # Invalid addresses are rejected by BaseComponent.
function RedstoneComponent:new(address)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    return self
end


---Set the redstone output strength on a side.
---Mutates the component output and converts component invocation exceptions into `nil, error`.
---@param side integer # The side to set the output on.
---@param value integer # The value to output on the specified side.
---@return integer|nil previousValue # Previous output strength, including mod-provided extended values.
---@return string|nil error
function RedstoneComponent:setOutput(side, value)
    local result, err = self:call(
        "setOutput",
        side,
        value
    )
    
    return result, err
end


---Pulse a side at strength 15, then restore it to zero after a delay.
---The prior output value is not restored. If the first write fails no sleep occurs; if the
---second write fails, the output may remain high. Missing/invalid `os.sleep` errors propagate.
---@param side integer # The side to pulse the redstone signal on.
---@param duration number # The duration in seconds to pulse the redstone signal for.
---@return boolean|nil pulsed # True only after both output writes succeed.
---@return string|nil error
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
