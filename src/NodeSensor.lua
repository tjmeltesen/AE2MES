---@class NodeSensor

local component = require("component")

local NodeSensor = {}
NodeSensor.__index = NodeSensor

function NodeSensor.new(config, cache)
    local self = setmetatable({}, NodeSensor)
    self._config = config or {}
    self._cache = cache
    self._bufferSnapshot = nil
    self._machineAvailability = {}
    self._pendingRequest = false
    self._lastRequestAt = 0
    return self
end

function NodeSensor:tick()
    self:_watchBuffer()
end

function NodeSensor:bufferSnapshot()
    return self._bufferSnapshot
end

function NodeSensor:machineAvailability(jobPool)
    if #self._machineAvailability == 0 then
        self:scanMachines()
    end

    local availability = {}
    local busy = {}

    if jobPool and jobPool.busyMachines then
        for _, address in ipairs(jobPool:busyMachines()) do
            busy[address] = true
        end
    end

    for _, entry in ipairs(self._machineAvailability) do
        local copy = {}
        for key, value in pairs(entry) do
            copy[key] = value
        end
        copy.busy = busy[entry.machineAddress] == true
        table.insert(availability, copy)
    end

    return availability
end

function NodeSensor:hasPendingRequest()
    if not self._pendingRequest then
        return false
    end

    local cooldown = self._config.jobRequestCooldown or 15
    if os.time() - self._lastRequestAt < cooldown then
        return false
    end

    return true
end

function NodeSensor:markRequestSent()
    self._pendingRequest = false
    self._lastRequestAt = os.time()
end

function NodeSensor:scanMachines()
    self._machineAvailability = {}
    local addresses = self:_discoverMachineAddresses()

    for _, address in ipairs(addresses) do
        local entry = self:_pollMachine(address)
        if entry then
            table.insert(self._machineAvailability, entry)
        end
    end

    self._cache:setLastMachineScan(self._machineAvailability)
    return self._machineAvailability
end

function NodeSensor:_discoverMachineAddresses()
    local addresses = {}
    local filter = self._config.machineFilter or "gt_machine"

    for address in component.list(filter) do
        table.insert(addresses, address)
    end

    return addresses
end

function NodeSensor:_pollMachine(address)
    local machine = self._cache:getComponent(address, "Machine")
    if not machine then
        return nil
    end

    local proxy = machine:getProxy()
    if not proxy then
        return nil
    end

    local state = machine:pollAvailability()

    return {
        machineAddress = address,
        available = state.available,
        active = state.active,
        hasWork = state.hasWork,
        workAllowed = state.workAllowed,
        problems = state.problems or 0,
        progressCurrent = state.progressCurrent,
        progressMax = state.progressMax,
        unavailableReason = state.unavailableReason or "",
        busy = false,
    }
end

function NodeSensor:_watchBuffer()
    local address = self._config.meControllerAddr or self._config.bufferSourceAddress
    if not address then
        return
    end

    local controller = self._cache:getComponent(address, "MeControllerComponent")
    if not controller then
        return
    end

    local snapshot, err = controller:getBufferSnapshot()
    if not snapshot then
        return
    end

    local previous = self._cache:getLastBuffer()
    if not previous or not self:_snapshotsEqual(previous, snapshot) then
        self._bufferSnapshot = snapshot
        self._cache:setLastBuffer(snapshot)
        self._pendingRequest = true
        self:scanMachines()
    end
end

function NodeSensor:_snapshotSignature(snapshot)
    local parts = {}

    for _, item in ipairs(snapshot.items or {}) do
        table.insert(parts, string.format(
            "i:%s:%s",
            tostring(item.name or ""),
            tostring(item.size or item.count or 0)
        ))
    end

    for _, fluid in ipairs(snapshot.fluids or {}) do
        table.insert(parts, string.format(
            "f:%s:%s",
            tostring(fluid.name or ""),
            tostring(fluid.amount or 0)
        ))
    end

    table.sort(parts)
    return table.concat(parts, "|")
end

function NodeSensor:_snapshotsEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end

    return self:_snapshotSignature(a) == self:_snapshotSignature(b)
end

return NodeSensor
