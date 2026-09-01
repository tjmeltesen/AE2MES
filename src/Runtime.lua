---@class Runtime

local Cache = require("Cache")
local CloudClient = require("CloudClient")
local NodeSensor = require("NodeSensor")
local JobPool = require("JobPool")

local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(config)
    local self = setmetatable({}, Runtime)
    self._config = config or {}
    self._cache = Cache.new()
    self._cloudClient = CloudClient.new(config)
    self._nodeSensor = NodeSensor.new(config, self._cache)
    self._jobPool = JobPool.new(self._cache)
    self._lastStatusAt = 0
    self._statusBackoffUntil = 0
    self._lastNoAssignmentDebug = nil
    self._running = true
    return self
end

function Runtime:tick()
    if not self._running then
        return
    end

    self._nodeSensor:tick()

    local done, faulted = self._jobPool:tick()
    self:_handleFinishedJobs(done, false)
    self:_handleFinishedJobs(faulted, true)

    if self._nodeSensor:hasPendingRequest() and self._jobPool:activeCount() == 0 then
        self:_submitJobRequest()
    end

    self:_maybeReportStatus()
end

function Runtime:shutdown()
    self._running = false
end

function Runtime:activeJobCount()
    return self._jobPool:activeCount()
end

function Runtime:_maybeReportStatus()
    local now = os.time()
    if now < self._statusBackoffUntil then
        return
    end

    local statusInterval = self._config.statusInterval or 30
    if now - self._lastStatusAt < statusInterval then
        return
    end

    local ok, err = self._cloudClient:reportStatus(self._jobPool:snapshot())
    if ok then
        self._lastStatusAt = now
        self._statusBackoffUntil = 0
        return
    end

    local retryDelay = self._config.statusRetryDelay or 15
    self._statusBackoffUntil = now + retryDelay
    print("[Runtime] status uplink failed: " .. tostring(err))
end

function Runtime:_submitJobRequest()
    local request = {
        nodeId = self._config.nodeId,
        buffer = self._nodeSensor:bufferSnapshot() or { items = {}, fluids = {} },
        machines = self._nodeSensor:machineAvailability(self._jobPool),
        activeJobs = self._jobPool:snapshot(),
        timestamp = math.floor(os.time()),
    }

    local assignments, err = self._cloudClient:submitJobRequest(request)
    self._nodeSensor:markRequestSent()

    if not assignments then
        print("[Runtime] job request failed: " .. tostring(err))
        return
    end

    if #assignments == 0 then
        self:_logNoAssignments(request)
        return
    end

    for _, assignment in ipairs(assignments) do
        self._jobPool:spawn(assignment)
    end
end

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

function Runtime:_handleFinishedJobs(jobIds, faulted)
    for _, jobId in ipairs(jobIds) do
        local run = self._jobPool:get(jobId)
        if run then
            local result = run.executor:result() or { ok = not faulted }
            self._cloudClient:reportCompletion(jobId, result)
            self._jobPool:remove(jobId)
        end
    end
end

return Runtime
