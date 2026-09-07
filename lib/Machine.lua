---@meta _
---@brief API wrapper and scheduler-facing sensor parser for OpenComputers GT machines.
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/gt-machine.lua
---@version 1.0.0
---@class MachineSensor
---@field raw any # Original sensor information value.
---@field lines string[] # Formatting-stripped sensor lines.
---@field progress { current: number|nil, max: number|nil }
---@field energy { stored: number|nil, capacity: number|nil, usage: number|nil, maxIncome: number|nil }
---@field tier string|nil
---@field problems number|nil
---@field efficiency number|nil
---@field pollutionReduction number|nil
---@field unknown string[] # Unrecognized stripped lines.
---@class MachineAvailability
---@field available boolean
---@field active boolean
---@field hasWork boolean
---@field workAllowed boolean
---@field problems number
---@field progressCurrent number|nil
---@field progressMax number|nil
---@field tier string|nil
---@field unavailableReason string # Comma-separated scheduler reason codes.
---@field sensorLines string[]
---@class Machine : BaseComponent
---@field address string # OpenComputers component address inherited from BaseComponent.

local BaseComponent = require("BaseComponent")

local Machine = setmetatable({}, { __index = BaseComponent })
Machine.__index = Machine

---Create a GT machine wrapper for the specified component address.
---@param address string # The address of the machine component.
---@return Machine|nil machine
---@return string|nil error # Invalid addresses are rejected by BaseComponent.
function Machine:new(address)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    return self
end


---Returns the amount of electricity contained in this Block, in EU units! (As a string for HUGE amounts.)
---@return string|nil storedEuString
---@return string|nil error
function Machine:getStoredEUString() return self:call("getStoredEUString") end

---Returns the average EU input of this block
---@return number|nil averageInput
---@return string|nil error
function Machine:getEUInputAverage() return self:call("getEUInputAverage") end

---Gets the Output in EU/p.
---@return number|nil outputVoltage
---@return string|nil error
function Machine:getOutputVoltage() return self:call("getOutputVoltage") end

---Returns the machine's name
---@return string|nil name
---@return string|nil error
function Machine:getName() return self:call("getName") end

---Returns whether the machine is currently active
---@return boolean|nil isActive
---@return string|nil error
function Machine:isMachineActive() return self:call("isMachineActive") end

---Returns the EU stored in this block
---@return number|nil euStored
---@return string|nil error
function Machine:getEUStored() return self:call("getEUStored") end

---Returns the amount of electricity containable in this Block, in EU units!
---@return number|nil euCapacity
---@return string|nil error
function Machine:getEUCapacity() return self:call("getEUCapacity") end

---Returns the steam stored in this block
---@return number|nil steamStored
---@return string|nil error
function Machine:getSteamStored() return self:call("getSteamStored") end

---Returns sensor information about this block
---@return string[]|nil sensorLines
---@return string|nil error
function Machine:getSensorInformation() return self:call("getSensorInformation") end

---Returns the average EU output of this block
---@return number|nil averageOutput
---@return string|nil error
function Machine:getEUOutputAverage() return self:call("getEUOutputAverage") end

---Returns the amount of electricity containable in this Block, in EU units! (As a string for HUGE amounts.)
---@return string|nil euCapacityString
---@return string|nil error
function Machine:getEUCapacityString() return self:call("getEUCapacityString") end

---Returns machine coordinates
---@return {[1]:number,[2]:number,[3]:number}|nil coordinates
---@return string|nil error
function Machine:getCoordinates() return self:call("getCoordinates") end

---Returns the amount of Electricity, accepted by this Block the last 5 ticks as Average.
---@return number|nil averageInput
---@return string|nil error
function Machine:getAverageElectricInput() return self:call("getAverageElectricInput") end

---Gets the maximum Input in EU/p.
---@return number|nil maxInput
---@return string|nil error
function Machine:getInputVoltage() return self:call("getInputVoltage") end

---Get the amount of output energy packets emitted per tick.
---@return number|nil packetsPerTick
---@return string|nil error
function Machine:getOutputAmperage() return self:call("getOutputAmperage") end

