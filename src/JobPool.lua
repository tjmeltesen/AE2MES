---@meta _
---@brief Parses, queues, advances, and reports assignment runs on a shared runtime thread.
---@version 1.0.0
---
---@class JobResult
---@field jobId string
---@field machineAddress string
---@field success boolean
---@field durationSeconds number
---@field itemsProcessed table[]
---@field error string | nil
---
---@class JobRun
---@field jobId string
---@field machineAddress string
---@field assignment Assignment
---@field node NodeComponent | nil
---@field stepIndex integer
---@field state string # `"ACTIVE"`, `"DONE"`, or `"FAULTED"`.
---@field startedAt number
---@field completedAt number | nil
---@field stepStartedAt number | nil
---@field waitTicks number | nil
---@field error any
---@field result JobResult | nil
---
---@class JobSnapshot
---@field jobId string
---@field machineAddress string
---@field phase string
---@field stepIndex integer
---@field startedAt integer
---
---@class JobPool
---@field _runs table<string, JobRun> # Runs retained until explicitly removed.
---@field _pending Assignment | nil # Single assignment waiting for its selected machine.
---@field _clock fun(): number # Time source used for run timing and process timeouts.
---@field _nodeCache NodeCache | nil # Topology-owned READY nodes reused by assignments.
---@field _componentCache ComponentCache | nil # Harness-only wrapper store for configureFromRegistry.
---@field _globals table | nil # Locally discovered broker-global hardware addresses.

local Assignment = require("Assignment")
local NodeComponent = require("NodeComponent")

local JobPool = {}
JobPool.__index = JobPool

local function monotonicClock()
    local ok, computer = pcall(require, "computer")
    if ok and computer and type(computer.uptime) == "function" then return computer.uptime() end
    return os.clock()
end

---Shallow-copy each item record in an array.
---Nested values remain shared, non-array keys are omitted, and malformed item entries may raise an error.
---@param items table[] | nil # Item array to copy; nil is treated as empty.
---@return table[] # New item array containing new top-level item tables.
local function copyItems(items)
    local copy = {}
    for index, item in ipairs(items or {}) do
        local itemCopy = {}
        for key, value in pairs(item) do
            itemCopy[key] = value
        end
        copy[index] = itemCopy
    end
    return copy
end

---Create an empty job pool using `os.time` as its clock.
---@param options? { nodeCache?: NodeCache, componentCache?: ComponentCache, globals?: table }
---@return JobPool # New pool with no active, terminal, or pending assignments.
function JobPool.new(options)
    options = type(options) == "table" and options or {}
    local self = setmetatable({}, JobPool)
    self._runs = {}
    self._pending = nil
    self._clock = monotonicClock
    self._nodeCache = options.nodeCache
    self._componentCache = options.componentCache
    self._globals = options.globals
    self._machineStatus = options.machineStatus
    self._onTopologyConflict = options.onTopologyConflict
    return self
end

---Normalize JSON, raw-table, or Assignment-like input into an Assignment object.
---Assignment accessor errors propagate; validation failures are returned with JobPool context.
---@param input any # JSON text, raw assignment data, or object exposing assignment methods.
---@return Assignment | nil assignment # Valid assignment with string job and machine identifiers.
---@return string | nil error # Parse or required-field validation error.
function JobPool:parseAssignment(input)
    local assignment
    local err

    if type(input) == "string" then
        assignment, err = Assignment.fromJSON(input)
    elseif type(input) == "table" and type(input.id) == "function" then
        assignment = input
    elseif type(input) == "table" then
        assignment, err = Assignment.fromTable(input)
    else
        err = "expected JSON string or assignment table"
    end

    if not assignment then
        return nil, "JobPool:parseAssignment() — " .. tostring(err)
    end
    if type(assignment.id) ~= "function" or type(assignment:id()) ~= "string" then
        return nil, "JobPool:parseAssignment() — assignment missing jobId"
    end
    if type(assignment.machineAddress) ~= "function"
        or type(assignment:machineAddress()) ~= "string" then
        return nil, "JobPool:parseAssignment() — assignment missing machineAddress"
    end

    return assignment
end

