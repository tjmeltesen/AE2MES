---@meta _
---@brief Wraps all Component Objects into a single table referencing a Machine Node, each node carries a Transposer, Interface, Database, Redstone, and Machine Component
---@version 1.0.0
---@class NodeComponent 
---@field transposer TransposerComponent | nil
---@field interface Interface | nil
---@field machine Machine | nil
---@field database DatabaseComponent | nil
---@field redstone RedstoneComponent | nil

local TransposerComponent = require("TransposerComponent")
local Interface = require("Interface")
local Machine = require("Machine")
local DatabaseComponent = require("DatabaseComponent")
local RedstoneComponent = require("RedstoneComponent")
local NodeComponent = {}
NodeComponent.__index = NodeComponent

---Creates a new NodeComponent instance with the specified transposer, interface, machine, database and redstone components.
---@param transposerObj TransposerComponent | nil # The transposer component object.
---@param interfaceObj Interface | nil # The interface component object.
---@param machineObj Machine | nil # The machine component object.
---@param databaseObj DatabaseComponent | nil # The database component object.
---@param redstoneObj RedstoneComponent | nil # The redstone component object.
---@return NodeComponent | nil # A new instance of NodeComponent. Will return nil and an error message if the components are invalid.
function NodeComponent:new(transposerObj, interfaceObj, machineObj, databaseObj, redstoneObj)
    local self = setmetatable({}, NodeComponent)
    self.transposer = transposerObj
    self.interface = interfaceObj
    self.machine = machineObj
    self.database = databaseObj
    self.redstone = redstoneObj
    return self
end

---Sets the transposer component for the node.
---@param transposerAddr string # The address of the transposer component.
---@return TransposerComponent | nil, string | nil # The transposer component object. Will return nil and an error message if the address is invalid.
function NodeComponent:setTransposer(transposerAddr)
    self.transposer = TransposerComponent:new(transposerAddr)
    if not self.transposer then
        return nil, "Failed to create TransposerComponent instance"
    end
    return self.transposer
end

---Sets the interface component for the node.
---@param interfaceAddr string # The address of the interface component.
---@return Interface | nil, string | nil # The interface component object. Will return nil and an error message if the address is invalid.
function NodeComponent:setInterface(interfaceAddr)
    self.interface = Interface:new(interfaceAddr)
    if not self.interface then
        return nil, "Failed to create InterfaceComponent instance"
    end
    return self.interface
end

---Sets the machine component for the node.
---@param machineAddr string # The address of the machine component.
---@return Machine | nil, string | nil # The machine component object. Will return nil and an error message if the address is invalid.
function NodeComponent:setMachine(machineAddr)
    self.machine = Machine:new(machineAddr)
    if not self.machine then
        return nil, "Failed to create MachineComponent instance"
    end
    return self.machine
end

---Sets the database component for the node.
---@param databaseAddr string # The address of the database component.
---@return DatabaseComponent | nil, string | nil # The database component object. Will return nil and an error message if the address is invalid.
function NodeComponent:setDatabase(databaseAddr)
    self.database = DatabaseComponent:new(databaseAddr)
    if not self.database then
        return nil, "Failed to create DatabaseComponent instance"
    end
    return self.database
end

---Sets the redstone component for the node.
---@param redstoneAddr string # The address of the redstone component.
---@return RedstoneComponent | nil, string | nil # The redstone component object. Will return nil and an error message if the address is invalid.
function NodeComponent:setRedstone(redstoneAddr)
    self.redstone = RedstoneComponent:new(redstoneAddr)
    if not self.redstone then
        return nil, "Failed to create RedstoneComponent instance"
    end
    return self.redstone
end

---Gets the transposer component for the node.
---@return TransposerComponent | nil # The transposer component object.
function NodeComponent:getTransposer()
    return self.transposer
end

---Gets the interface component for the node.
---@return Interface | nil # The interface component object.
function NodeComponent:getInterface()
    return self.interface
end

---Gets the machine component for the node.
---@return Machine | nil # The machine component object.
function NodeComponent:getMachine()
    return self.machine
end

---Gets the database component for the node.
---@return DatabaseComponent | nil # The database component object.
function NodeComponent:getDatabase()
    return self.database
end

---Gets the redstone component for the node.
---@return RedstoneComponent | nil # The redstone component object.
function NodeComponent:getRedstone()
    return self.redstone
end



-- This will be used to transfer the items from the buffer to the machine --> into the bus ensure empty for both fluids and items --> done
---@return boolean True if the transfer was successful, false otherwise
function NodeComponent:transferToMachine()
    local fromSide = 1
    local toSide = 2
    self.interface:clearAllConfigurations()
    self.interface:setAllConfigurations(self.database)
    self.transposer:drainInventory(fromSide, toSide)
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

-- Idea is that based on the Cloud passdown we construct our node object which we then use to process the job
function NodeComponent:executeJobAssignment(jobID) end --get the job assignment from the cloud which contains the items/fluids to be processed and appropriate machine configurations and steps, set the node object with the appropriate job parameters and execute the job

function NodeComponent:isDone() end -- Return true if the recipe is done, false otherwise



return NodeComponent