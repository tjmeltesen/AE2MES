---@meta _
---@brief Starts the AE2-ES2 node runtime with local cloud and hardware configuration.
---@version 1.0.0
---
---Entry point side effects: extends `package.path`, constructs the runtime, and then
---ticks it indefinitely at 0.5-second intervals. Runtime or sleep errors are not caught.
---
---When `useMockAssignment` is true, Runtime reads `fixtures/mock_assignment.json`,
---injects current buffer items/fluids into the fixture sequenceFlow, and prints
---status/completion locally instead of calling cloud HTTP.

package.path = "./src/?.lua;./lib/?.lua;" .. package.path

local Runtime = require("Runtime")

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

local runtime = Runtime.new(config)

while true do
    runtime:tick()
    os.sleep(0.5)
end
