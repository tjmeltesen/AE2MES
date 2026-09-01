---@class Registry
---@field _data table

local JSON = require("JSON")

local Registry = {}
Registry.__index = Registry

function Registry.fromTable(data)
    if type(data) ~= "table" then
        return nil, "Registry.fromTable() — expected table"
    end

    local self = setmetatable({}, Registry)
    self._data = data
    return self
end

function Registry:get(key)
    return self._data[key]
end

---@class RouteStep
---@field type string
---@field target string
---@field params table

local RouteStep = {}
RouteStep.__index = RouteStep

RouteStep.TYPES = {
    CONFIGURE = "configure",
    TRANSFER = "transfer",
    WAIT = "wait",
    PROCESS = "process",
    CLEAR = "clear",
    REDSTONE = "redstone",
}

function RouteStep.fromTable(data)
    if type(data) ~= "table" or type(data.type) ~= "string" then
        return nil, "RouteStep.fromTable() — invalid step"
    end

    local self = setmetatable({}, RouteStep)
    self.type = data.type
    self.target = data.target
    self.params = data.params or {}
    return self
end

---@class SequenceFlow
---@field items table
---@field fluids table
---@field steps RouteStep[]

local SequenceFlow = {}
SequenceFlow.__index = SequenceFlow

function SequenceFlow.fromTable(data)
    if type(data) ~= "table" then
        return nil, "SequenceFlow.fromTable() — expected table"
    end

    local self = setmetatable({}, SequenceFlow)
    self.items = data.items or {}
    self.fluids = data.fluids or {}
    self.steps = {}

    if type(data.steps) == "table" then
        for _, stepData in ipairs(data.steps) do
            local step, err = RouteStep.fromTable(stepData)
            if not step then
                return nil, err
            end
            table.insert(self.steps, step)
        end
    end

    return self
end

function SequenceFlow:stepCount()
    return #self.steps
end

function SequenceFlow:stepAt(index)
    return self.steps[index]
end

---@class Assignment
---@field jobId string
---@field machineAddress string
---@field registry Registry
---@field sequenceFlow SequenceFlow

local Assignment = {}
Assignment.__index = Assignment

function Assignment.fromTable(data)
    if type(data) ~= "table" or type(data.jobId) ~= "string" then
        return nil, "Assignment.fromTable() — invalid assignment"
    end

    local registry, registryErr = Registry.fromTable(data.registry or {})
    if not registry then
        return nil, registryErr
    end

    local sequenceFlow, flowErr = SequenceFlow.fromTable(data.sequenceFlow or { steps = {} })
    if not sequenceFlow then
        return nil, flowErr
    end

    local self = setmetatable({}, Assignment)
    self._jobId = data.jobId
    self._machineAddress = data.machineAddress or registry:get("machineAddress")
    self._registry = registry
    self._sequenceFlow = sequenceFlow
    return self
end

function Assignment.fromJSON(body)
    if type(body) ~= "string" then
        return nil, "Assignment.fromJSON() — expected string"
    end

    local ok, data = pcall(JSON.decode, body)
    if not ok then
        return nil, "Assignment.fromJSON() — decode failed: " .. tostring(data)
    end

    return Assignment.fromTable(data)
end

function Assignment.listFromJSON(body)
    if type(body) ~= "string" then
        return nil, "Assignment.listFromJSON() — expected string"
    end

    local ok, data = pcall(JSON.decode, body)
    if not ok then
        return nil, "Assignment.listFromJSON() — decode failed: " .. tostring(data)
    end

    local assignments = {}

    if type(data.assignments) == "table" then
        for _, item in ipairs(data.assignments) do
            local assignment, err = Assignment.fromTable(item)
            if not assignment then
                return nil, err
            end
            table.insert(assignments, assignment)
        end
    elseif type(data.jobId) == "string" then
        local assignment, err = Assignment.fromTable(data)
        if not assignment then
            return nil, err
        end
        table.insert(assignments, assignment)
    end

    return assignments
end

function Assignment:id()
    return self._jobId
end

function Assignment:registry()
    return self._registry
end

function Assignment:sequenceFlow()
    return self._sequenceFlow
end

function Assignment:machineAddress()
    return self._machineAddress
end

return Assignment
