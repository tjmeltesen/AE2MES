---@class CloudClient
-- Endpoints:
-- POST /nodes/{nodeId}/jobs/request  — buffer + availability + activeJobs → assignments[]
-- GET  /jobs/{jobId}                 — fetch assignment if cloud processes async
-- POST /nodes/{nodeId}/status        — heartbeat + active job snapshot
-- POST /jobs/{jobId}/complete        — result uplink

local JSON = require("JSON")
local Assignment = require("Assignment")

local CloudClient = {}
CloudClient.__index = CloudClient

function CloudClient.new(config)
    local self = setmetatable({}, CloudClient)
    self._config = config or {}
    self._comms = require("Comms")
    return self
end

function CloudClient:_baseUrl()
    return self._config.cloudBaseUrl or ""
end

function CloudClient:_nodeId()
    return self._config.nodeId or "unknown-node"
end

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

    local encoded = type(body) == "table" and JSON.encode(body) or tostring(body)
    return Assignment.listFromJSON(encoded)
end

function CloudClient:pollAssignment(jobId)
    if type(jobId) ~= "string" or jobId == "" then
        return nil, "CloudClient:pollAssignment() — invalid jobId"
    end

    local url = self:_baseUrl() .. "/jobs/" .. jobId
    local body, err = self._comms:requestJSON(url)
    if not body then
        return nil, err
    end

    local encoded = type(body) == "table" and JSON.encode(body) or tostring(body)
    return Assignment.fromJSON(encoded)
end

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
