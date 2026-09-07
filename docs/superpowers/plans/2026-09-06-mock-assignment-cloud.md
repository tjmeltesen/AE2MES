# Mock Assignment Cloud Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let in-game Runtime pull assignments from a local JSON fixture (with buffer items/fluids injected) and print status/completion locally when `useMockAssignment` is enabled.

**Architecture:** Add mock branches inside existing `CloudClient` gated by config. Add a one-shot `NodeSensor:forcePendingRequest()` used by `Runtime.new` in mock mode. Ship `fixtures/mock_assignment.json` and wire flags in `main.lua`. No JobPool/NodeComponent changes.

**Tech Stack:** OpenComputers Lua, existing `Assignment` / `JSON` / `Runtime` / `NodeSensor`, standalone unit tests via `lua` (same style as `spec/job_pool_unit.lua`).

## Global Constraints

- In-game OC with real hardware; mock replaces cloud HTTP only.
- Config flags: `useMockAssignment`, `mockAssignmentPath` (default `fixtures/mock_assignment.json`).
- Fixture authors registry/sides/steps; items/fluids overwritten from `request.buffer` at submit time.
- When mock is on: status and completion print and return success (no HTTP).
- Force one pending job request at Runtime startup in mock mode.
- Do not change JobPool or NodeComponent execution semantics.
- Do not create a separate MockCloudClient or main_mock.lua.

## File Structure

| File | Responsibility |
|------|----------------|
| `fixtures/mock_assignment.json` | Editable in-game assignment fixture (registry + steps) |
| `src/CloudClient.lua` | Mock read/inject/parse + local status/completion |
| `src/NodeSensor.lua` | `forcePendingRequest()` one-shot kick |
| `src/Runtime.lua` | Call force pending when mock config is on |
| `src/main.lua` | Enable mock flags + document usage |
| `spec/cloud_client_mock_unit.lua` | Unit coverage for mock CloudClient + Runtime kick |
| `scripts/run_tests.sh` | Include the new unit file |

---

### Task 1: Fixture + CloudClient mock request path

**Files:**
- Create: `fixtures/mock_assignment.json`
- Create: `spec/cloud_client_mock_unit.lua`
- Modify: `src/CloudClient.lua`
- Modify: `scripts/run_tests.sh`
- Test: `spec/cloud_client_mock_unit.lua`

**Interfaces:**
- Consumes: `Assignment.listFromJSON`, `Assignment.fromJSON`, `JSON:decode` / `JSON:encode`
- Produces:
  - `CloudClientConfig.useMockAssignment: boolean | nil`
  - `CloudClientConfig.mockAssignmentPath: string | nil`
  - `CloudClient:_mockEnabled(): boolean`
  - `CloudClient:_mockAssignmentPath(): string`
  - `CloudClient:_readMockAssignmentFile(): string|nil, string|nil`
  - `CloudClient:_applyBufferToAssignmentData(data, buffer): table`
  - Mock `submitJobRequest` returns `Assignment[]` with buffer-derived items/fluids

- [ ] **Step 1: Create the fixture file**

Create `fixtures/mock_assignment.json` with empty items/fluids and placeholder addresses (user replaces with real OC addresses). Use current JobPool step methods:

```json
{
  "schemaVersion": 1,
  "jobId": "job-mock-001",
  "machineAddress": "REPLACE_MACHINE_ADDRESS",
  "registry": {
    "machineAddress": "REPLACE_MACHINE_ADDRESS",
    "transposerAddress": "REPLACE_TRANSPOSER_ADDRESS",
    "interfaceAddress": "REPLACE_INTERFACE_ADDRESS",
    "databaseAddress": "REPLACE_DATABASE_ADDRESS",
    "redstoneAddress": "REPLACE_REDSTONE_ADDRESS",
    "databaseSize": 9,
    "transposerSides": {
      "pull": 5,
      "input": 0,
      "returnSide": 2
    },
    "redstoneSides": {
      "start": 0,
      "stop": 1
    }
  },
  "sequenceFlow": {
    "items": [],
    "fluids": [],
    "steps": [
      { "method": "transferToMachine", "params": {} },
      { "method": "waitForProcess", "params": { "timeout": 600 } }
    ]
  }
}
```

