---@meta _
---@brief Wraps all Component Objects into a single table referencing a Machine Node, each node carries a Transposer, Interface, databaseObj and Machine Component
---@version 1.0.0
---@class NodeComponent 
---@
---@
---@

local NodeComponent = {}
NodeComponent.__index = NodeComponent

function NodeComponent:new(transposerObj, interfaceObj, machineObj, databaseObj)
    local self = setmetatable({}, NodeComponent)
    self.transposer = transposerObj
    self.interface = interfaceObj
    self.machine = machineObj
    self.database = databaseObj
    return self
end

function NodeComponent:getTransposer()
    return self.transposer
end

function NodeComponent:getInterface()
    return self.interface
end

function NodeComponent:getMachine()
    return self.machine
end

function NodeComponent:getDatabase()
    return self.database
end

-- Idea is that based on the Cloud passdown we construct our node object which we then use to process the job
function NodeComponent:processJob(jobID) end

-- This will be used to transfer the items from the buffer to the machine --> into the bus ensure empty for both fluids and items --> done
---@return boolean True if the transfer was successful, false otherwise
function NodeComponent:transferToMachine()
    local fromSide = 1
    local toSide = 2
    self.interface.clearAllConfigurations()
    self.interface.setAllConfigurations(self.database)
    self.transposer.drainInventory(fromSide, toSide)
    while not self.interface:isEmpty() do
        os.sleep(0.1)
    end
    return true
    --[[ self.machine:parseSensorInformation() If processing then initiate empty from bus to chest --> Return for residual items.
    if self.machine:isProcessing() then
        return true
    end
    return false ]]
end


return NodeComponent