---Set whether the machine is allowed to work.
---Mutates the machine's work-enabled state.
---@param enabled boolean
---@return any|nil result # Component-defined acknowledgement.
---@return string|nil error
function Machine:setWorkAllowed(enabled) return self:call("setWorkAllowed", enabled) end

---Returns the name of this block's owner
---@return string|nil ownerName
---@return string|nil error
function Machine:getOwnerName() return self:call("getOwnerName") end

---Returns true if the machine currently has work to do
---@return boolean|nil hasWork
---@return string|nil error
function Machine:hasWork() return self:call("hasWork") end

---Returns the amount of Steam contained in this Block, in EU units!
---@return number|nil storedSteamAsEu
---@return string|nil error
function Machine:getStoredSteam() return self:call("getStoredSteam") end

---Returns the current progress of this block in ticks
---@return number|nil progress
---@return string|nil error
function Machine:getWorkProgress() return self:call("getWorkProgress") end

---Returns the max EU that can be stored in this block
---@return number|nil euCapacity
---@return string|nil error
function Machine:getEUMaxStored() return self:call("getEUMaxStored") end

---Returns the amount of Electricity, outputted by this Block the last 5 ticks as Average.
---@return number|nil averageElectricOutput
---@return string|nil error
function Machine:getAverageElectricOutput() return self:call("getAverageElectricOutput") end

---Returns the amount of electricity contained in this Block, in EU units!
---@return number|nil storedEU
---@return string|nil error
function Machine:getStoredEU() return self:call("getStoredEU") end

---Returns whether this block is currently allowed to work
---@return boolean|nil isAllowed
---@return string|nil error
function Machine:isWorkAllowed() return self:call("isWorkAllowed") end

---Returns the max progress of this block in ticks
---@return number|nil maxProgress
---@return string|nil error
function Machine:getWorkMaxProgress() return self:call("getWorkMaxProgress") end

---Returns the amount of Steam containable in this Block, in EU units!
---@return number|nil steamCapacityAsEU
---@return string|nil error
function Machine:getSteamCapacity() return self:call("getSteamCapacity") end

---Returns the max steam that can be stored in this block
---@return number|nil steamCapacity
---@return string|nil error
function Machine:getSteamMaxStored() return self:call("getSteamMaxStored") end

---Normalize a signal value to true only for literal boolean true.
---@param value any
---@return boolean|nil normalized # Nil remains unknown; every other non-true value becomes false.
local function signalBoolean(value)
    if value == nil then
        return nil
    end
    return value == true
end

---Append a scheduler reason code to a list.
---@param reasons string[]
---@param code string
---@return nil
local function appendReason(reasons, code)
    table.insert(reasons, code)
end

