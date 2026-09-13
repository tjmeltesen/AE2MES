---@meta _
---@brief Aggregates component wrappers and hardware operations for one machine node.
---@version 1.0.0
---
---@class NodeComponent
---@field transposer TransposerComponent|nil
---@field interface Interface|nil
---@field machine Machine|nil
---@field database DatabaseComponent|nil
---@field redstone RedstoneComponent|nil
---@field transposerSides table<string, integer> # Registry role-to-side map.
---@field redstoneSides table<string, integer> # Registry role-to-side map.

local TransposerComponent = require("TransposerComponent")
local Interface = require("Interface")
local Machine = require("Machine")
local DatabaseComponent = require("DatabaseComponent")
local RedstoneComponent = require("RedstoneComponent")
local NodeComponent = {}
NodeComponent.__index = NodeComponent

---Create a node aggregate from optional preconstructed component wrappers.
---No wrapper validation or component I/O is performed.
---@param transposerObj TransposerComponent | nil # The transposer component object.
---@param interfaceObj Interface | nil # The interface component object.
---@param machineObj Machine | nil # The machine component object.
---@param databaseObj DatabaseComponent | nil # The database component object.
---@param redstoneObj RedstoneComponent | nil # The redstone component object.
---@return NodeComponent node
function NodeComponent:new(transposerObj, interfaceObj, machineObj, databaseObj, redstoneObj)
    local self = setmetatable({}, NodeComponent)
    self.transposer = transposerObj
    self.interface = interfaceObj
    self.machine = machineObj
    self.database = databaseObj
    self.redstone = redstoneObj
    self.transposerSides = {}
    self.redstoneSides = {}
    return self
end

---============================================================
--- Registry configuration helpers
---============================================================

---Read a registry value from a raw table or Assignment Registry wrapper.
---@param registry table # Raw registry map or object exposing `get`.
---@param key string # Registry key to look up.
---@return any # Stored value, or nil when absent.
local function registryValue(registry, key)
    if type(registry.get) == "function" then
        return registry:get(key)
    end
    return registry[key]
end

---Read a non-empty string address from a registry.
---@param registry table # Raw registry map or object exposing `get`.
---@param key string # Registry key to look up (e.g. "machineAddress").
---@return string | nil # The address string, or nil when missing or empty.
local function registryAddress(registry, key)
    local value = registryValue(registry, key)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

---Build a READY node from an approved machine mapping and sticky ComponentCache Globals.
---Reuses `configureFromRegistry` for wiring. Interface wrappers are created here (lazily),
---not during discovery. Cluster `redstoneSides` come from Globals only.
---@param mapping table # Cloud machine mapping (addresses, sides, mappingRevision, status).
---@param globals? { databaseAddress?: string, databaseSize?: integer, redstoneAddress?: string, redstoneSides?: table }
---@param componentCache? ComponentCache # Hardware wrapper identity store.
---@return NodeComponent|nil node
---@return string|nil error
function NodeComponent:fromMapping(mapping, globals, componentCache)
    if type(mapping) ~= "table" then
        return nil, "NodeComponent:fromMapping() — expected machine mapping table"
    end
    if mapping.status ~= nil and mapping.status ~= "READY" then
        return nil, "NodeComponent:fromMapping() — machine mapping is not READY"
    end
    globals = type(globals) == "table" and globals or {}

    local registry = {
        machineAddress = mapping.machineAddress,
        interfaceAddress = mapping.interfaceAddress,
        transposerAddress = mapping.transposerAddress,
        transposerSides = mapping.transposerSides,
        redstoneSides = globals.redstoneSides,
    }

    local node = NodeComponent:new()
    local ok, err = node:configureFromRegistry(registry, globals, componentCache)
    if not ok then
        return nil, err
    end

    node.machineAddress = registry.machineAddress
    node.interfaceAddress = registry.interfaceAddress
    node.transposerAddress = registry.transposerAddress
    node.mappingRevision = mapping.mappingRevision
    return node
end

