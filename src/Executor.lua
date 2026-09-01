---@class Executor
--- Basic sequence executor for in-game testing.
--- Steps may complete in one tick or return pending for multi-tick work.

local Executor = {}
Executor.__index = Executor

Executor.PHASE = {
    IDLE = "IDLE",
    RUNNING = "RUNNING",
    DONE = "DONE",
    FAULTED = "FAULTED",
}

function Executor.new(cache, options)
    local self = setmetatable({}, Executor)
    self._cache = cache
    self._verbose = not options or options.verbose ~= false
    self._phase = Executor.PHASE.IDLE
    self._stepIndex = 0
    self._stepState = {}
    self._hardwareContext = nil
    self._sequenceFlow = nil
    self._jobId = nil
    self._machineAddress = nil
    self._result = nil
    return self
end

function Executor:begin(hardwareContext, sequenceFlow, jobId, machineAddress)
    if not hardwareContext or not sequenceFlow then
        return false, "Executor:begin() — missing hardware context or sequence flow"
    end

    self._hardwareContext = hardwareContext
    self._sequenceFlow = sequenceFlow
    self._jobId = jobId
    self._machineAddress = machineAddress
    self._stepIndex = 1
    self._stepState = {}
    self._phase = Executor.PHASE.RUNNING
    self._result = nil

    self:_log(string.format(
        "begin job %s on %s (%d steps)",
        tostring(jobId),
        tostring(machineAddress),
        sequenceFlow:stepCount()
    ))

    return true
end

function Executor:tick()
    if self._phase ~= Executor.PHASE.RUNNING then
        return
    end

    local step = self._sequenceFlow:stepAt(self._stepIndex)
    if not step then
        self._phase = Executor.PHASE.DONE
        self._result = { ok = true, stepsCompleted = self._stepIndex - 1 }
        self:_log("job complete")
        return
    end

    if not self._stepState.started then
        self:_log(string.format(
            "step %d/%d type=%s target=%s",
            self._stepIndex,
            self._sequenceFlow:stepCount(),
            tostring(step.type),
            tostring(step.target)
        ))
        self._stepState.started = true
    end

    local status, err = self:_runStep(step, self._hardwareContext)

    if status == "pending" then
        return
    end

    if status ~= "done" then
        self._phase = Executor.PHASE.FAULTED
        self._result = {
            ok = false,
            faultReason = err or "step failed",
            failedStep = self._stepIndex,
            stepType = step.type,
        }
        self:_log("fault: " .. tostring(self._result.faultReason))
        return
    end

    self:_log(string.format("step %d done", self._stepIndex))
    self._stepState = {}
    self._stepIndex = self._stepIndex + 1
end

function Executor:phase()
    return self._phase
end

function Executor:stepIndex()
    return self._stepIndex
end

function Executor:isActive()
    return self._phase == Executor.PHASE.RUNNING
end

function Executor:isDone()
    return self._phase == Executor.PHASE.DONE or self._phase == Executor.PHASE.FAULTED
end

function Executor:result()
    return self._result
end

function Executor:jobId()
    return self._jobId
end

function Executor:machineAddress()
    return self._machineAddress
end

function Executor:abort(reason)
    self._phase = Executor.PHASE.FAULTED
    self._result = { ok = false, faultReason = reason or "aborted" }
    self:_log("aborted: " .. tostring(reason))
end

function Executor:_log(message)
    if self._verbose then
        print(string.format(
            "[Executor %s] %s",
            tostring(self._jobId or "?"),
            message
        ))
    end
end

function Executor:_runStep(step, hardwareContext)
    if step.type == "wait" then
        return self:_stepWait(step, hardwareContext)
    elseif step.type == "transfer" then
        return self:_stepTransfer(step, hardwareContext)
    elseif step.type == "configure" then
        return self:_stepConfigure(step, hardwareContext)
    elseif step.type == "process" then
        return self:_stepProcess(step, hardwareContext)
    elseif step.type == "clear" then
        return self:_stepClear(step, hardwareContext)
    elseif step.type == "redstone" then
        return self:_stepRedstone(step, hardwareContext)
    end

    return nil, "unknown step type: " .. tostring(step.type)
end

