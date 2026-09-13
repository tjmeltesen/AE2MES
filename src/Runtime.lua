---@meta _
---@brief Coordinates sensing, cloud scheduling, job execution, and result reporting.
---@version 1.0.0
---
---@class RuntimeConfig
---@field clusterId string | nil
---@field cloudBaseUrl string | nil
---@field meControllerAddr string | nil
---@field bufferSourceAddress string | nil
---@field machineFilter string | nil
---@field statusInterval number | nil
---@field statusRetryDelay number | nil
---@field jobRequestCooldown number | nil
---@field useMockAssignment boolean | nil
---@field mockAssignmentPath string | nil
---@field databaseAddress string | nil
---@field redstoneAddress string | nil
---@field databaseSize integer | nil
---
---@class Runtime
---@field _config RuntimeConfig # Runtime configuration retained by reference.
---@field _componentCache ComponentCache # Hardware wrapper identity store.
---@field _nodeCache NodeCache # Topology-owned READY NodeComponent generations.
---@field _cloudClient CloudClient # Cloud API client.
---@field _nodeSensor NodeSensor # Buffer and machine sensor.
---@field _jobPool JobPool # Assignment scheduler and executor.
---@field _meController MeControllerComponent # Discovered controller used to stage buffer materials.
---@field _database DatabaseComponent # Discovered staging database shared with job nodes.
---@field _redstone RedstoneComponent # Discovered broker-global redstone component.
---@field _machineAddresses string[] # Discovered broker-global machine addresses.
---@field _lastStatusAt number # Time of the last successful status report.
---@field _statusBackoffUntil number # Earliest time for another report after failure.
---@field _lastNoAssignmentDebug string | nil # Signature used to suppress repeated empty-assignment logs.
---@field _running boolean # Whether `tick` should perform work.

local ComponentCache = require("ComponentCache")
local NodeCache = require("NodeCache")
local CloudClient = require("CloudClient")
local NodeSensor = require("NodeSensor")
local JobPool = require("JobPool")
local HardwareDiscovery = require("HardwareDiscovery")


local Runtime = {}
Runtime.__index = Runtime

---Create a runtime, discover global hardware, wipe its staging database, and build services.
---The configuration is shared with the cloud client and node sensor; module-loading
---or collaborator-construction errors are not caught.
---@param config RuntimeConfig | nil # Optional node, cloud, sensor, and interval settings.
---@return Runtime # Running coordinator with discovered global hardware and an empty job pool.
function Runtime.new(config)
    local self = setmetatable({}, Runtime)
    self._config = config or {}
    self._config.clusterId = self._config.clusterId or self._config.nodeId or "unknown-cluster"
    self._componentCache = ComponentCache.new()
    self._nodeCache = NodeCache.new(self._componentCache)
    local globals, discoveryErr = HardwareDiscovery.discover(self._config, self._componentCache)
    if not globals then
        error(discoveryErr)
    end
    self._config.meControllerAddr = globals.meControllerAddr
    self._config.databaseAddress = globals.databaseAddress
    self._config.redstoneAddress = globals.redstoneAddress
    self._config.databaseSize = globals.databaseSize
    globals.machineAddresses = globals.machineAddresses or {}
    globals.globals = globals.globals or {
        meControllerAddress = globals.meControllerAddr,
        databaseAddress = globals.databaseAddress,
        databaseSize = globals.databaseSize,
        redstoneAddress = globals.redstoneAddress,
        machineAddresses = globals.machineAddresses,
    }
    if globals.globals.machineAddresses == nil then
        globals.globals.machineAddresses = globals.machineAddresses
    end
    globals.components = globals.components or { machines = {}, interfaces = {}, transposers = {} }
    self._config.machineAddresses = globals.machineAddresses
    local controller, controllerErr = self._componentCache:getComponent(
        globals.meControllerAddr,
        "MeControllerComponent"
    )
    if not controller then
        error(controllerErr or "Runtime.new() — failed to create discovered ME controller")
    end
    local database, databaseErr = self._componentCache:getComponent(
        globals.databaseAddress,
        "DatabaseComponent",
        globals.databaseSize
    )
    if not database then
        error(databaseErr or "Runtime.new() — failed to create discovered database")
    end
    local redstone, redstoneErr = self._componentCache:getComponent(
        globals.redstoneAddress,
        "RedstoneComponent"
    )
    if not redstone then
        error(redstoneErr or "Runtime.new() — failed to create discovered redstone component")
    end
    local machines = {}
    for _, machineAddress in ipairs(globals.machineAddresses) do
        local machine, machineErr = self._componentCache:getComponent(
            machineAddress,
            "Machine"
        )
        if not machine then
            error(machineErr or "Runtime.new() — failed to create discovered machine component")
        end
        table.insert(machines, machine)
    end
    self._meController = controller
    self._database = database
    self._redstone = redstone
    self._database:clearAll()
    self._cloudClient = CloudClient.new(self._config) -- Instatiate cloud client with config.
    self._nodeSensor = NodeSensor.new(self._config, self._componentCache)
    self._jobPool = JobPool.new({
        nodeCache = self._nodeCache,
        globals = globals,
        machineStatus = function(address) return self._machineStatuses[address] end,
        onTopologyConflict = function(address, reason) self:_quarantineMachine(address, reason) end,
    })
    self._state = "INITIALIZING"
    self._clusterStatus = "INITIALIZING"
    self._topologyRevision = 0
    self._machineStatuses = {}
    for _, address in ipairs(globals.machineAddresses) do self._machineStatuses[address] = "UNMAPPED" end
    self._observation = globals
    self._lastTopologyCheckAt = 0
    self._topologyBackoffUntil = 0
    -- Compatibility for injected legacy collaborators; the real CloudClient always handshakes.
    if type(self._cloudClient.initialize) ~= "function" then
        self._state = "RUNNING"
        self._clusterStatus = "READY"
        for address in pairs(self._machineStatuses) do self._machineStatuses[address] = "READY" end
    end
    self._lastStatusAt = 0
    self._statusBackoffUntil = 0
    self._lastNoAssignmentDebug = nil
    self._running = true
    if self._config.useMockAssignment == true then
        self._nodeSensor:forcePendingRequest()
    end
    return self
