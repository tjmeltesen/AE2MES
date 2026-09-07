---@meta _
---@brief Coordinates sensing, cloud scheduling, job execution, and result reporting.
---@version 1.0.0
---
---@class RuntimeConfig
---@field nodeId string | nil
---@field cloudBaseUrl string | nil
---@field meControllerAddr string | nil
---@field bufferSourceAddress string | nil
---@field machineFilter string | nil
---@field statusInterval number | nil
---@field statusRetryDelay number | nil
---@field jobRequestCooldown number | nil
---@field useMockAssignment boolean | nil
---@field mockAssignmentPath string | nil
---
---@class Runtime
---@field _config RuntimeConfig # Runtime configuration retained by reference.
---@field _cache Cache # Shared component and observation cache.
---@field _cloudClient CloudClient # Cloud API client.
---@field _nodeSensor NodeSensor # Buffer and machine sensor.
---@field _jobPool JobPool # Assignment scheduler and executor.
---@field _lastStatusAt number # Time of the last successful status report.
---@field _statusBackoffUntil number # Earliest time for another report after failure.
---@field _lastNoAssignmentDebug string | nil # Signature used to suppress repeated empty-assignment logs.
---@field _running boolean # Whether `tick` should perform work.

local Cache = require("Cache")
local CloudClient = require("CloudClient")
local NodeSensor = require("NodeSensor")
local JobPool = require("JobPool")

local Runtime = {}
Runtime.__index = Runtime

---Create a runtime and all of its collaborating services.
---The configuration is shared with the cloud client and node sensor; module-loading
---or collaborator-construction errors are not caught.
---@param config RuntimeConfig | nil # Optional node, cloud, sensor, and interval settings.
---@return Runtime # Running coordinator with empty cache and job pool.
function Runtime.new(config)
    local self = setmetatable({}, Runtime)
    self._config = config or {}
    self._cache = Cache.new()
    self._cloudClient = CloudClient.new(config)
    self._nodeSensor = NodeSensor.new(config, self._cache)
    self._jobPool = JobPool.new()
    self._lastStatusAt = 0
    self._statusBackoffUntil = 0
    self._lastNoAssignmentDebug = nil
    self._running = true
    if self._config.useMockAssignment == true then
        self._nodeSensor:forcePendingRequest()
    end
    return self
end

---Perform one cooperative runtime iteration.
---Polls sensors, advances jobs, retries terminal-result uplinks, may request assignments,
---and may report status. Cloud failures are logged; uncaught collaborator errors propagate.
---@return nil
function Runtime:tick()
    if not self._running then
        return
    end

    self._nodeSensor:tick()

    local done, faulted = self._jobPool:tick()
    self:_handleFinishedJobs(done, false)
    self:_handleFinishedJobs(faulted, true)

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

---Submit current demand, machine availability, and active jobs for scheduling.
---HTTP failures are logged and left pending for retry. Mock-mode failures still return
---`nil, err` from CloudClient, then call `markRequestSent()` so `jobRequestCooldown`
---throttles the every-tick print loop. A successful request clears the sensor's pending
---flag, logs deduplicated empty responses, and submits each assignment; individual pool
---rejection results are currently ignored.
---@return nil
function Runtime:_submitJobRequest()
    local request = {
        nodeId = self._config.nodeId,
        buffer = self._nodeSensor:bufferSnapshot() or { items = {}, fluids = {} },
        machines = self._nodeSensor:machineAvailability(self._jobPool),
        activeJobs = self._jobPool:snapshot(),
        timestamp = math.floor(os.time()),
    }

    local assignments, err = self._cloudClient:submitJobRequest(request)

    if not assignments then
        print("[Runtime] job request failed: " .. tostring(err))
        if self._config.useMockAssignment == true then
            self._nodeSensor:markRequestSent()
        end
        return
    end

    self._nodeSensor:markRequestSent()

    if #assignments == 0 then
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
