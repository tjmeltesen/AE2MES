---@class JobPool

local HardwareContext = require("HardwareContext")
local Executor = require("Executor")

local JobPool = {}
JobPool.__index = JobPool

function JobPool.new(cache)
    local self = setmetatable({}, JobPool)
    self._cache = cache
    self._runs = {}
    return self
end

function JobPool:spawn(assignment)
    if not assignment then
        return false, "JobPool:spawn() — missing assignment"
    end

    local jobId = assignment:id()
    local machineAddress = assignment:machineAddress()

    if self._runs[jobId] then
        return false, "JobPool:spawn() — job already active: " .. jobId
    end

    if self:isMachineBusy(machineAddress) then
        return false, "JobPool:spawn() — machine busy: " .. tostring(machineAddress)
    end

    local hardwareContext, hwErr = HardwareContext.fromRegistry(assignment:registry(), self._cache)
    if not hardwareContext then
        return false, hwErr
    end

    local executor = Executor.new(self._cache)
    local ok, beginErr = executor:begin(
        hardwareContext,
        assignment:sequenceFlow(),
        jobId,
        machineAddress
    )

    if not ok then
        return false, beginErr
    end

    self._runs[jobId] = {
        jobId = jobId,
        machineAddress = machineAddress,
        executor = executor,
        hardwareContext = hardwareContext,
        assignment = assignment,
        startedAt = os.time(),
    }

    return true
end

function JobPool:tick()
    local done = {}
    local faulted = {}

    for jobId, run in pairs(self._runs) do
        run.executor:tick()

        if run.executor:phase() == Executor.PHASE.DONE then
            table.insert(done, jobId)
        elseif run.executor:phase() == Executor.PHASE.FAULTED then
            table.insert(faulted, jobId)
        end
    end

    return done, faulted
end

function JobPool:remove(jobId)
    self._runs[jobId] = nil
end

function JobPool:get(jobId)
    return self._runs[jobId]
end

function JobPool:activeCount()
    local count = 0
    for _ in pairs(self._runs) do
        count = count + 1
    end
    return count
end

function JobPool:busyMachines()
    local machines = {}

    for _, run in pairs(self._runs) do
        table.insert(machines, run.machineAddress)
    end

    return machines
end

function JobPool:isMachineBusy(machineAddress)
    for _, run in pairs(self._runs) do
        if run.machineAddress == machineAddress then
            return true
        end
    end
    return false
end

function JobPool:snapshot()
    local snapshot = {}
    local index = 0

    for jobId, run in pairs(self._runs) do
        index = index + 1
        snapshot[index] = {
            jobId = tostring(jobId),
            machineAddress = tostring(run.machineAddress),
            phase = tostring(run.executor:phase() or "IDLE"),
            stepIndex = math.floor(run.executor:stepIndex() or 0),
            startedAt = math.floor(run.startedAt or os.time()),
        }
    end

    return snapshot
end

return JobPool