end

function Runtime:state()
    return self._state
end

function Runtime:_quarantineMachine(address, reason)
    self._machineStatuses[address] = "NEEDS_REVIEW"
    self._topologyProblems = self._topologyProblems or {}
    self._topologyProblems[address] = reason or "topology_changed"
    if self._jobPool then self._jobPool:rejectPendingForMachine(address, "topology_changed") end
end

---True when cloud machine-mapping wiring differs from the cached node.
---Compares interface/transposer addresses and transposer side roles only.
local function mappingBindingsChanged(node, mapping)
    if not node or type(mapping) ~= "table" then
        return true
    end
    if node.interfaceAddress ~= mapping.interfaceAddress then
        return true
    end
    if node.transposerAddress ~= mapping.transposerAddress then
        return true
    end
    local incoming = type(mapping.transposerSides) == "table" and mapping.transposerSides or {}
    local current = type(node.transposerSides) == "table" and node.transposerSides or {}
    for role, side in pairs(incoming) do
        if current[role] ~= side then
            return true
        end
    end
    for role, side in pairs(current) do
        if incoming[role] ~= side then
            return true
        end
    end
    return false
end

function Runtime:_applyTopologyResponse(response)
    if type(response) ~= "table" then return false, "invalid initialization response" end
    self._topologyRevision = tonumber(response.topologyRevision) or self._topologyRevision
    self._clusterStatus = response.clusterStatus or (response.ready and "READY" or "INITIALIZING")
    local redstoneSides = response.cluster and response.cluster.redstoneSides or {}
    self._jobPool._globals.redstoneSides = redstoneSides
    if self._clusterStatus == "NEEDS_REVIEW" then
        for address in pairs(self._machineStatuses) do self:_quarantineMachine(address, "cluster topology_changed") end
        self._state = "INITIALIZING"
        return false
    end

    local globalChanged = false
    if self._observation and self._observation.globals then
        local globals = self._observation.globals
        local globalFingerprint = table.concat({ tostring(globals.meControllerAddress),
            tostring(globals.databaseAddress), tostring(globals.databaseSize),
            tostring(globals.redstoneAddress), tostring(redstoneSides.start), tostring(redstoneSides.stop) }, "|")
        globalChanged = self._appliedGlobalFingerprint ~= globalFingerprint
        self._appliedGlobalFingerprint = globalFingerprint
        self._jobPool._globals.databaseAddress = globals.databaseAddress
        self._jobPool._globals.databaseSize = globals.databaseSize
        self._jobPool._globals.redstoneAddress = globals.redstoneAddress
        self._config.meControllerAddr = globals.meControllerAddress
        self._config.databaseAddress = globals.databaseAddress
        self._config.databaseSize = globals.databaseSize
        self._config.redstoneAddress = globals.redstoneAddress
        self._meController = assert(self._componentCache:getComponent(globals.meControllerAddress, "MeControllerComponent"))
        local nextDatabase = assert(self._componentCache:getComponent(globals.databaseAddress, "DatabaseComponent", globals.databaseSize))
        if nextDatabase ~= self._database then nextDatabase:clearAll() end
        self._database = nextDatabase
        self._redstone = assert(self._componentCache:getComponent(globals.redstoneAddress, "RedstoneComponent"))
    end

    local seen = {}
    local allReady = true
    for _, mapping in ipairs(response.machines or {}) do
        local address = mapping.machineAddress
        if type(address) == "string" then
            seen[address] = true
            self._machineStatuses[address] = mapping.status or "UNMAPPED"
            if self._machineStatuses[address] == "READY" then
                local current = self._nodeCache:get(address)
                local needsRebuild = globalChanged or not current
                    or current.mappingRevision ~= mapping.mappingRevision
                    or mappingBindingsChanged(current, mapping)
                if needsRebuild then
                    local previousGeneration = current and current.cacheGeneration
                    local node, err = self._nodeCache:build(mapping, self._jobPool._globals)
                    if not node then self:_quarantineMachine(address, err) allReady = false end
                    if node and previousGeneration
                        and self._jobPool:activeGeneration(address) ~= previousGeneration then
                        self._nodeCache:retireGeneration(address, previousGeneration)
                    end
                else
                    local compatible, conflict = current:mergeRegistry(mapping)
                    if not compatible then self:_quarantineMachine(address, conflict) allReady = false end
                end
            else
                allReady = false
                self._jobPool:rejectPendingForMachine(address, "topology_changed")
            end
        end
    end
    for address in pairs(self._machineStatuses) do
        if not seen[address] and self._machineStatuses[address] == "READY" then
            self._machineStatuses[address] = "OFFLINE"
            self._jobPool:rejectPendingForMachine(address, "topology_changed")
        end
    end
    if response.ready == true and self._clusterStatus == "READY" and allReady then
        self._state = "RUNNING"
        return true
    end
    -- After initial startup, new unmapped machines do not stop already-ready machines.
    if self._state == "RUNNING" then return true end
    return false
