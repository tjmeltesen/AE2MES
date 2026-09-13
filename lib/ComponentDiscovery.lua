---@meta _
---@brief Discovers the complete hardware topology of one OC-managed cluster.

local ComponentDiscovery = {}

local function addresses(componentApi, componentType)
    local found = {}
    for address in componentApi.list(componentType) do found[#found + 1] = address end
    table.sort(found)
    return found
end

local function first(configured, found)
    if type(configured) == "string" and configured ~= "" then
        for _, address in ipairs(found) do if address == configured then return configured end end
    end
    return found[1]
end

local function canonical(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = canonical(key) .. "=" .. canonical(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function ComponentDiscovery.fingerprint(value)
    return canonical(value)
end

function ComponentDiscovery.discover(config, cache)
    config = type(config) == "table" and config or {}
    local componentApi = require("component")
    local controllers = addresses(componentApi, "me_controller")
    local databases = addresses(componentApi, "database")
    local redstones = addresses(componentApi, "redstone")
    local machines = addresses(componentApi, "gt_machine")
    local interfaces = addresses(componentApi, "me_interface")
    local transposers = addresses(componentApi, "transposer")

    local meAddress = first(config.meControllerAddress or config.meControllerAddr
        or config.bufferSourceAddress, controllers)
    local databaseAddress = first(config.databaseAddress, databases)
    local redstoneAddress = first(config.redstoneAddress, redstones)
    if not meAddress then return nil, "ComponentDiscovery.discover() - missing me_controller" end
    if not databaseAddress then return nil, "ComponentDiscovery.discover() - missing database" end
    if not redstoneAddress then return nil, "ComponentDiscovery.discover() - missing redstone" end

    local transposerRecords = {}
    for _, address in ipairs(transposers) do
        local wrapper, err
        if cache then
            wrapper, err = cache:getComponent(address, "TransposerComponent")
        else
            local TransposerComponent = require("TransposerComponent")
            wrapper, err = TransposerComponent:new(address)
        end
        if not wrapper then return nil, err or ("failed to open transposer " .. address) end
        local discovered, sideErr = wrapper:discoverSides()
        if not discovered then return nil, sideErr or ("failed to inspect transposer " .. address) end
        local sides = {}
        for _, side in pairs(discovered) do
            sides[#sides + 1] = {
                side = side.side,
                sideName = side.sideName or side.side_name,
                containerName = side.containerName or side.container_name,
                slots = side.slots,
            }
        end
        table.sort(sides, function(a, b) return a.side < b.side end)
        transposerRecords[#transposerRecords + 1] = { address = address, sides = sides }
    end

    local observation = {
        clusterId = config.clusterId,
        globals = {
            meControllerAddress = meAddress,
            databaseAddress = databaseAddress,
            databaseSize = tonumber(config.databaseSize) or 9,
            redstoneAddress = redstoneAddress,
            machineAddresses = machines,
        },
        components = { machines = {}, interfaces = {}, transposers = transposerRecords },
    }
    for _, address in ipairs(machines) do
        observation.components.machines[#observation.components.machines + 1] = { address = address }
    end
    for _, address in ipairs(interfaces) do
        observation.components.interfaces[#observation.components.interfaces + 1] = { address = address }
    end
    observation.meControllerAddr = meAddress
    observation.databaseAddress = databaseAddress
    observation.databaseSize = observation.globals.databaseSize
    observation.redstoneAddress = redstoneAddress
    observation.machineAddresses = observation.globals.machineAddresses
    observation.fingerprint = ComponentDiscovery.fingerprint({ globals = observation.globals, components = observation.components })
    return observation
end

return ComponentDiscovery