- [ ] **Step 2: Write the failing unit tests**

Create `spec/cloud_client_mock_unit.lua`:

```lua
package.path = "./src/?.lua;./lib/?.lua;./features/support/?.lua;" .. package.path

local failures = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("PASS: " .. name)
        return
    end
    failures = failures + 1
    print("FAIL: " .. name .. " - " .. tostring(err))
end

local function assertEqual(expected, actual, message)
    if expected ~= actual then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected truthy")
    end
end

test("mock submitJobRequest loads fixture and injects buffer materials", function()
    package.loaded["CloudClient"] = nil
    package.loaded["Comms"] = {
        requestJSONPost = function()
            error("HTTP should not run in mock mode")
        end,
        requestJSON = function()
            error("HTTP should not run in mock mode")
        end,
    }

    local CloudClient = require("CloudClient")
    local client = CloudClient.new({
        nodeId = "broker-alpha",
        useMockAssignment = true,
        mockAssignmentPath = "fixtures/mock_assignment.json",
    })

    local assignments, err = client:submitJobRequest({
        buffer = {
            items = {
                { name = "minecraft:iron_ingot", label = "Iron Ingot", size = 64 },
            },
            fluids = {
                { name = "water", label = "Water", amount = 1000 },
            },
        },
    })

    assertEqual(nil, err, "mock submit should succeed")
    assertTrue(assignments and #assignments == 1, "one assignment")
    local flow = assignments[1]:sequenceFlow()
    assertEqual("minecraft:iron_ingot", flow.items[1].name, "item name")
    assertEqual(64, flow.items[1].count, "item count from buffer size")
    assertEqual("water", flow.fluids[1].name, "fluid name")
    assertEqual(1000, flow.fluids[1].amount, "fluid amount")
    assertEqual("REPLACE_MACHINE_ADDRESS", assignments[1]:machineAddress(), "fixture machine")
end)

test("mock reportStatus and reportCompletion succeed without HTTP", function()
    package.loaded["CloudClient"] = nil
    package.loaded["Comms"] = {
        requestJSONPost = function()
            error("HTTP should not run in mock mode")
        end,
    }

    local CloudClient = require("CloudClient")
    local client = CloudClient.new({ useMockAssignment = true })

    local okStatus, statusErr = client:reportStatus({})
    assertEqual(true, okStatus, statusErr or "status ok")
    local okDone, doneErr = client:reportCompletion("job-mock-001", { success = true })
    assertEqual(true, okDone, doneErr or "completion ok")
end)

if failures > 0 then
    os.exit(1)
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `lua spec/cloud_client_mock_unit.lua`

Expected: FAIL because mock config fields / mock branches do not exist yet (HTTP stub errors or missing helpers).

- [ ] **Step 4: Implement CloudClient mock helpers and branches**

Update `src/CloudClient.lua` annotations and add helpers near `_nodeId`:

```lua
---@class CloudClientConfig
---@field cloudBaseUrl any
---@field nodeId any
---@field useMockAssignment boolean|nil
---@field mockAssignmentPath string|nil

function CloudClient:_mockEnabled()
    return self._config.useMockAssignment == true
end

function CloudClient:_mockAssignmentPath()
    local path = self._config.mockAssignmentPath
    if type(path) == "string" and path ~= "" then
        return path
    end
    return "fixtures/mock_assignment.json"
end

function CloudClient:_readMockAssignmentFile()
    local path = self:_mockAssignmentPath()
    local file, openErr = io.open(path, "r")
    if not file then
        return nil, "CloudClient:_readMockAssignmentFile() — failed to open "
            .. tostring(path) .. ": " .. tostring(openErr)
    end
    local body = file:read("*a")
    file:close()
    if type(body) ~= "string" or body == "" then
        return nil, "CloudClient:_readMockAssignmentFile() — empty file: " .. tostring(path)
    end
    return body
end

