---@meta _
---@brief Sends node scheduling, status, and completion traffic to the cloud API.
---@version 1.0.0
---
---@class CloudClientConfig
---@field cloudBaseUrl any # Truthy value used as the URL prefix without type validation.
---@field nodeId any # Truthy value used as the node identifier without type validation.
---
---@class CloudClient
---@field _config CloudClientConfig # Node and cloud endpoint configuration, retained by reference.
---@field _comms Comms # Shared HTTP/JSON communications module.
-- Endpoints:
-- POST /nodes/{nodeId}/jobs/request  — buffer + availability + activeJobs → assignments[]
-- GET  /jobs/{jobId}                 — fetch assignment if cloud processes async
-- POST /nodes/{nodeId}/status        — heartbeat + active job snapshot
-- POST /jobs/{jobId}/complete        — result uplink

local JSON = require("JSON")
local Assignment = require("Assignment")

local CloudClient = {}
CloudClient.__index = CloudClient

---Create a cloud API client.
---Loads the shared Comms module and retains the supplied configuration table by reference.
---@param config CloudClientConfig | nil # Optional unvalidated cloudBaseUrl and nodeId values.
---@return CloudClient # New client instance.
function CloudClient.new(config)
    local self = setmetatable({}, CloudClient)
    self._config = config or {}
    self._comms = require("Comms")
    return self
end

---Return the configured cloud base URL.
---@return any # Truthy configured value, or an empty string when absent or false.
function CloudClient:_baseUrl()
    return self._config.cloudBaseUrl or ""
end

---Return the configured node identifier.
---@return any # Truthy configured value, or `"unknown-node"` when absent or false.
function CloudClient:_nodeId()
    return self._config.nodeId or "unknown-node"
end

---Submit current node demand and availability for cloud scheduling.
---Overwrites `request.nodeId`, performs an HTTP POST, and parses the response as
---an assignment envelope or single assignment. Transport and parse failures are returned.
---@param request table # Mutable job-request payload.
---@return Assignment[] | nil assignments # Parsed assignments, including an empty list when none are returned.
---@return string | nil error # Validation, transport, JSON, or assignment parsing error.
function CloudClient:submitJobRequest(request)
    if type(request) ~= "table" then
        return nil, "CloudClient:submitJobRequest() — expected request table"
    end

    request.nodeId = self:_nodeId()

    local url = self:_baseUrl() .. "/nodes/" .. self:_nodeId() .. "/jobs/request"
    local body, err = self._comms:requestJSONPost(url, request)
    if not body then
        return nil, err
    end

    local encoded = type(body) == "table" and JSON:encode(body) or tostring(body)
    return Assignment.listFromJSON(encoded)
end

---Fetch and parse one assignment by job identifier.
---Performs an HTTP GET and returns transport, JSON, or assignment validation failures.
---@param jobId string # Non-empty cloud job identifier.
---@return Assignment | nil assignment # Parsed assignment when the request succeeds.
---@return string | nil error # Invalid-id, transport, JSON, or assignment parsing error.
function CloudClient:pollAssignment(jobId)
    if type(jobId) ~= "string" or jobId == "" then
        return nil, "CloudClient:pollAssignment() — invalid jobId"
    end

    local url = self:_baseUrl() .. "/jobs/" .. jobId
    local body, err = self._comms:requestJSON(url)
    if not body then
        return nil, err
    end

    local encoded = type(body) == "table" and JSON:encode(body) or tostring(body)
    return Assignment.fromJSON(encoded)
end

---Post a heartbeat containing the node's active-job snapshot.
---The payload also includes the configured nodeId and current integer timestamp.
---@param activeJobsSnapshot table # Array or map of active job status records.
---@return boolean ok # True when the POST completes without a reported error.
---@return string | nil error # Validation, serialization, transport, or response-decoding error.
function CloudClient:reportStatus(activeJobsSnapshot)
    if type(activeJobsSnapshot) ~= "table" then
        return false, "CloudClient:reportStatus() — expected snapshot table"
    end

    local url = self:_baseUrl() .. "/nodes/" .. self:_nodeId() .. "/status"
    local _, err = self._comms:requestJSONPost(url, {
        nodeId = self:_nodeId(),
        activeJobs = activeJobsSnapshot,
        timestamp = math.floor(os.time()),
    })

    if err then
        return false, err
    end

    return true
end

---Post a terminal job result to the cloud.
---A nil or false result is sent as an empty table; the payload includes the current timestamp.
---@param jobId string # Non-empty completed job identifier.
---@param result any # Completion result payload; nil or false defaults to an empty table.
---@return boolean ok # True when the POST completes without a reported error.
---@return string | nil error # Invalid-id, serialization, transport, or response-decoding error.
function CloudClient:reportCompletion(jobId, result)
    if type(jobId) ~= "string" or jobId == "" then
        return false, "CloudClient:reportCompletion() — invalid jobId"
    end

    local url = self:_baseUrl() .. "/jobs/" .. jobId .. "/complete"
    local _, err = self._comms:requestJSONPost(url, {
        jobId = jobId,
        result = result or {},
        timestamp = math.floor(os.time()),
    })

    if err then
        return false, err
    end

    return true
end

return CloudClient
