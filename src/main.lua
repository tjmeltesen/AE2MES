-- AE2-ES2 entry point
-- config: nodeId, cloudBaseUrl, meControllerAddr, machineFilter, statusInterval

package.path = "./src/?.lua;./lib/?.lua;" .. package.path

local Runtime = require("Runtime")

local config = {
    nodeId = "broker-alpha",
    cloudBaseUrl = "https://nonamphibian-unpredictably-deandre.ngrok-free.dev",
    meControllerAddr = "61df706b-463f-453f-ba71-c2c43a79e12a",
    machineFilter = "gt_machine",
    statusInterval = 30,
    statusRetryDelay = 15,
    jobRequestCooldown = 15,
}

local runtime = Runtime.new(config)

while true do
    runtime:tick()
    os.sleep(0.5)
end
