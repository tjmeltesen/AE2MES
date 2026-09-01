local BaseComponent = require("BaseComponent")
local NetworkItems = require("NetworkItems")

local Interface = setmetatable({}, BaseComponent)
Interface.__index = Interface

function Interface:new(address)
    return BaseComponent.new(self, address)
end

function Interface:getItemsInNetwork(filter)
    if filter ~= nil then
        return self:callNetwork("getItemsInNetwork", filter)
    end
    return self:callNetwork("getItemsInNetwork")
end

function Interface:getFluidsInNetwork()
    return self:callNetwork("getFluidsInNetwork")
end

function Interface:getContents()
    return NetworkItems.formatContents(
        self:getItemsInNetwork(),
        self:getFluidsInNetwork()
    )
end

function Interface:setConfiguration(slot, dbAddress, dbSlot, count)
    return self:callNetwork(
        "setInterfaceConfiguration",
        slot,
        dbAddress,
        dbSlot,
        count
    )
end

function Interface:clearConfiguration(slot)
    return self:callNetwork(
        "setInterfaceConfiguration",
        slot
    )
end

function Interface:setFluidConfiguration(side, dbAddress, dbSlot)
    return self:callNetwork(
        "setFluidInterfaceConfiguration",
        side,
        dbAddress,
        dbSlot
    )
end

function Interface:clearFluidConfiguration(side)
    return self:callNetwork(
        "setFluidInterfaceConfiguration",
        side
    )
end

function Interface:store(filter, databaseAddress, databaseSlot)
    return self:callNetwork(
        "store",
        filter,
        databaseAddress,
        databaseSlot,
        1
    )
end

return Interface
