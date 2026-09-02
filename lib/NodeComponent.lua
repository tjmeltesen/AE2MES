---@meta _
---@brief Wraps all Component Objects into a single table referencing a Machine Node.
---@version 1.0.0
---
--- MES Cloud Assignment JSON (schemaVersion 1):
--- {
---   "schemaVersion": 1,
---   "jobId": "job-cloud-001",
---   "machineAddress": "machine-lathe",
---   "registry": {
---     "machineAddress": "machine-lathe",
---     "transposerAddress": "transposer-001",
---     "interfaceAddress": "iface-001",
---     "databaseAddress": "db-001",
---     "redstoneAddress": "rs-001",
---     "transposerSides": { "pull": 1, "input": 2, "returnSide": 3 },
---     "redstoneSides": { "start": 2, "stop": 3 }
---   },
---   "sequenceFlow": {
---     "items": [{ "name": "minecraft:iron_ingot", "count": 64 }],
---     "fluids": [],
---     "steps": [
---       { "method": "transferToMachine", "params": {} },
---       { "method": "waitForProcess", "params": { "timeout": 600 } }
---     ]
---   }
--- }
---
---@class NodeComponent
---@field transposer TransposerComponent | nil
---@field interface Interface | nil
---@field machine Machine | nil
---@field database DatabaseComponent | nil
---@field redstone RedstoneComponent | nil
---@field schemaVersion number
---@field jobId string | nil
---@field machineAddress string | nil
---@field transposerSides table
---@field redstoneSides table
---@field items table
---@field fluids table
---@field steps table

local JSON = require("JSON")
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
    self.schemaVersion = nil
    self.jobId = nil
    self.machineAddress = nil
    self.transposerSides = {}
    self.redstoneSides = {}
    self.items = {}
    self.fluids = {}
    self.steps = {}
    return self
end

---============================================================
--- Assignment parsing helpers
---============================================================

---Read a non-empty string address from a registry table entry.
---@param registry table # Assignment registry map from cloud JSON.
---@param key string # Registry key to look up (e.g. "machineAddress").
---@return string | nil # The address string, or nil when missing or empty.
local function registryAddress(registry, key)
    local value = registry[key]
    if type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

---Normalize assignment input into a plain schema-v1 table.
---Accepts a JSON string, a raw assignment table, or a parsed Assignment object from src/Assignment.lua.
---@param input string | table # JSON string, assignment table, or Assignment instance.
---@return table | nil data # Normalized assignment table.
---@return string | nil error # Error message when normalization fails.
local function coerceAssignment(input)
    if type(input) == "string" then
        local ok, data = pcall(JSON.decode, input)
        if not ok then
            return nil, "NodeComponent:readAssignment() — JSON decode failed: " .. tostring(data)
        end
        return data
    end

    if type(input) ~= "table" then
        return nil, "NodeComponent:readAssignment() — expected JSON string or assignment table"
    end

    if type(input.id) == "function" and type(input.registry) == "function" then
        local registry = input:registry()
        local sequenceFlow = input:sequenceFlow()
        local registryData = {}

        if registry and type(registry.get) == "function" then
            for _, key in ipairs({
                "machineAddress",
                "transposerAddress",
                "interfaceAddress",
                "databaseAddress",
                "redstoneAddress",
                "transposerSides",
                "redstoneSides",
            }) do
                local value = registry:get(key)
                if value ~= nil then
                    registryData[key] = value
                end
            end
        end

        return {
            schemaVersion = type(input.schemaVersion) == "function" and input:schemaVersion() or 1,
            jobId = input:id(),
            machineAddress = input:machineAddress(),
            registry = registryData,
            sequenceFlow = sequenceFlow and {
                items = sequenceFlow.items or {},
                fluids = sequenceFlow.fluids or {},
                steps = sequenceFlow.steps or {},
            } or { items = {}, fluids = {}, steps = {} },
        }
    end

    return input
end