---Reuse the topology-owned NodeCache node for an assignment.
---Assignments never invent wiring when a NodeCache is present: missing or conflicting
---mappings fail with topology_changed. Without a NodeCache (manual/smoke harnesses only),
---falls back to configureFromRegistry.
---@param assignment Assignment # Parsed assignment used to select the cached node.
---@return NodeComponent | nil node # Cached or harness-built node, or nil on failure.
---@return string | nil error # Missing node, merge conflict, or harness wiring error.
function JobPool:createNode(assignment)
    local machineAddress = assignment:machineAddress()
    if self._nodeCache then
        local cached = self._nodeCache:get(machineAddress)
        if not cached then
            return nil, "topology_changed: no cached node for " .. tostring(machineAddress)
        end
        local ok, mergeErr = cached:mergeRegistry(assignment:registry())
        if not ok then
            if self._onTopologyConflict then self._onTopologyConflict(machineAddress, mergeErr) end
            return nil, mergeErr
        end
        return cached
    end
    local node = NodeComponent:new()
    if not node then
        return nil, "JobPool:createNode() — failed to create NodeComponent"
    end

    local ok, err = node:configureFromRegistry(assignment:registry(), self._globals, self._componentCache)
    if not ok then
        return nil, err or "JobPool:createNode() — failed to configure assignment registry"
    end

    return node
end

---Build an active run record and its initialized node.
---The run start time comes from the pool's replaceable clock.
---@param assignment Assignment # Parsed assignment to run.
---@return JobRun | nil run # New, not-yet-stored run record.
---@return string | nil error # Node creation or assignment wiring error.
function JobPool:createRun(assignment)
    local node, err = self:createNode(assignment)
    if not node then
        return nil, err
    end

    return {
        jobId = assignment:id(),
        machineAddress = assignment:machineAddress(),
        assignment = assignment,
        node = node,
        stepIndex = 1,
        state = "ACTIVE",
        startedAt = self._clock(),
    }
end

---Check whether a machine address currently has an active run.
---@param machineAddress string # Machine address to search for.
---@return boolean # True when an `"ACTIVE"` run uses the address.
function JobPool:isMachineActive(machineAddress)
    for _, run in pairs(self._runs) do
        if run.machineAddress == machineAddress and run.state == "ACTIVE" then
            return true
        end
    end
    return false
end

---Check whether the pool's single pending slot is occupied.
---@return boolean # True when an assignment is waiting to start.
function JobPool:hasPending()
    return self._pending ~= nil
end

---Check whether any terminal run still awaits removal after cloud reporting.
---@return boolean # True when a run is `"DONE"` or `"FAULTED"`.
function JobPool:hasUnreported()
    for _, run in pairs(self._runs) do
        if run.state == "DONE" or run.state == "FAULTED" then
            return true
        end
    end
    return false
end

---Start a parsed assignment and store its run by jobId.
---If node creation fails, stores a faulted run and completion result for later reporting.
---@param assignment Assignment # Valid assignment to start.
---@return boolean ok # True when an active run was created.
---@return string | nil error # Node creation or assignment wiring error.
function JobPool:startAssignment(assignment)
    local run, err = self:createRun(assignment)
    if not run then
        run = {
            jobId = assignment:id(),
            machineAddress = assignment:machineAddress(),
            assignment = assignment,
            stepIndex = 1,
            state = "ACTIVE",
            startedAt = self._clock(),
        }
        self._runs[run.jobId] = run
        self:finishRun(run, false, err)
        return false, err
    end

    self._runs[run.jobId] = run
    return true
end

---Parse and submit an assignment to the pool.
---Rejects duplicate jobIds and a full pending slot. If the selected machine is
---active, stores the assignment in the one-element pending slot; otherwise starts it now.
---@param input any # JSON text, raw assignment data, or Assignment-like object.
---@return boolean accepted # True when started or queued; false when rejected or startup faults.
---@return string | nil error # Parse, duplicate, capacity, or node creation error.
function JobPool:submit(input)
    local assignment, err = self:parseAssignment(input)
    if not assignment then
        return false, err
    end

    local jobId = assignment:id()
    if self._machineStatus and self._machineStatus(assignment:machineAddress()) ~= "READY" then
        return false, "topology_changed: machine is not READY"
    end
    if self._runs[jobId] then
        return false, "JobPool:submit() — job already active: " .. jobId
    end
    if self._pending then
        return false, "JobPool:submit() — pending assignment slot is full"
    end
    if self:isMachineActive(assignment:machineAddress()) then
        self._pending = assignment
        return true
    end

    return self:startAssignment(assignment)