end

function Runtime:_refreshTopology(force)
    if type(self._cloudClient.initialize) ~= "function" then return true end
    local now = os.time()
    if now < self._topologyBackoffUntil then return false end
    local interval = self._config.topologyCheckInterval or 30
    if not force and now - self._lastTopologyCheckAt < interval then return true end
    local observation, discoveryErr = HardwareDiscovery.discover(self._config, self._componentCache)
    if not observation then
        self._topologyBackoffUntil = now + (self._config.initializationRetryDelay or 5)
        print("[Runtime] topology discovery failed: " .. tostring(discoveryErr))
        return false
    end
    self._lastTopologyCheckAt = now
    observation.machineAddresses = observation.machineAddresses or {}
    observation.globals = observation.globals or {
        meControllerAddress = observation.meControllerAddr,
        databaseAddress = observation.databaseAddress,
        databaseSize = observation.databaseSize,
        redstoneAddress = observation.redstoneAddress,
        machineAddresses = observation.machineAddresses,
    }
    if observation.globals.machineAddresses == nil then
        observation.globals.machineAddresses = observation.machineAddresses
    end
    observation.components = observation.components or { machines = {}, interfaces = {}, transposers = {} }
    self._config.machineAddresses = observation.machineAddresses
    -- The POST is idempotent. Polling it even for an unchanged observation is how a
    -- running client learns that a user confirmed a repair in the cloud UI.
    self._observation = observation
    local response, err = self._cloudClient:initialize(observation)
    if not response then
        self._topologyBackoffUntil = now + (self._config.initializationRetryDelay or 5)
        print("[Runtime] initialization failed: " .. tostring(err))
        return false
    end
    self._topologyBackoffUntil = 0
    return self:_applyTopologyResponse(response)
end

