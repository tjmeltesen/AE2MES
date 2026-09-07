---@meta _
---@brief Parses and exposes cloud job assignments, registries, route steps, and sequence flows.
---@version 1.0.0
---
---@class Registry
---@field _data table<string, any> # Original registry table, retained by reference.

local JSON = require("JSON")

local Registry = {}
Registry.__index = Registry

---Wrap a registry data table without copying it.
---Changes made to `data` after this call remain visible through the registry.
---@param data any # Candidate registry values keyed by assignment field name.
---@return Registry | nil registry # New registry wrapper, or nil when `data` is not a table.
---@return string | nil error # Validation error when `data` is not a table.
function Registry.fromTable(data)
    if type(data) ~= "table" then
        return nil, "Registry.fromTable() — expected table"
    end

    local self = setmetatable({}, Registry)
    self._data = data
    return self
end

---Return a registry value by key.
---@param key string # Registry field name.
---@return any # Stored value, or nil when the key is absent.
function Registry:get(key)
    return self._data[key]
end

---@class RouteStep
---@field type any # Legacy route operation value retained from input.
---@field method any # Method-oriented route operation value retained from input.
---@field target any # Optional target value copied from input without validation.
---@field params any # Truthy input value retained without validation; false or nil becomes an empty table.

local RouteStep = {}
RouteStep.__index = RouteStep

---Supported legacy route-step type names.
---@enum RouteStepType
RouteStep.TYPES = {
    CONFIGURE = "configure",
    TRANSFER = "transfer",
    WAIT = "wait",
    PROCESS = "process",
    CLEAR = "clear",
    REDSTONE = "redstone",
}

---Create a route step from a table containing a string `type` or `method`.
---The target is retained without validation. Truthy params values are retained by reference;
---false or nil params become an empty table.
---@param data any # Candidate route-step data.
---@return RouteStep | nil step # Parsed step, or nil when the input or operation name is invalid.
---@return string | nil error # Validation error when no supported operation-name field is present.
function RouteStep.fromTable(data)
    if type(data) ~= "table"
        or (type(data.type) ~= "string" and type(data.method) ~= "string") then
        return nil, "RouteStep.fromTable() — invalid step"
    end

    local self = setmetatable({}, RouteStep)
    self.type = data.type
    self.method = data.method
    self.target = data.target
    self.params = data.params or {}
    return self
end

---@class SequenceFlow
---@field items any # Truthy input value retained without validation; false or nil becomes an empty table.
---@field fluids any # Truthy input value retained without validation; false or nil becomes an empty table.
---@field steps RouteStep[]

local SequenceFlow = {}
SequenceFlow.__index = SequenceFlow

---Create a sequence flow and parse each route step in order.
---False or missing items and fluids become empty tables; other values are retained without validation.
---Table-valued steps are parsed in order and malformed entries abort parsing. A non-table steps
---value is silently treated as an empty sequence.
---@param data any # Candidate sequence-flow data.
---@return SequenceFlow | nil flow # Parsed sequence flow, or nil when input or a route step is invalid.
---@return string | nil error # Validation error from this flow or one of its route steps.
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

---Return the number of parsed route steps.
---@return integer # Current length of the steps array.
function SequenceFlow:stepCount()
    return #self.steps
end

---Return the route step at a one-based array index.
---@param index integer # One-based position in the route.
---@return RouteStep | nil # Step at `index`, or nil when no step exists there.
function SequenceFlow:stepAt(index)
    return self.steps[index]
end

---@class Assignment
---@field _jobId string # Cloud job identifier.
---@field _machineAddress any # Explicit or registry-derived machine selector retained without validation.
---@field _registry Registry # Parsed component and side registry.
---@field _sequenceFlow SequenceFlow # Parsed materials and route steps.

local Assignment = {}
Assignment.__index = Assignment

---Parse an assignment table into its registry and sequence-flow wrappers.
---The jobId must be a string. A truthy machineAddress is retained without type validation;
---false or missing values fall back to the registry.
---@param data any # Candidate assignment object.
---@return Assignment | nil assignment # Parsed assignment, or nil when validation fails.
---@return string | nil error # Assignment, registry, or route validation error.
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

---Decode one JSON assignment object and parse it.
---@param body string # JSON document containing a single assignment.
---@return Assignment | nil assignment # Parsed assignment, or nil when decoding or validation fails.
---@return string | nil error # Type, JSON decoding, or assignment validation error.
function Assignment.fromJSON(body)
    if type(body) ~= "string" then
        return nil, "Assignment.fromJSON() — expected string"
    end

    local ok, data = pcall(JSON.decode, JSON, body)
    if not ok then
        return nil, "Assignment.fromJSON() — decode failed: " .. tostring(data)
    end

    return Assignment.fromTable(data)
end

---Decode either an assignment envelope or a single assignment object.
---An object with an `assignments` table parses each entry in order; an object with a string
---`jobId` is treated as one assignment. Other decoded tables return an empty list.
---@param body string # JSON document containing `{ assignments = [...] }` or one assignment.
---@return Assignment[] | nil assignments # Parsed assignments, or nil if decoding or any entry fails.
---@return string | nil error # Type, JSON decoding, or assignment validation error.
function Assignment.listFromJSON(body)
    if type(body) ~= "string" then
        return nil, "Assignment.listFromJSON() — expected string"
    end

    local ok, data = pcall(JSON.decode, JSON, body)
    if not ok then
        return nil, "Assignment.listFromJSON() — decode failed: " .. tostring(data)
    end
    if type(data) ~= "table" then
        return nil, "Assignment.listFromJSON() — expected JSON object"
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

---Return the cloud job identifier.
---@return string # Assignment jobId.
function Assignment:id()
    return self._jobId
end

---Return the parsed registry wrapper.
---@return Registry # Assignment registry.
function Assignment:registry()
    return self._registry
end

---Return the parsed sequence flow.
---@return SequenceFlow # Assignment materials and route steps.
function Assignment:sequenceFlow()
    return self._sequenceFlow
end

---Return the selected machine component address.
---@return any # Explicit or registry-derived value; nil when neither was supplied.
function Assignment:machineAddress()
    return self._machineAddress
end

return Assignment