end

function JobPool:activeGeneration(machineAddress)
    for _, run in pairs(self._runs) do
        if run.machineAddress == machineAddress and run.state == "ACTIVE" and run.node then
            return run.node.cacheGeneration
        end
    end
    return nil
end

---Fault a queued, not-yet-started assignment when its machine is quarantined.
function JobPool:rejectPendingForMachine(machineAddress, reason)
    local rejected = false
    if self._pending and self._pending:machineAddress() == machineAddress then
        local assignment = self._pending
        self._pending = nil
        local run = {
            jobId = assignment:id(), machineAddress = machineAddress, assignment = assignment,
            stepIndex = 1, state = "ACTIVE", startedAt = self._clock(),
        }
        self._runs[run.jobId] = run
        self:finishRun(run, false, reason or "topology_changed")
        rejected = true
    end
    for _, run in pairs(self._runs) do
        if run.machineAddress == machineAddress and run.state == "ACTIVE" and not run.executionStarted then
            self:finishRun(run, false, reason or "topology_changed")
            rejected = true
        end
    end
    return rejected
end

---Submit an assignment using the pool's compatibility alias.
---@param input any # Input accepted by `submit`.
---@return boolean accepted # True when started or queued.
---@return string | nil error # Error returned by `submit`.
function JobPool:spawn(input)
    return self:submit(input)
end

---Start the pending assignment when its machine is free.
---Returns false without an error while the machine remains active. A startup failure
---clears the pending slot but leaves the generated faulted run stored for reporting.
---@return boolean started # True when no assignment is pending or the pending run starts.
---@return string | nil error # Node creation or assignment wiring error.
function JobPool:startPending()
    if not self._pending then
        return true
    end
    if self:isMachineActive(self._pending:machineAddress()) then
        return false
    end

    local assignment = self._pending
    local ok, err = self:startAssignment(assignment)
    if not ok then
        self._pending = nil
        return false, err
    end

    self._pending = nil
    return true
end

---Mark a run terminal and build its cloud completion result.
---Mutates and timestamps the supplied run. Truthy `ok` selects `"DONE"` and copies
---requested items, while only literal true sets `result.success`; falsey values fault
---the run. Malformed assignment flow data may raise an error.
---@param run JobRun # Stored run to finish.
---@param ok any # Truthy marks the run done; only literal true sets `result.success` true.
---@param err any # Optional failure detail converted to text for a faulted result.
---@return nil
function JobPool:finishRun(run, ok, err)
    run.state = ok and "DONE" or "FAULTED"
    run.error = err
    run.completedAt = self._clock()
    run.result = {
        jobId = run.jobId,
        machineAddress = run.machineAddress,
        success = ok == true,
        durationSeconds = math.max(0, run.completedAt - run.startedAt),
        processingDurationMs = run.processingStartedAt
            and math.floor(math.max(0, run.completedAt - run.processingStartedAt) * 1000 + 0.5)
            or 0,
        itemsProcessed = ok and copyItems(run.assignment:sequenceFlow().items) or {},
    }
    run.result.ok = run.result.success
    run.result.durationMs = run.result.processingDurationMs
    if not ok then
        run.result.error = tostring(err or "job failed")
    end
end