---Configure per-machine hardware from a cloud registry and broker-global hardware locally.
---Side maps are replaced before wrapper construction, so an error can leave partial configuration.
---Missing component addresses are allowed because some workflows use only a subset of wrappers.
---@param registry table # Raw registry map or Assignment Registry wrapper.
---@param globals? { databaseAddress?: string, databaseSize?: integer, redstoneAddress?: string }
---@param componentCache? ComponentCache # Sticky ComponentCache for wrapper identity.
---@return boolean ok # True when every requested wrapper was constructed.
---@return string | nil error # Component construction or registry validation error.
function NodeComponent:configureFromRegistry(registry, globals, componentCache)
    if type(registry) ~= "table" then
        return false, "NodeComponent:configureFromRegistry() — expected registry table"
    end

    local transposerSides = registryValue(registry, "transposerSides")
    local redstoneSides = registryValue(registry, "redstoneSides")
    self.transposerSides = type(transposerSides) == "table" and transposerSides or {}
    self.redstoneSides = type(redstoneSides) == "table" and redstoneSides or {}

    local machineAddr = registryAddress(registry, "machineAddress")
    local transposerAddr = registryAddress(registry, "transposerAddress")
    local interfaceAddr = registryAddress(registry, "interfaceAddress")
    globals = type(globals) == "table" and globals or {}
    local databaseAddr = globals.databaseAddress
    local redstoneAddr = globals.redstoneAddress

    if machineAddr then
        local _, setErr
        if componentCache then self.machine, setErr = componentCache:getComponent(machineAddr, "Machine")
        else self.machine, setErr = self:setMachine(machineAddr) end
        if setErr then
            return false, setErr
        end
    end

    if transposerAddr then
        local _, setErr
        if componentCache then self.transposer, setErr = componentCache:getComponent(transposerAddr, "TransposerComponent")
        else self.transposer, setErr = self:setTransposer(transposerAddr) end
        if setErr then
            return false, setErr
        end
    end

    if databaseAddr then
        local database, setErr
        if componentCache then
            database, setErr = componentCache:getComponent(
                databaseAddr,
                "DatabaseComponent",
                globals.databaseSize
            )
            self.database = database
        else
            database, setErr = self:setDatabase(databaseAddr, globals.databaseSize)
        end
        if not database then
            return false, setErr
        end
    end

    if interfaceAddr then
        local _, setErr
        if componentCache then self.interface, setErr = componentCache:getComponent(interfaceAddr, "Interface", self.database)
        else self.interface, setErr = self:setInterface(interfaceAddr) end
        if setErr then
            return false, setErr
        end
    end

    if redstoneAddr then
        local redstone, setErr
        if componentCache then
            redstone, setErr = componentCache:getComponent(redstoneAddr, "RedstoneComponent")
            self.redstone = redstone
        else
            redstone, setErr = self:setRedstone(redstoneAddr)
        end
        if not redstone then
            return false, setErr
        end
    end

    return true
end

local function mergeValue(target, key, incoming, path)
    if incoming == nil then return true end
    if target[key] == nil then target[key] = incoming return true end
    if target[key] ~= incoming then return false, "topology_changed: " .. path end
    return true
end

---Fill explicitly missing cached topology fields. Existing values are never overwritten.
function NodeComponent:mergeRegistry(registry)
    if registry == nil then return true end
    if type(registry) ~= "table" then return false, "topology_changed: invalid registry" end
    local ok, err
    ok, err = mergeValue(self, "machineAddress", registryAddress(registry, "machineAddress"), "machineAddress")
    if not ok then return false, err end
    ok, err = mergeValue(self, "interfaceAddress", registryAddress(registry, "interfaceAddress"), "interfaceAddress")
    if not ok then return false, err end
    ok, err = mergeValue(self, "transposerAddress", registryAddress(registry, "transposerAddress"), "transposerAddress")
    if not ok then return false, err end
    for _, pair in ipairs({ { "transposerSides", self.transposerSides }, { "redstoneSides", self.redstoneSides } }) do
        local incoming = registryValue(registry, pair[1])
        if type(incoming) == "table" then
            for role, side in pairs(incoming) do
                ok, err = mergeValue(pair[2], role, side, pair[1] .. "." .. tostring(role))
                if not ok then return false, err end
            end
        end
    end
    return true
