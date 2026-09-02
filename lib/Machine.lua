---@meta _
---@brief API Wrapper for Machine component in OpenComputers for GTNH
---@see https://github.com/Navatusein/GTNH-OC-Lua-Documentation/blob/main/lua/components/gt-machine.lua
---@version 1.0.0
---@class Machine : BaseComponent
---@field address string

local BaseComponent = require("BaseComponent")

local Machine = setmetatable({}, { __index = BaseComponent })
Machine.__index = Machine

---Creates a new Machine instance with the specified address.
---@param address string # The address of the machine component.
---@return Machine | nil, string | nil # A new instance of Machine. Will return nil and an error message if the address is invalid.
function Machine:new(address)
    local self, err = BaseComponent.new(self, address)
    if not self then
        return nil, err
    end
    return self
end


---Returns the amount of electricity contained in this Block, in EU units! (As a string for HUGE amounts.)
---@return string storedEuString
function Machine:getStoredEUString() return self:call("getStoredEUString") end

---Returns the average EU input of this block
---@return number averageInput
function Machine:getEUInputAverage() return self:call("getEUInputAverage") end

---Gets the Output in EU/p.
---@return number outputVoltage
function Machine:getOutputVoltage() return self:call("getOutputVoltage") end

---Returns the machine's name
---@return string name
function Machine:getName() return self:call("getName") end

---Returns whether the machine is currently active
---@return boolean isActive
function Machine:isMachineActive() return self:call("isMachineActive") end

---Returns the EU stored in this block
---@return number euStored
function Machine:getEUStored() return self:call("getEUStored") end

---Returns the amount of electricity containable in this Block, in EU units!
---@return number euCapacity
function Machine:getEUCapacity() return self:call("getEUCapacity") end

---Returns the steam stored in this block
---@return number steamStored
function Machine:getSteamStored() return self:call("getSteamStored") end

---Returns sensor information about this block
---@return string[] sensorLines
function Machine:getSensorInformation() return self:call("getSensorInformation") end

---Returns the average EU output of this block
---@return number averageOutput
function Machine:getEUOutputAverage() return self:call("getEUOutputAverage") end

---Returns the amount of electricity containable in this Block, in EU units! (As a string for HUGE amounts.)
---@return string euCapacityString
function Machine:getEUCapacityString() return self:call("getEUCapacityString") end

---Returns machine coordinates
---@return {[1]:number,[2]:number,[3]:number} coordinates
function Machine:getCoordinates() return self:call("getCoordinates") end

---Returns the amount of Electricity, accepted by this Block the last 5 ticks as Average.
---@return number averageInput
function Machine:getAverageElectricInput() return self:call("getAverageElectricInput") end

---Gets the maximum Input in EU/p.
---@return number maxInput
function Machine:getInputVoltage() return self:call("getInputVoltage") end

-- Gets the amount of Energy Packets per tick.
---@return number packetPerTick
function Machine:getOutputAmperage() return self:call("getOutputAmperage") end

---Sets whether this block is currently allowed to work
---@param enabled boolean
---@return number packetPerTick
function Machine:setWorkAllowed(enabled) return self:call("setWorkAllowed", enabled) end

---Returns the name of this block's owner
---@return string ownerName
function Machine:getOwnerName() return self:call("getOwnerName") end

---Returns true if the machine currently has work to do
---@return boolean hasWork
function Machine:hasWork() return self:call("hasWork") end

---Returns the amount of Steam contained in this Block, in EU units!
---@return number storedSteamAsEu
function Machine:getStoredSteam() return self:call("getStoredSteam") end

---Returns the current progress of this block in ticks
---@return number progress
function Machine:getWorkProgress() return self:call("getWorkProgress") end

---Returns the max EU that can be stored in this block
---@return number euCapacity
function Machine:getEUMaxStored() return self:call("getEUMaxStored") end

---Returns the amount of Electricity, outputted by this Block the last 5 ticks as Average.
---@return number averageElectricOutput
function Machine:getAverageElectricOutput() return self:call("getAverageElectricOutput") end

---Returns the amount of electricity contained in this Block, in EU units!
---@return number storedEU
function Machine:getStoredEU() return self:call("getStoredEU") end

---Returns whether this block is currently allowed to work
---@return boolean isAllowed
function Machine:isWorkAllowed() return self:call("isWorkAllowed") end

---Returns the max progress of this block in ticks
---@return number maxProgress
function Machine:getWorkMaxProgress() return self:call("getWorkMaxProgress") end

---Returns the amount of Steam containable in this Block, in EU units!
---@return number steamCapacityAsEU
function Machine:getSteamCapacity() return self:call("getSteamCapacity") end

---Returns the max steam that can be stored in this block
---@return number steamCapacity
function Machine:getSteamMaxStored() return self:call("getSteamMaxStored") end

local function signalBoolean(value)
    if value == nil then
        return nil
    end
    return value == true
end

local function appendReason(reasons, code)
    table.insert(reasons, code)
end

local function stripFormatting(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("§.", "")
end

local function parseSensorNumber(value)
    if type(value) ~= "string" then
        return nil
    end
    local normalized = value:gsub(",", "")
    return tonumber(normalized)
end

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
---@param rawLines string[]|nil
---@return table
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

local function sensorHasProblems(sensor)
    return type(sensor) == "table"
        and type(sensor.problems) == "number"
        and sensor.problems > 0
end

---Parsed view of getSensorInformation() for scheduling decisions.
---@return table|nil
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
---@return table
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