---Store the current buffer description in consecutive database slots and track each write.
---Items use name/damage/count filters; fluids use AE2FC drop labels.
---@param buffer BufferSnapshot | nil
---@return boolean | nil stored
---@return string | nil error
function Runtime:_storeBufferInDatabase(buffer)
    buffer = type(buffer) == "table" and buffer or {}
    local items = type(buffer.items) == "table" and buffer.items or {}
    local fluids = type(buffer.fluids) == "table" and buffer.fluids or {}
    if self._database.clearTracked then self._database:clearTracked() end

    local function fail(message)
        if self._database.clearTracked then self._database:clearTracked() end
        return nil, message
    end

    local requiredSlots = #items + #fluids
    local databaseSize = self._database:getSize()
    if requiredSlots > databaseSize then
        return fail(string.format(
            "Runtime:_storeBufferInDatabase() — need %d slots but database has %d",
            requiredSlots,
            databaseSize
        ))
    end

    local databaseAddress = self._config.databaseAddress
    local slot = 1
    for _, item in ipairs(items) do
        if type(item) ~= "table" or type(item.name) ~= "string" or item.name == "" then
            return fail("Runtime:_storeBufferInDatabase() — item missing name")
        end
        local stored, storeErr = self._meController:store(
            { name = item.name, damage = tonumber(item.damage) or 0 },
            databaseAddress,
            slot,
            item.count or item.size
        )
        if not stored then
            return fail(
                "Runtime:_storeBufferInDatabase() — item store failed: " .. tostring(storeErr)
            )
        end
        self._database:trackSlot(slot)
        slot = slot + 1
    end

    for _, fluid in ipairs(fluids) do
        local label = type(fluid) == "table" and (fluid.label or fluid.name) or nil
        if type(label) ~= "string" or label == "" then
            return fail("Runtime:_storeBufferInDatabase() — fluid missing label")
        end
        local stored, storeErr = self._meController:store(
            { label = "drop of " .. label },
            databaseAddress,
            slot
        )
        if not stored then
            return fail(
                "Runtime:_storeBufferInDatabase() — fluid store failed: " .. tostring(storeErr)
            )
        end
        self._database:trackSlot(slot)
        slot = slot + 1
    end

    self._database:refreshIndex()
    return true
end

---Perform one cooperative runtime iteration.
---Polls sensors, advances jobs, retries terminal-result uplinks, may request assignments,
---and may report status. Cloud failures are logged; uncaught collaborator errors propagate.
---@return nil
function Runtime:tick()
    if not self._running then
        return
    end

    if self._state ~= "RUNNING" and type(self._cloudClient.initialize) ~= "function" then
        self._state = "RUNNING"
        self._clusterStatus = "READY"
    end

    if self._state == "RUNNING" then self:_refreshTopology(false) end

    local done, faulted = self._jobPool:tick()
    self:_handleFinishedJobs(done, false)
    self:_handleFinishedJobs(faulted, true)

    if self._state ~= "RUNNING" then
        self:_refreshTopology(true)
        if self._state ~= "RUNNING" then
            return
        end
    end

    self._nodeSensor:tick()

    if self._nodeSensor:hasPendingRequest()
        and not self._jobPool:hasPending()
        and not self._jobPool:hasUnreported() then
        self:_submitJobRequest()
    end

    self:_maybeReportStatus()
end

---Stop future runtime iterations.
---Existing jobs and resources are retained; subsequent `tick` calls return immediately.
---@return nil
function Runtime:shutdown()
    self._running = false
end

---Return the number of jobs currently executing.
---@return integer # Active run count from the job pool.
function Runtime:activeJobCount()
    return self._jobPool:activeCount()
end

---Report node status when its success interval and failure backoff permit.
---Success updates the last-report time and clears backoff. Failure schedules a retry
---and prints an error; no exception handling is applied around the cloud client.
---@return nil
function Runtime:_maybeReportStatus()
    local now = os.time()
    if now < self._statusBackoffUntil then
        return
    end

    local statusInterval = self._config.statusInterval or 30
    if now - self._lastStatusAt < statusInterval then
        return
    end

    local availability = self._nodeSensor:machineAvailability(self._jobPool)
    for _, machine in ipairs(availability) do
        machine.status = self._machineStatuses[machine.machineAddress] or "OFFLINE"
        if machine.status ~= "READY" then machine.available = false end
    end
    local ok, err = self._cloudClient:reportStatus({
        topologyRevision = self._topologyRevision,
        clusterStatus = self._clusterStatus,
        machines = availability,
        activeJobs = self._jobPool:snapshot(),
    })
    if ok then
        self._lastStatusAt = now
        self._statusBackoffUntil = 0
        return
    end

    local retryDelay = self._config.statusRetryDelay or 15
    self._statusBackoffUntil = now + retryDelay
    print("[Runtime] status uplink failed: " .. tostring(err))
end