function Executor:_stepWait(step, hardwareContext)
    local params = step.params or {}

    if params.duration then
        local clock = os.clock or os.time
        if not self._stepState.untilTime then
            self._stepState.untilTime = clock() + params.duration
        end

        if clock() < self._stepState.untilTime then
            if os.sleep then os.sleep(0) end
            return "pending"
        end

        return "done"
    end

    local ticks = params.ticks or 1
    self._stepState.remaining = (self._stepState.remaining or ticks) - 1

    if self._stepState.remaining > 0 then
        if os.sleep then os.sleep(0) end
        return "pending"
    end

    return "done"
end

function Executor:_stepTransfer(step, hardwareContext)
    local transposer = hardwareContext:transposer()
    if not transposer then
        return nil, "transposer unavailable"
    end

    local params = step.params or {}
    local fromSide = params.fromSide or hardwareContext:side("transposerStore")
    local toSide = params.toSide or hardwareContext:side("transposerStock")

    if not fromSide or not toSide then
        return nil, "transfer missing fromSide/toSide in params or registry sides"
    end

    local moved = transposer:transferItem(
        fromSide,
        toSide,
        params.count,
        params.fromSlot,
        params.toSlot
    )

    if moved == nil then
        return nil, "transferItem call failed"
    end

    if moved == 0 and not params.allowZero then
        return nil, "transfer moved 0 items"
    end

    if os.sleep then os.sleep(0) end
    return "done"
end

function Executor:_stepConfigure(step, hardwareContext)
    local params = step.params or {}
    local target = step.target or ""

    if target == "storeInterfaceAddress" or target == "stockInterfaceAddress" then
        local which = target == "stockInterfaceAddress" and "stock" or "store"
        local iface = hardwareContext:interface(which)
        if not iface then
            return nil, "interface unavailable: " .. target
        end

        if params.clear then
            iface:clearConfiguration(params.slot or 1)
        else
            iface:setConfiguration(
                params.slot or 1,
                params.dbAddress,
                params.dbSlot,
                params.count
            )
        end

        if os.sleep then os.sleep(0) end
        return "done"
    end

    return nil, "configure unsupported for target: " .. tostring(target)
end

function Executor:_stepProcess(step, hardwareContext)
    local machine = hardwareContext:machine()
    if not machine then
        return nil, "machine unavailable"
    end

    local params = step.params or {}
    local timeout = params.timeout or 600
    self._stepState.elapsed = (self._stepState.elapsed or 0) + 1

    local active = machine:isMachineActive()
    if active == nil then
        return nil, "machine poll failed"
    end

    if active or params.waitForActive then
        if self._stepState.elapsed >= timeout then
            return nil, "process timeout after " .. timeout .. " ticks"
        end

        if os.sleep then os.sleep(0) end
        return "pending"
    end

    return "done"
end

function Executor:_stepClear(step, hardwareContext)
    local params = step.params or {}
    local target = step.target or "databaseAddress"

    if target == "databaseAddress" then
        local database = hardwareContext:database()
        if not database then
            return nil, "database unavailable"
        end

        database:clear(params.slot or 1)
        if os.sleep then os.sleep(0) end
        return "done"
    end

    if target == "storeInterfaceAddress" or target == "stockInterfaceAddress" then
        local which = target == "stockInterfaceAddress" and "stock" or "store"
        local iface = hardwareContext:interface(which)
        if not iface then
            return nil, "interface unavailable: " .. target
        end

        iface:clearConfiguration(params.slot or 1)
        if os.sleep then os.sleep(0) end
        return "done"
    end

    return nil, "clear unsupported for target: " .. tostring(target)
end

function Executor:_stepRedstone(step, hardwareContext)
    local redstone = hardwareContext:redstone()
    if not redstone then
        return nil, "redstone unavailable"
    end

    local params = step.params or {}
    local side = params.side or 0

    if params.pulse then
        local ok, err = redstone:pulse(side, params.duration or 0.5)
        if not ok then
            return nil, err or "redstone pulse failed"
        end
    else
        local ok, err = redstone:setOutput(side, params.value or 15)
        if not ok then
            return nil, err or "redstone setOutput failed"
        end
    end

    return "done"
end

return Executor
