---@class MeControllerComponent : BaseComponent
--- CommonNetworkAPI wrapper — dot-call via callNetwork, not call (colon-call).

local BaseComponent = require("BaseComponent")
local NetworkItems = require("NetworkItems")

local MeControllerComponent = setmetatable({}, BaseComponent)
MeControllerComponent.__index = MeControllerComponent

function MeControllerComponent:new(address)
    return BaseComponent.new(self, address)
end

function MeControllerComponent:allItems()
    return self:callNetwork("allItems")
end

function MeControllerComponent:getItemsInNetwork(filter)
    local raw
    if filter ~= nil then
        raw = self:callNetwork("getItemsInNetwork", filter)
    else
        raw = self:callNetwork("getItemsInNetwork")
        if NetworkItems.isEmpty(raw) then
            raw = self:allItems()
        end
    end
    return raw
end

function MeControllerComponent:getFluidsInNetwork()
    return self:callNetwork("getFluidsInNetwork")
end

function MeControllerComponent:getEssentiaInNetwork()
    return self:callNetwork("getEssentiaInNetwork")
end

function MeControllerComponent:store(filter, dbAddress, startSlot, count)
    return self:callNetwork("store", filter, dbAddress, startSlot, count)
end

function MeControllerComponent:getCpus()
    return self:callNetwork("getCpus")
end

function MeControllerComponent:getCraftables(filter)
    if filter ~= nil then
        return self:callNetwork("getCraftables", filter)
    end
    return self:callNetwork("getCraftables")
end

function MeControllerComponent:getAvgPowerInjection()
    return self:callNetwork("getAvgPowerInjection")
end

function MeControllerComponent:getAvgPowerUsage()
    return self:callNetwork("getAvgPowerUsage")
end

function MeControllerComponent:getMaxStoredPower()
    return self:callNetwork("getMaxStoredPower")
end

function MeControllerComponent:getStoredPower()
    return self:callNetwork("getStoredPower")
end

function MeControllerComponent:getIdlePowerUsage()
    return self:callNetwork("getIdlePowerUsage")
end

---Normalized buffer snapshot for cloud uplink (items + fluids in ME network).
---@return table
function MeControllerComponent:getBufferSnapshot()
    return NetworkItems.formatContents(
        self:getItemsInNetwork(),
        self:getFluidsInNetwork()
    )
end

return MeControllerComponent