---Stage current demand in the shared database, then submit it for scheduling.
---HTTP failures are logged and left pending for retry. Mock-mode failures still return
---`nil, err` from CloudClient, then call `markRequestSent()` so `jobRequestCooldown`
---throttles the every-tick print loop. A successful request clears the sensor's pending
---flag, logs deduplicated empty responses, and submits the single returned assignment.
---Multiple assignments are rejected because they cannot safely share one staging database.
---@return nil
function Runtime:_submitJobRequest()
    local request = {
        clusterId = self._config.clusterId,
        topologyRevision = self._topologyRevision,
        buffer = self._nodeSensor:bufferSnapshot() or { items = {}, fluids = {} },
        machines = self._nodeSensor:machineAvailability(self._jobPool),
        activeJobs = self._jobPool:snapshot(),
        timestamp = math.floor(os.time()),
    }
    local eligible = {}
    for _, machine in ipairs(request.machines) do
        machine.status = self._machineStatuses[machine.machineAddress] or "OFFLINE"
        if machine.status == "READY" then eligible[#eligible + 1] = machine end
    end
    request.machines = eligible

    local staged, stageErr = self:_storeBufferInDatabase(request.buffer)
    if not staged then
        print("[Runtime] database staging failed: " .. tostring(stageErr))
        return
    end

    local assignments, err, metadata = self._cloudClient:submitJobRequest(request)

    if not assignments then
        print("[Runtime] job request failed: " .. tostring(err))
        if self._config.useMockAssignment == true then
            self._nodeSensor:markRequestSent()
        end
        return
    end

    if metadata and metadata.reinitializeRequired then
        if self._database.clearTracked then self._database:clearTracked() end
        self._state = "INITIALIZING"
        return
    end

    if #assignments > 1 then
        if self._database.clearTracked then self._database:clearTracked() end
        print("[Runtime] job request rejected: shared staging database supports one assignment")
        return
    end

    self._nodeSensor:markRequestSent()

    if #assignments == 0 then
        if self._database.clearTracked then self._database:clearTracked() end
        self:_logNoAssignments(request)
        return
    end

    for _, assignment in ipairs(assignments) do
        self._jobPool:spawn(assignment)
    end
end

---Log a bounded diagnostic when a request receives no assignments.
---Suppresses repeats using a signature derived from the first eight item summaries and
---the machine count, then prints up to eight item and machine records.
---@param request table # Previously submitted request payload.
---@return nil
function Runtime:_logNoAssignments(request)
    local buffer = request.buffer or {}
    local items = buffer.items or {}
    local machines = request.machines or {}
    local parts = {}

    for index, item in ipairs(items) do
        if index > 8 then
            break
        end
        table.insert(parts, string.format(
            "%s x%s",
            tostring(item.name or "?"),
            tostring(item.size or item.count or 0)
        ))
    end

    local signature = table.concat(parts, "|") .. "#" .. tostring(#machines)
    if signature == self._lastNoAssignmentDebug then
        return
    end

    self._lastNoAssignmentDebug = signature
    print("[Runtime] job request returned no assignments")
    if #parts == 0 then
        print("[Runtime] buffer items: (none)")
    else
        print("[Runtime] buffer items: " .. table.concat(parts, ", "))
    end

    local machineParts = {}
    for index, machine in ipairs(machines) do
        if index > 8 then
            break
        end
        table.insert(machineParts, string.format(
            "%s avail=%s busy=%s problems=%s reason=%s",
            tostring(machine.machineAddress or "?"),
            tostring(machine.available),
            tostring(machine.busy),
            tostring(machine.problems or 0),
            tostring(machine.unavailableReason or "")
        ))
    end

    if #machineParts == 0 then
        print("[Runtime] machines: (none)")
    else
        print("[Runtime] machines: " .. table.concat(machineParts, ", "))
    end
end

---Upload completion results and remove each acknowledged run.
---Missing results are skipped. Failed uplinks are printed and retained for later retries.
---@param jobIds string[] # Terminal job identifiers to inspect.
---@param faulted boolean # Terminal category supplied by the caller; currently has no effect.
---@return nil
function Runtime:_handleFinishedJobs(jobIds, faulted)
    for _, jobId in ipairs(jobIds) do
        local result = self._jobPool:getResult(jobId)
        if result then
            local reported, err = self._cloudClient:reportCompletion(jobId, result)
            if not reported then
                print("[Runtime] completion uplink failed: " .. tostring(err))
            else
                self._jobPool:remove(jobId)
            end
        end
    end
end

return Runtime
