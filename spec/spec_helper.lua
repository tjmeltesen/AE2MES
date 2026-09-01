package.path = "./src/?.lua;./lib/?.lua;./features/support/?.lua;./spec/support/?.lua;" .. package.path

local shim = require("cucumber_shim")

_G.Given = shim.Given
_G.When = shim.When
_G.Then = shim.Then
_G.Before = shim.Before

require("step_json")
require("step_assignment")
require("step_modules")
require("step_job_pool")
require("step_node_sensor")
require("step_runtime")

_G.step = shim.step
_G.run_before = shim.run_before