end

---Resolve a transposer role name to an OpenComputers side index.
---Numeric values pass through unchanged; unsupported types and unknown roles return nil.
---@param role string|number
---@return number|nil side
function NodeComponent:transposerSide(role)
    if type(role) == "number" then
        return role
    end
    if type(role) == "string" then
        return self.transposerSides[role]
    end
    return nil
end

---Resolve a redstone role name to an OpenComputers side index.
---Numeric values pass through unchanged; unsupported types and unknown roles return nil.
---@param role string|number
---@return number|nil side
function NodeComponent:redstoneSide(role)
    if type(role) == "number" then
        return role
    end
    if type(role) == "string" then
        return self.redstoneSides[role]
    end
    return nil
end

---Construct and assign the node's transposer wrapper.
---A failed construction replaces any previous wrapper with nil and returns a generic error.
---@param transposerAddr string # The address of the transposer component.
---@return TransposerComponent|nil transposer
---@return string|nil error
function NodeComponent:setTransposer(transposerAddr)
    self.transposer = TransposerComponent:new(transposerAddr)
    if not self.transposer then
        return nil, "Failed to create TransposerComponent instance"
    end
    return self.transposer
end

---Construct and assign the node's interface wrapper, binding the current database when present.
---A failed construction replaces any previous wrapper with nil and returns a generic error.
---@param interfaceAddr string # The address of the interface component.
---@return Interface|nil interface
---@return string|nil error
function NodeComponent:setInterface(interfaceAddr)
    self.interface = Interface:new(interfaceAddr, self.database)
    if not self.interface then
        return nil, "Failed to create InterfaceComponent instance"
    end
    return self.interface
end

---Construct and assign the node's machine wrapper.
---A failed construction replaces any previous wrapper with nil and returns a generic error.
---@param machineAddr string # The address of the machine component.
---@return Machine|nil machine
---@return string|nil error
function NodeComponent:setMachine(machineAddr)
    self.machine = Machine:new(machineAddr)
    if not self.machine then
        return nil, "Failed to create MachineComponent instance"
    end
    return self.machine
end

---Construct and assign the node's database wrapper.
---Construction scans the database immediately. On success, any existing interface is rebound to
---the new database; on failure the previous database is replaced with nil.
---@param databaseAddr string # The address of the database component.
---@param size? integer # Optional database slot count; defaults to 9.
---@return DatabaseComponent|nil database
---@return string|nil error
function NodeComponent:setDatabase(databaseAddr, size)
    self.database = DatabaseComponent:new(databaseAddr, size)
    if not self.database then
        return nil, "Failed to create DatabaseComponent instance"
    end
    if self.interface then
        self.interface:bindDatabase(self.database)
    end
    return self.database
end

---Construct and assign the node's redstone wrapper.
---A failed construction replaces any previous wrapper with nil and returns a generic error.
---@param redstoneAddr string # The address of the redstone component.
---@return RedstoneComponent|nil redstone
---@return string|nil error
function NodeComponent:setRedstone(redstoneAddr)
    self.redstone = RedstoneComponent:new(redstoneAddr)
    if not self.redstone then
        return nil, "Failed to create RedstoneComponent instance"
    end
    return self.redstone
end

---Get the node's current transposer wrapper.
---@return TransposerComponent | nil # The transposer component object.
function NodeComponent:getTransposer()
    return self.transposer
end

---Get the node's current interface wrapper.
---@return Interface | nil # The interface component object.
function NodeComponent:getInterface()
    return self.interface
end

---Get the node's current machine wrapper.
---@return Machine | nil # The machine component object.
function NodeComponent:getMachine()
    return self.machine
end

---Get the node's current database wrapper.
---@return DatabaseComponent | nil # The database component object.
function NodeComponent:getDatabase()
    return self.database
end