---Load job metadata, registry side maps, sequence flow, and wire component wrappers from an assignment.
---Populates schemaVersion, jobId, machineAddress, transposerSides, redstoneSides, items, fluids, and steps on self,
---then instantiates any component wrappers whose addresses are present in the registry.
---@param input string | table # JSON string or assignment table (schema v1); also accepts parsed Assignment objects from src/Assignment.lua.
---@return boolean ok # True when the assignment was loaded and all component addresses resolved.
---@return string | nil error # Error message when parsing or component wiring fails.
function NodeComponent:readAssignment(input)
    local data, err = coerceAssignment(input)
    if not data then
        return false, err
    end

    if type(data.jobId) ~= "string" then
        return false, "NodeComponent:readAssignment() — assignment missing jobId"
    end

    local registry = data.registry or {}
    local sequenceFlow = data.sequenceFlow or {}

    self.schemaVersion = data.schemaVersion or 1
    self.jobId = data.jobId
    self.machineAddress = data.machineAddress or registryAddress(registry, "machineAddress")
    self.transposerSides = registry.transposerSides or {}
    self.redstoneSides = registry.redstoneSides or {}
    self.items = sequenceFlow.items or {}
    self.fluids = sequenceFlow.fluids or {}
    self.steps = sequenceFlow.steps or {}

    local machineAddr = registryAddress(registry, "machineAddress")
    local transposerAddr = registryAddress(registry, "transposerAddress")
    local interfaceAddr = registryAddress(registry, "interfaceAddress")
    local databaseAddr = registryAddress(registry, "databaseAddress")
    local redstoneAddr = registryAddress(registry, "redstoneAddress")

    if machineAddr then
        local _, setErr = self:setMachine(machineAddr)
        if setErr then
            return false, setErr
        end
    end

    if transposerAddr then
        local _, setErr = self:setTransposer(transposerAddr)
        if setErr then
            return false, setErr
        end
    end

    if databaseAddr then
        local _, setErr = self:setDatabase(databaseAddr)
        if setErr then
            return false, setErr
        end
    end

    if interfaceAddr then
        local _, setErr = self:setInterface(interfaceAddr)
        if setErr then
            return false, setErr
        end
    end

    if redstoneAddr then
        local _, setErr = self:setRedstone(redstoneAddr)
        if setErr then
            return false, setErr
        end
    end

    return true
end

---Resolve a transposer role name to an OC side index.
---@param role string | number
---@return number | nil
function NodeComponent:transposerSide(role)
    if type(role) == "number" then
        return role
    end
    if type(role) == "string" then
        return self.transposerSides[role]
    end
    return nil
end

---Resolve a redstone role name to an OC side index.
---@param role string | number
---@return number | nil
function NodeComponent:redstoneSide(role)
    if type(role) == "number" then
        return role
    end
    if type(role) == "string" then
        return self.redstoneSides[role]
    end
    return nil
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
    self.interface = Interface:new(interfaceAddr, self.database)
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
    if self.interface then
        self.interface:bindDatabase(self.database)
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

---============================================================
--- Transfer pipeline helpers
---============================================================

---Maximum seconds to wait for the interface side to drain after a pull.
local DRAIN_TIMEOUT_SEC = 10
---Maximum seconds to wait for the machine to report active processing.
local PROCESS_TIMEOUT_SEC = 10
---Polling interval used by timed wait helpers.
local POLL_INTERVAL_SEC = 0.1

---Poll a predicate until it returns true or the timeout elapses.
---@param predicate fun(): boolean # Function evaluated each poll interval.
---@param timeoutSec number # Maximum seconds to wait.
---@return boolean # True when predicate returned true before the deadline.
local function waitUntil(predicate, timeoutSec)
    local deadline = os.clock() + timeoutSec
    while os.clock() < deadline do
        if predicate() then
            return true
        end
        os.sleep(POLL_INTERVAL_SEC)
    end
    return predicate()
end

---Check whether a transposer side currently holds at least one item stack.
---@param transposer TransposerComponent # Transposer used to inspect inventory.
---@param side number # OC side index to inspect.
---@return boolean # True when one or more stacks are present.
local function sideHasItems(transposer, side)
    local contents = transposer:getInventoryContents(side)
    return contents ~= nil and #contents > 0
end

---Check whether a transposer side has no item stacks remaining.
---@param transposer TransposerComponent # Transposer used to inspect inventory.
---@param side number # OC side index to inspect.
---@return boolean # True when the side inventory is empty.
local function sideIsEmpty(transposer, side)
    local contents = transposer:getInventoryContents(side)
    return contents ~= nil and #contents == 0
end

---Check whether a database contains at least one non-fluid item entry.
---@param database DatabaseComponent # Database whose slots are scanned.
---@return boolean # True when a solid item stack is configured.
local function databaseHasItems(database)
    for slot = 1, database:getSize() do
        local stack = database:get(slot)
        if stack and stack.fluidDrop == nil then
            return true
        end
    end
    return false
end