---Copy request.buffer materials onto assignment sequenceFlow (size → count for items).
function CloudClient:_applyBufferToAssignmentData(data, buffer)
    data.sequenceFlow = data.sequenceFlow or {}
    local items = {}
    local fluids = {}

    for _, item in ipairs((buffer and buffer.items) or {}) do
        table.insert(items, {
            name = item.name,
            label = item.label,
            count = item.count or item.size or 0,
        })
    end

    for _, fluid in ipairs((buffer and buffer.fluids) or {}) do
        table.insert(fluids, {
            name = fluid.name,
            label = fluid.label,
            amount = fluid.amount or 0,
        })
    end

    data.sequenceFlow.items = items
    data.sequenceFlow.fluids = fluids
    return data
end
```

At the top of `submitJobRequest`, after request-table validation and `request.nodeId = ...`:

```lua
if self:_mockEnabled() then
    local body, readErr = self:_readMockAssignmentFile()
    if not body then
        return nil, readErr
    end

    local ok, data = pcall(JSON.decode, JSON, body)
    if not ok or type(data) ~= "table" then
        return nil, "CloudClient:submitJobRequest() — mock JSON decode failed: " .. tostring(data)
    end

    if type(data.assignments) == "table" then
        for _, entry in ipairs(data.assignments) do
            self:_applyBufferToAssignmentData(entry, request.buffer)
        end
    else
        self:_applyBufferToAssignmentData(data, request.buffer)
    end

    return Assignment.listFromJSON(JSON:encode(data))
end
```

At the top of `pollAssignment` after jobId validation:

```lua
if self:_mockEnabled() then
    local body, readErr = self:_readMockAssignmentFile()
    if not body then
        return nil, readErr
    end
    local assignment, err = Assignment.fromJSON(body)
    if not assignment then
        return nil, err
    end
    if assignment:id() ~= jobId then
        return nil, "CloudClient:pollAssignment() — mock fixture jobId mismatch"
    end
    return assignment
end
```

At the top of `reportStatus` after snapshot validation:

```lua
if self:_mockEnabled() then
    local count = 0
    for _ in pairs(activeJobsSnapshot) do
        count = count + 1
    end
    print(string.format("[CloudClient:mock] status node=%s activeJobs=%s",
        tostring(self:_nodeId()), tostring(count)))
    return true
end
```

At the top of `reportCompletion` after jobId validation:

```lua
if self:_mockEnabled() then
    local okFlag = type(result) == "table" and result.success
    print(string.format("[CloudClient:mock] completion jobId=%s success=%s",
        tostring(jobId), tostring(okFlag)))
    return true
end
```

- [ ] **Step 5: Wire the new unit file into the test runner**

In `scripts/run_tests.sh`, after `lua spec/job_pool_unit.lua` add:

```bash
lua spec/cloud_client_mock_unit.lua
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `lua spec/cloud_client_mock_unit.lua`

Expected:

```
PASS: mock submitJobRequest loads fixture and injects buffer materials
PASS: mock reportStatus and reportCompletion succeed without HTTP
```

- [ ] **Step 7: Commit**

```bash
git add fixtures/mock_assignment.json src/CloudClient.lua spec/cloud_client_mock_unit.lua scripts/run_tests.sh
git commit -m "feat: add mock assignment file mode to CloudClient"
```

---

### Task 2: Startup pending kick + main.lua config

**Files:**
- Modify: `src/NodeSensor.lua`
- Modify: `src/Runtime.lua`
- Modify: `src/main.lua`
- Modify: `spec/cloud_client_mock_unit.lua`
- Test: `spec/cloud_client_mock_unit.lua`

**Interfaces:**
- Consumes: `CloudClientConfig.useMockAssignment`
- Produces:
  - `NodeSensor:forcePendingRequest(): nil` — sets `_pendingRequest = true` and `_lastRequestAt = 0`
  - `Runtime.new` calls `forcePendingRequest` when `config.useMockAssignment == true`
  - `main.lua` exposes `useMockAssignment` / `mockAssignmentPath`

- [ ] **Step 1: Extend unit tests for the startup kick**

