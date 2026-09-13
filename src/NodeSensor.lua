---@meta _
---@brief Watches the ME buffer and polls GT machines for cloud scheduling state.
---@version 1.0.0
---
---@class BufferSnapshot
---@field items table[] | nil # Item stacks reported by the ME controller.
---@field fluids table[] | nil # Fluid stacks reported by the ME controller.
---
---@class MachineAvailabilityEntry
---@field machineAddress string
---@field available boolean
---@field active boolean
---@field hasWork boolean
---@field workAllowed boolean
---@field problems number
---@field progressCurrent number | nil
---@field progressMax number | nil
---@field unavailableReason string
---@field busy boolean
---
---@class NodeSensor
---@field _config table # Sensor intervals, addresses, and component filter configuration.
---@field _cache Cache # Shared component cache used for ME and machine wrappers.
---@field _bufferSnapshot BufferSnapshot | nil # Last changed buffer snapshot observed by this instance.
---@field _machineAvailability MachineAvailabilityEntry[] # Most recent hardware scan.
---@field _pendingRequest boolean # Whether a changed buffer is awaiting a cloud request.
---@field _lastRequestAt number # `os.time()` value recorded after the last accepted request.

local NodeSensor = {}
NodeSensor.__index = NodeSensor

---Create a node sensor backed by a shared component cache.
---The supplied configuration and cache are retained by reference and are not validated.
---@param config table | nil # Optional sensor configuration.
---@param cache Cache # Cache used for hardware wrappers.
---@return NodeSensor # New sensor with no observations and no pending request.
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

---Poll the configured ME buffer once.
---A detected content-signature change updates caches, marks a request pending, and scans machines.
---@return nil
function NodeSensor:tick()
    self:_watchBuffer()
end

---Return the most recently changed buffer snapshot.
---@return BufferSnapshot | nil # Snapshot retained from the controller, or nil before the first change.
function NodeSensor:bufferSnapshot()
    return self._bufferSnapshot
end

---Return a shallow copy of the latest machine scan with current job-pool busy flags.
---If no machine entries are cached, performs a scan first. Nested entry values remain shared.
---@param jobPool JobPool | nil # Optional pool used to identify machine addresses with active runs.
---@return MachineAvailabilityEntry[] # Newly allocated availability array and entry tables.
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

---Check whether a changed buffer may trigger a cloud job request.
---A pending request remains suppressed until jobRequestCooldown seconds have elapsed
---since the last successful submission.
---@return boolean # True only when a request is pending and its cooldown has expired.
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

---Acknowledge that the pending job request was submitted.
---Clears the pending flag and records the current `os.time()` value.
---@return nil
function NodeSensor:markRequestSent()
    self._pendingRequest = false
    self._lastRequestAt = os.time()
end

---Mark a job request pending and clear cooldown so the next eligible tick can submit.
---Used by mock-mode Runtime startup; does not mutate buffer snapshots.
---@return nil
function NodeSensor:forcePendingRequest()
    self._pendingRequest = true
    self._lastRequestAt = 0
end

---Discover and poll all configured GT machine components.
---Replaces the current scan retained on this sensor.
---@return MachineAvailabilityEntry[] # Internal availability array for the completed scan.
function NodeSensor:scanMachines()
    self._machineAvailability = {}
    local addresses = self:_discoverMachineAddresses()

    for _, address in ipairs(addresses) do
        local entry = self:_pollMachine(address)
        if entry then
            table.insert(self._machineAvailability, entry)
        end
    end

    return self._machineAvailability
end

---Enumerate component addresses matching the configured machine filter.
---@return string[] # Discovered addresses in component iterator order.
function NodeSensor:_discoverMachineAddresses()
    local addresses = {}
    local filter = self._config.machineFilter or "gt_machine"

    for address in component.list(filter) do
        table.insert(addresses, address)
    end

    return addresses
end

---Read scheduling state from one machine wrapper.
---Wrapper/proxy lookup failures return nil; exceptions from component methods propagate.
---@param address string # OpenComputers machine component address.
---@return MachineAvailabilityEntry | nil # Scheduling record, or nil when the wrapper or proxy is unavailable.
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

---Watch the configured ME controller for a changed item/fluid signature.
---Missing configuration, wrapper lookup failures, and snapshot failures are ignored.
---A change stores the snapshot, marks a request pending, and immediately scans machines.
---@return nil
function NodeSensor:_watchBuffer()
    local address = self._config.meControllerAddr or self._config.bufferSourceAddress
    if not address then
        return
    end

    local controller = self._cache:getComponent(address, "MeControllerComponent")
    if not controller then
        return
    end

    local snapshot, err = controller:getSnapshot()
    if not snapshot then
        return
    end

    local previous = self._bufferSnapshot
    if not previous or not self:_snapshotsEqual(previous, snapshot) then
        self._bufferSnapshot = snapshot
        self._pendingRequest = true
        self:scanMachines()
    end
end

---Build a stable content signature from item and fluid names and quantities.
---Entry order is ignored. Item quantity prefers `size` and falls back to `count`;
---fluid quantity uses `amount`. Other fields are not represented.
---@param snapshot BufferSnapshot # Snapshot whose items and fluids are inspected.
---@return string # Sorted, delimiter-joined content signature.
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

---Compare two buffer snapshots by their reduced content signatures.
---@param a BufferSnapshot | any # First snapshot.
---@param b BufferSnapshot | any # Second snapshot.
---@return boolean # False for non-tables; otherwise true when represented content matches.
function NodeSensor:_snapshotsEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end

    return self:_snapshotSignature(a) == self:_snapshotSignature(b)
end

return NodeSensor
