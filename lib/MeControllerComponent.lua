---@meta _
---@brief API Wrapper for MEController component combined with CommonNetworkAPI in OpenComputers Applied Energistics 2
---@version 1.0.0
---@class MeControllerComponent : BaseComponent
---@field address string

local BaseComponent = require("BaseComponent")
local NetworkItems = require("NetworkItems")

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


---Get an iterator object for the list of the items in the network.
---@return fun():MEItemStack|nil
function MeControllerComponent:allItems()
    return self:callNetwork("allItems")
end


---Get a list of the stored items in the network.
---@param filter? MEItemStackFilter A filter for the query
---@return MEItemStack[]
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

---Get a list of the stored fluids in the network.
---@return MEFluidStack[]
function MeControllerComponent:getFluidsInNetwork()
    return self:callNetwork("getFluidsInNetwork")
end

---Get a list of the stored essentia in the network.
---@return EssentiaStack[]
function MeControllerComponent:getEssentiaInNetwork()
    return self:callNetwork("getEssentiaInNetwork")
end

---Store items in the network matching the specified filter in the database with the specified address.
---@param filter MEItemStackFilter # A filter of items to look for.
---@param dbAddress string # Address of the internal database to store items to.
---@param startSlot? integer # Optional, start index of the first item to store.
---@param count? integer # Optional, how many items to store.
---@return boolean
function MeControllerComponent:store(filter, dbAddress, startSlot, count)
    return self:callNetwork("store", filter, dbAddress, startSlot, count)
end

---Get a list of all available cpus on the network.
---@return AECpuMetadata[]
function MeControllerComponent:getCpus()
    return self:callNetwork("getCpus")
end

---Get a list of known item recipes. These can be used to issue crafting requests.
---@param filter? MEItemStackFilter # A filter of items to look for.
---@return AECraftable[]
function MeControllerComponent:getCraftables(filter)
    if filter ~= nil then
        return self:callNetwork("getCraftables", filter)
    end
    return self:callNetwork("getCraftables")
end

---Get the average power injection into the network.
---@return number
function MeControllerComponent:getAvgPowerInjection()
    return self:callNetwork("getAvgPowerInjection")
end

---Get the average power usage of the network.
---@return number
function MeControllerComponent:getAvgPowerUsage()
    return self:callNetwork("getAvgPowerUsage")
end

---Get the maximum stored power in the network.
---@return number
function MeControllerComponent:getMaxStoredPower()
    return self:callNetwork("getMaxStoredPower")
end

---Get the stored power in the network. 
---@return number
function MeControllerComponent:getStoredPower()
    return self:callNetwork("getStoredPower")
end

---Get the idle power usage of the network.
---@return number
function MeControllerComponent:getIdlePowerUsage()
    return self:callNetwork("getIdlePowerUsage")
end

---Normalized snapshot packaged as a lua table (items + fluids in ME network).
---@return table
function MeControllerComponent:getSnapshot()
    return NetworkItems.formatContents(
        self:getItemsInNetwork(),
        self:getFluidsInNetwork()
    )
end

return MeControllerComponent