Append to `spec/cloud_client_mock_unit.lua` (before the failures exit):

```lua
test("Runtime forces one pending request in mock mode", function()
    package.loaded["Runtime"] = nil
    package.loaded["CloudClient"] = nil
    package.loaded["NodeSensor"] = nil
    package.loaded["JobPool"] = nil
    package.loaded["Cache"] = nil
    package.loaded["Comms"] = {
        requestJSONPost = function() error("no http") end,
        requestJSON = function() error("no http") end,
    }

    -- Avoid requiring real OC component during NodeSensor construction/tick.
    package.loaded["component"] = {
        list = function() return function() end end,
    }

    local Runtime = require("Runtime")
    local runtime = Runtime.new({
        useMockAssignment = true,
        mockAssignmentPath = "fixtures/mock_assignment.json",
        nodeId = "broker-alpha",
        jobRequestCooldown = 0,
    })

    assertEqual(true, runtime._nodeSensor:hasPendingRequest(), "mock startup should pending")
end)
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `lua spec/cloud_client_mock_unit.lua`

Expected: FAIL on `"mock startup should pending"` (pending remains false).

- [ ] **Step 3: Add NodeSensor:forcePendingRequest**

In `src/NodeSensor.lua`, after `markRequestSent`:

```lua
---Mark a job request pending and clear cooldown so the next eligible tick can submit.
---Used by mock-mode Runtime startup; does not mutate buffer snapshots.
---@return nil
function NodeSensor:forcePendingRequest()
    self._pendingRequest = true
    self._lastRequestAt = 0
end
```

- [ ] **Step 4: Call it from Runtime.new in mock mode**

In `src/Runtime.lua` `Runtime.new`, after collaborators are constructed:

```lua
if self._config.useMockAssignment == true then
    self._nodeSensor:forcePendingRequest()
end
```

Also extend `RuntimeConfig` annotations with `useMockAssignment` and `mockAssignmentPath`.

- [ ] **Step 5: Enable mock flags in main.lua**

Update `src/main.lua` config to:

```lua
---@type RuntimeConfig
local config = {
    nodeId = "broker-alpha",
    cloudBaseUrl = "https://nonamphibian-unpredictably-deandre.ngrok-free.dev",
    meControllerAddr = "61df706b-463f-453f-ba71-c2c43a79e12a",
    machineFilter = "gt_machine",
    statusInterval = 30,
    statusRetryDelay = 15,
    jobRequestCooldown = 15,

    -- In-game full pipeline without cloud HTTP.
    -- Edit fixtures/mock_assignment.json addresses/sides, then set true.
    useMockAssignment = true,
    mockAssignmentPath = "fixtures/mock_assignment.json",
}
```

Add a brief header comment that mock mode reads the fixture, injects buffer items/fluids, and prints status/completion locally.

- [ ] **Step 6: Run unit tests**

Run: `lua spec/cloud_client_mock_unit.lua`

Expected: all PASS (including Runtime pending kick).

Optionally: `lua spec/job_pool_unit.lua` to confirm no regressions.

- [ ] **Step 7: Commit**

```bash
git add src/NodeSensor.lua src/Runtime.lua src/main.lua spec/cloud_client_mock_unit.lua
git commit -m "feat: force mock assignment request on Runtime startup"
```

---

## Spec Coverage Check

| Spec requirement | Task |
|------------------|------|
| `useMockAssignment` + `mockAssignmentPath` config | Task 1 + Task 2 |
| `fixtures/mock_assignment.json` registry/steps, empty materials | Task 1 |
| Mock submit reads file, injects buffer items/fluids | Task 1 |
| Mock status/completion print + success | Task 1 |
| Mock pollAssignment from file | Task 1 |
| HTTP unchanged when flag false | Task 1 (branches only when enabled) |
| One forced pending request at startup | Task 2 |
| Runtime/JobPool/NodeComponent path unchanged | Task 2 (Runtime kick only) |
| Unit tests for mock client | Task 1 + Task 2 |
| In-game usage via main.lua | Task 2 |