---Advance one active run by at most one assignment step.
---Transfer and machine-completion calls are protected with `pcall`; failures fault the run.
---Process steps poll without sleeping, while wait steps count pool ticks.
---@param run JobRun # Active run record to mutate.
---@return nil
function JobPool:tickRun(run)
    run.executionStarted = true
    local flow = run.assignment:sequenceFlow()
    local step = flow:stepAt(run.stepIndex)
    if not step then
        self:finishRun(run, true)
        return
    end

    local method = step.method or step.type
    local params = step.params or {}

    if method == "transferToMachine" or method == "transfer" then
        local callOk, transferred = pcall(
            run.node.transferToMachine,
            run.node,
            params.fromSide,
            params.toSide,
            params
        )
        if not callOk or transferred ~= true then
            self:finishRun(run, false, callOk and "transfer failed" or tostring(transferred))
            return
        end
        -- transferToMachine returns only after the machine has confirmed active.
        run.processingStartedAt = self._clock()
        run.stepIndex = run.stepIndex + 1
        run.stepStartedAt = nil
    elseif method == "waitForProcess" or method == "process" then
        run.stepStartedAt = run.stepStartedAt or self._clock()
        local callOk, done = pcall(run.node.isDone, run.node)
        if not callOk then
            self:finishRun(run, false, tostring(done))
            return
        end
        if done then
            run.stepIndex = run.stepIndex + 1
            run.stepStartedAt = nil
        else
            local timeout = tonumber(params.timeout) or 600
            if timeout >= 0 and self._clock() - run.stepStartedAt >= timeout then
                self:finishRun(run, false, "process timeout")
            end
            return
        end
    elseif method == "wait" then
        local ticks = math.max(1, tonumber(params.ticks) or 1)
        run.waitTicks = (run.waitTicks or 0) + 1
        if run.waitTicks < ticks then
            return
        end
        run.waitTicks = nil
        run.stepIndex = run.stepIndex + 1
    else
        self:finishRun(run, false, "unsupported assignment step: " .. tostring(method))
        return
    end

    if run.stepIndex > flow:stepCount() then
        self:finishRun(run, true)
    end
end

---Advance all active runs once and attempt to start the pending assignment.
---Terminal jobIds are returned on every tick until their runs are removed. A pending
---run started or faulted at the end of this call appears in a later tick's result lists.
---@return string[] done # JobIds currently in the `"DONE"` state.
---@return string[] faulted # JobIds currently in the `"FAULTED"` state.
function JobPool:tick()
    local done = {}
    local faulted = {}

    for jobId, run in pairs(self._runs) do
        if run.state == "ACTIVE" then
            self:tickRun(run)
        end

        if run.state == "DONE" then
            done[#done + 1] = jobId
        elseif run.state == "FAULTED" then
            faulted[#faulted + 1] = jobId
        end
    end

    self:startPending()
    return done, faulted
end

---Remove a run without changing or reporting it.
---@param jobId string # Stored job identifier.
---@return nil
function JobPool:remove(jobId)
    local run = self._runs[jobId]
    self._runs[jobId] = nil
    if run and run.node and self._nodeCache then
        self._nodeCache:retireGeneration(run.machineAddress, run.node.cacheGeneration)
    end
end

---Look up a stored run.
---@param jobId string # Job identifier to find.
---@return JobRun | nil # Active or terminal run, or nil when absent.
function JobPool:get(jobId)
    return self._runs[jobId]
end

---Return a stored run's completion result.
---@param jobId string # Job identifier to find.
---@return JobResult | nil # Result for a terminal run, or nil when absent or still active.
function JobPool:getResult(jobId)
    local run = self._runs[jobId]
    return run and run.result or nil
end

---Count runs currently in the active state.
---@return integer # Number of `"ACTIVE"` runs.
function JobPool:activeCount()
    local count = 0
    for _, run in pairs(self._runs) do
        if run.state == "ACTIVE" then
            count = count + 1
        end
    end
    return count
end

---Collect machine addresses used by active runs.
---Iteration order follows Lua table traversal and is not stable.
---@return string[] # Machine address for each active run.
function JobPool:busyMachines()
    local machines = {}

    for _, run in pairs(self._runs) do
        if run.state == "ACTIVE" then
            table.insert(machines, run.machineAddress)
        end
    end

    return machines
end

---Check whether a machine has an active run.
---@param machineAddress string # Machine address to search for.
---@return boolean # Result of `isMachineActive`.
function JobPool:isMachineBusy(machineAddress)
    return self:isMachineActive(machineAddress)
end

---Build a serializable status snapshot for every stored run, including terminal runs.
---The returned array order is unspecified; identifiers and phases are stringified,
---and missing start times fall back to the current time.
---@return JobSnapshot[] # Newly allocated status records.
function JobPool:snapshot()
    local snapshot = {}
    local index = 0

    for jobId, run in pairs(self._runs) do
        index = index + 1
        snapshot[index] = {
            jobId = tostring(jobId),
            machineAddress = tostring(run.machineAddress),
            phase = tostring(run.state),
            stepIndex = math.floor(run.stepIndex or 0),
            startedAt = math.floor(run.startedAt or os.time()),
        }
    end

    return snapshot
end

return JobPool