---Check whether a GT machine is actively processing a recipe.
---@param machine Machine | nil # Machine component to poll.
---@return boolean # True when pollAvailability reports active processing.
local function machineIsProcessing(machine)
    if not machine then
        return false
    end
    local availability = machine:pollAvailability()
    return availability ~= nil and availability.active == true
end

---Check whether a GT machine has finished its current recipe.
---@param machine Machine | nil
---@return boolean
local function machineIsDone(machine)
    if not machine then
        return false
    end
    local availability = machine:pollAvailability()
    if not availability then
        return false
    end

    local current = availability.progressCurrent
    local max = availability.progressMax
    if type(current) == "number" and type(max) == "number" and max > 0 and current >= max then
        return true
    end

    local reason = availability.unavailableReason or ""
    return reason:find("recipe_complete", 1, true) ~= nil
end

---Move leftover stacks from the machine input bus to the return chest.
---@param self NodeComponent
---@param inputSide number
---@return number|nil moved
local function drainInputToReturn(self, inputSide)
    local returnSide = self:transposerSide("returnSide")
    if not self.transposer or not returnSide or not inputSide then
        return nil
    end
    if not sideHasItems(self.transposer, inputSide) then
        return 0
    end
    return self.transposer:drainInventory(inputSide, returnSide)
end

---============================================================
--- Job execution
---============================================================

---Transfer stocked items and fluids from the ME interface into the machine input bus.
---Configures the interface from the node database, waits for AE2 stocking, drains into the input bus,
---clears interface configs, and optionally confirms the machine started processing.
---@param fromSide number | string | nil # Transposer side facing the interface; defaults to transposerSides.pull.
---@param toSide number | string | nil # Transposer side facing the machine input bus; defaults to transposerSides.input.
---@param opts? { requireProcessing?: boolean } # When false, skip waiting for machine to start (default true).
---@return boolean ok # True when transfer completes; false on timeout, drain error, or rollback.
function NodeComponent:transferToMachine(fromSide, toSide, opts)
    opts = type(opts) == "table" and opts or {}
    local requireProcessing = opts.requireProcessing ~= false

    if type(fromSide) == "string" then
        fromSide = self:transposerSide(fromSide)
    end
    if type(toSide) == "string" then
        toSide = self:transposerSide(toSide)
    end

    fromSide = fromSide or self:transposerSide("pull")
    toSide = toSide or self:transposerSide("input")

    if not self.interface or not self.database or not self.transposer then
        return false
    end
    if not fromSide or not toSide then
        return false
    end

    self.interface:setAllConfigurations()


    local moved = self.transposer:drainInventory(fromSide, toSide)
    if moved == nil then
        self.interface:clearAllConfigurations()
        return false
    end

    if moved > 0 then
        if not waitUntil(function()
            return sideIsEmpty(self.transposer, fromSide)
        end, DRAIN_TIMEOUT_SEC) then
            self.interface:clearAllConfigurations()
            return false
        end
    end

    self.interface:clearAllConfigurations()

    if not requireProcessing then
        drainInputToReturn(self, toSide)
        return true
    end

    if not waitUntil(function()
        return machineIsProcessing(self.machine)
    end, PROCESS_TIMEOUT_SEC) then
        if moved > 0 then
            drainInputToReturn(self, toSide)
        end
        return false
    end

    drainInputToReturn(self, toSide)
    return true
end

---Check whether the active recipe on the machine has finished.
---@return boolean # True when sensor progress reports recipe complete.
function NodeComponent:isDone()
    return machineIsDone(self.machine)
end

---Wait until the machine reports recipe complete or the timeout elapses.
---@param timeout number | table | nil # Seconds to wait, or { timeout = number } from assignment params.
---@return boolean # True when isDone() before the deadline.
function NodeComponent:waitForProcess(timeout)
    if not self.machine then
        return false
    end

    if type(timeout) == "table" then
        timeout = timeout.timeout
    end

    timeout = tonumber(timeout) or 600
    if timeout <= 0 then
        return machineIsDone(self.machine)
    end

    if machineIsDone(self.machine) then
        return true
    end

    return waitUntil(function()
        return machineIsDone(self.machine)
    end, timeout)
end

---Fetch a job assignment from the cloud and execute its sequence flow on this node.
---@param jobID string # Cloud job identifier to load and run.
---@return boolean | nil ok # True when the job completed successfully.
---@return string | nil error # Error message when the job cannot be loaded or executed.
function NodeComponent:executeJobAssignment(jobID) end



return NodeComponent