---Remove Minecraft section-sign formatting pairs from a sensor line.
---@param value any
---@return string stripped # Empty string for non-string values.
local function stripFormatting(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("§.", "")
end

---Parse a comma-grouped decimal number from sensor text.
---@param value any
---@return number|nil value
local function parseSensorNumber(value)
    if type(value) ~= "string" then
        return nil
    end
    local normalized = value:gsub(",", "")
    return tonumber(normalized)
end

---Create an empty parsed sensor record retaining the original raw value.
---@param raw any
---@return MachineSensor sensor
local function emptySensor(raw)
    return {
        raw = raw,
        lines = {},
        progress = { current = nil, max = nil },
        energy = { stored = nil, capacity = nil, usage = nil, maxIncome = nil },
        tier = nil,
        problems = nil,
        efficiency = nil,
        pollutionReduction = nil,
        unknown = {},
    }
end

---Parse the raw lines returned by getSensorInformation().
---Formatting codes are removed, recognized English GTNH labels populate structured fields,
---and all other lines are retained in `unknown`.
---@param rawLines string[]|nil
---@return MachineSensor sensor
local function parseSensorLines(rawLines)
    if type(rawLines) ~= "table" then
        return emptySensor(rawLines)
    end

    local sensor = emptySensor(rawLines)

    for _, rawLine in ipairs(rawLines) do
        local line = stripFormatting(rawLine)
        table.insert(sensor.lines, line)

        local current, max = line:match("Progress:%s*([%d%.]+)%s*s%s*/%s*([%d%.]+)%s*s")
        if current and max then
            sensor.progress.current = tonumber(current)
            sensor.progress.max = tonumber(max)
        else
            local stored, capacity = line:match(
                "Stored Energy:%s*([%d,%.]+)%s*EU%s*/%s*([%d,%.]+)%s*EU"
            )
            if stored and capacity then
                sensor.energy.stored = parseSensorNumber(stored)
                sensor.energy.capacity = parseSensorNumber(capacity)
            else
                local usage = line:match("Currently uses:%s*([%d,%.]+)%s*EU/t")
                if usage then
                    sensor.energy.usage = parseSensorNumber(usage)
                else
                    local income = line:match("Max Energy Income:%s*([%d,%.]+)%s*EU/t")
                    local tier = line:match("Tier:%s*(%S+)")
                    if income then
                        sensor.energy.maxIncome = parseSensorNumber(income)
                    end
                    if tier then
                        sensor.tier = tier
                    end
                    if not income and not tier then
                        local problems = line:match("Problems:%s*([%d,%.]+)")
                        local efficiency = line:match("Efficiency:%s*([%d,%.]+)%s*%%")
                        if problems then
                            sensor.problems = parseSensorNumber(problems)
                        end
                        if efficiency then
                            sensor.efficiency = parseSensorNumber(efficiency)
                        end
                        if not problems and not efficiency then
                            local pollution = line:match(
                                "Pollution reduced to:%s*([%d,%.]+)%s*%%"
                            )
                            if pollution then
                                sensor.pollutionReduction = parseSensorNumber(pollution)
                            else
                                table.insert(sensor.unknown, line)
                            end
                        end
                    end
                end
            end
        end
    end

    return sensor
end

---Return whether parsed progress is strictly between zero and its positive maximum.
---@param sensor MachineSensor|any
---@return boolean
local function sensorIsProcessing(sensor)
    if type(sensor) ~= "table" or type(sensor.progress) ~= "table" then
        return false
    end

    local current = sensor.progress.current
    local max = sensor.progress.max
    if current == nil or max == nil then
        return false
    end

    return current > 0 and max > 0 and current < max
end

---Return whether a parsed sensor reports a positive numeric problem count.
---@param sensor MachineSensor|any
---@return boolean
local function sensorHasProblems(sensor)
    return type(sensor) == "table"
        and type(sensor.problems) == "number"
        and sensor.problems > 0
end

---Get and parse machine sensor information for scheduling decisions.
---Component errors and non-table responses are collapsed to nil.
---@return MachineSensor|nil sensor
function Machine:parseSensorInformation()
    local raw = self:getSensorInformation()
    if type(raw) ~= "table" then
        return nil
    end
    return parseSensorLines(raw)
end

---Read GT machine state for cloud scheduling.
---Availability is derived from getSensorInformation(); isWorkAllowed is the only
---extra GT call because soft-mallet state is not present in sensor lines.
---Component failures are represented as an empty sensor and an allowed work state, so callers
---cannot distinguish those failures from missing telemetry in the returned record.
---@return MachineAvailability availability
function Machine:pollAvailability()
    local sensor = self:parseSensorInformation() or emptySensor(nil)
    local workAllowed = signalBoolean(self:isWorkAllowed())
    local processing = sensorIsProcessing(sensor)
    local problems = sensor.problems or 0
    local reasons = {}

    if workAllowed == false then
        appendReason(reasons, "work_disabled")
    end
    if processing then
        appendReason(reasons, "processing")
    elseif sensor.progress.current ~= nil
        and sensor.progress.max ~= nil
        and sensor.progress.max > 0
        and sensor.progress.current >= sensor.progress.max then
        appendReason(reasons, "recipe_complete")
    end
    if sensorHasProblems(sensor) then
        appendReason(reasons, "problems:" .. tostring(problems))
    end

    return {
        available = #reasons == 0,
        active = processing,
        hasWork = processing or (
            sensor.progress.max ~= nil and (sensor.progress.current or 0) > 0
        ),
        workAllowed = workAllowed ~= false,
        problems = problems,
        progressCurrent = sensor.progress.current,
        progressMax = sensor.progress.max,
        tier = sensor.tier,
        unavailableReason = table.concat(reasons, ","),
        sensorLines = sensor.lines,
    }
end

return Machine