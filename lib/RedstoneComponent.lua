local BaseComponent = require("BaseComponent")

local RedstoneComponent = setmetatable({}, BaseComponent)
RedstoneComponent.__index = RedstoneComponent

function RedstoneComponent:new(address)
    return BaseComponent.new(self, address)
end

function RedstoneComponent:setOutput(side, value)
    local result, err = self:call(
        "setOutput",
        side,
        value
    )

    if result == nil then
        return false, err
    end

    return true
end

function RedstoneComponent:pulse(side, duration)
    local ok, err = self:setOutput(side, 15)

    if not ok then
        return false, err
    end

    os.sleep(duration)

    return self:setOutput(side, 0)
end

return RedstoneComponent