---Get the node's current redstone wrapper.
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
---Uses `os.clock` for its deadline, sleeps between checks, and performs one final check at timeout.
---Predicate and sleep errors propagate.
---@param predicate fun(): boolean # Function evaluated each poll interval.
---@param timeoutSec number # Maximum seconds to wait.
---@return boolean # True when the predicate succeeds during polling or on the final timeout check.
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
---Component errors are collapsed to false.
---@param transposer TransposerComponent # Transposer used to inspect inventory.
---@param side number # OC side index to inspect.
---@return boolean # True when one or more stacks are present.
local function sideHasItems(transposer, side)
    local contents = transposer:getInventoryContents(side)
    return contents ~= nil and #contents > 0
end

---Check whether a transposer side has no item stacks remaining.
---Component errors are collapsed to false rather than treated as empty.
---@param transposer TransposerComponent # Transposer used to inspect inventory.
---@param side number # OC side index to inspect.
---@return boolean # True when the side inventory is empty.
local function sideIsEmpty(transposer, side)
    local contents = transposer:getInventoryContents(side)
    return contents ~= nil and #contents == 0
end

---Check whether a database contains at least one non-fluid item entry.
---Scans every configured slot and ignores per-slot component errors.
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
---Missing wrappers or unavailable telemetry return false.
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
---Completion is inferred from current/max progress or the `recipe_complete` reason code.
---@param machine Machine|nil
---@return boolean done
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

---Move leftover stacks from the machine input bus to the configured return chest.
---Returns nil when required wiring is absent. Returns zero when the source is empty or its inventory
---cannot be read, and otherwise forwards the transposer drain result and error unchanged.
---@param self NodeComponent
---@param inputSide number
---@return number|nil moved
---@return string|nil error
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

---Clear interface configuration references and the database slots staged for this transfer.
---@param self NodeComponent
---@return nil
local function clearStagedConfiguration(self)
    self.interface:clearAllConfigurations()
    if self.database and type(self.database.clearTracked) == "function" then
        self.database:clearTracked()
    end
end

---============================================================
--- Job execution
---============================================================

---Transfer stocked items and fluids from the ME interface into the machine input bus.
---Configures the interface from the node database, immediately drains available contents into the input bus,
---clears interface configs, pulses redstone for next job start, and optionally confirms processing began.
---Returns false for missing wiring, unresolved roles, transposer failure, or timeout. Configuration,
---clear, pulse, and rollback errors are not checked. Successful paths attempt to return any remaining
---machine-input items through `returnSide`. This implementation also reads/writes the globals
---`startSide` and `stopSide`; its dot-style pulse call raises when reached with the bundled
---colon-defined `RedstoneComponent:pulse` method.
---@param fromSide number | string | nil # Transposer side facing the interface; defaults to transposerSides.pull.
---@param toSide number | string | nil # Transposer side facing the machine input bus; defaults to transposerSides.input.
---@param opts? { requireProcessing?: boolean } # When false, skip waiting for machine to start (default true).
---@return boolean ok # True when transfer completes; false on missing wiring, drain failure, or processing timeout.
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
    local startSide = self:redstoneSide("start")
    local stopSide = self:redstoneSide("stop")
    if not self.interface or not self.database or not self.transposer or not self.redstone then
        return false
    end
    if not fromSide or not toSide or not startSide or not stopSide then
        return false
    end

    if type(self.interface.bindDatabase) == "function" then
        self.interface:bindDatabase(self.database)
    end
    self.interface:setAllConfigurations()


    local moved = self.transposer:drainInventory(fromSide, toSide)
    if moved == nil then
        clearStagedConfiguration(self)
        return false
    end

    if moved > 0 then
        if not waitUntil(function()
            return sideIsEmpty(self.transposer, fromSide)
        end, DRAIN_TIMEOUT_SEC) then
            clearStagedConfiguration(self)
            return false
        end
    end

    clearStagedConfiguration(self)
    self.redstone:pulse(startSide, 1)
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
---Missing machine wrappers and unavailable telemetry return false.
---@return boolean # True when sensor progress reports recipe complete.
function NodeComponent:isDone()
    return machineIsDone(self.machine)
end

return NodeComponent
