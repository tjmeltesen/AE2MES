local JSON = require("JSON")

local mock_oc = {}

local DEFAULT_MACHINES = {
    ["machine-lathe"] = { active = false, hasWork = false },
    ["machine-assembler"] = { active = true, hasWork = true },
    ["abc-123"] = { active = false, hasWork = false },
    ["machine-001"] = { active = false, hasWork = false },
}

local DEFAULT_BUFFER = {
    items = {
        { name = "minecraft:iron_ingot", label = "Iron Ingot", size = 64 },
    },
    fluids = {
        { name = "water", label = "Water", amount = 1000 },
    },
}

local state = {
    machines = {},
    buffer = { items = {}, fluids = {} },
    cloudAssignments = {},
    machineActive = false,
    transferCount = 4,
    proxyOverrides = {},
}

local function cloneTable(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        if type(item) == "table" then
            copy[key] = cloneTable(item)
        else
            copy[key] = item
        end
    end
    return copy
end

local function resolveType(address)
    if type(address) ~= "string" then
        return nil
    end
    if address:find("^me%-") or address:find("^me_") then
        return "me_controller"
    end
    if address:find("^trans") or address:find("^transposer") then
        return "transposer"
    end
    if address:find("^db%-") or address:find("^database") then
        return "database"
    end
    if address:find("^redstone") then
        return "redstone"
    end
    if address:find("^iface") then
        return "me_interface"
    end
    if address:find("^machine") or state.machines[address] then
        return "gt_machine"
    end
    return "gt_machine"
end

local function buildProxy(address)
    local mock = state.machines[address] or { active = false, hasWork = false }
    local override = state.proxyOverrides[address] or {}

    local proxy = {
        address = address,
        getName = function() return address end,
        getStoredEU = function() return 1000 end,
        getStoredPower = function() return 100 end,
        isMachineActive = function()
            if override.isMachineActive then
                return override.isMachineActive()
            end
            if mock.active ~= nil then
                return mock.active
            end
            return state.machineActive
        end,
        hasWork = function() return mock.hasWork or false end,
        isWorkAllowed = function() return true end,
        getSensorInformation = function()
            if override.getSensorInformation then
                return override.getSensorInformation()
            end
            return {
                "Progress: 0 s / 0 s",
                "Problems: 0 Efficiency: 100.0 %",
            }
        end,
        getItemsInNetwork = function(maybeSelf)
            if maybeSelf ~= nil then
                return {}
            end
            return cloneTable(state.buffer.items)
        end,
        allItems = function(maybeSelf)
            if maybeSelf ~= nil then
                return {}
            end
            return cloneTable(state.buffer.items)
        end,
        getFluidsInNetwork = function(maybeSelf)
            if maybeSelf ~= nil then
                return {}
            end
            return cloneTable(state.buffer.fluids)
        end,
        transferItem = function(...)
            if override.transferItem then
                return override.transferItem(...)
            end
            return state.transferCount
        end,
        getInventorySize = function(...)
            if override.getInventorySize then
                return override.getInventorySize(...)
            end
            return 9
        end,
        getInventoryName = function(...)
            if override.getInventoryName then
                return override.getInventoryName(...)
            end
            return nil
        end,
        get = function(_, slot)
            return { name = "minecraft:stone", size = 1, slot = slot }
        end,
        indexOf = function() return 1 end,
        getStackInSlot = function() return nil end,
        getSlotStackSize = function() return 0 end,
        getTankCount = function() return 0 end,
        setInterfaceConfiguration = function() return true end,
        clear = function() return true end,
        setOutput = function() return true end,
    }

    return proxy
end

local function installGlobals()
    _G.component = {
        doc = function(_, methodName)
            return "mock doc for " .. tostring(methodName)
        end,
        list = function(filter)
            local byType = {
                me_controller = { "me-controller" },
                database = { "database-global" },
                redstone = { "redstone-global" },
                gt_machine = { "machine-lathe", "machine-assembler" },
                me_interface = { "iface-store", "iface-stock" },
                transposer = { "transposer-001" },
            }
            local addresses = byType[filter or "gt_machine"] or {}
            local index = 0
            return function()
                index = index + 1
                if addresses[index] then
                    return addresses[index], filter or "gt_machine"
                end
            end
        end,
        methods = function(address)
            return {
                getName = false,
                getStoredEU = false,
            }
        end,
        proxy = function(address)
            return buildProxy(address)
        end,
        type = function(address)
            return resolveType(address)
        end,
        slot = function(_)
            return -1
        end,
        get = function(address, type)
            if resolveType(address) then
                return address
            end
            return nil, "component not found"
        end,
        isAvailable = function(type)
            return type == "gt_machine" or type == "me_controller" or type == "transposer"
        end,
        getPrimary = function(type)
            return buildProxy("machine-lathe")
        end,
        setPrimary = function() end,
        invoke = function(address, method, ...)
            local proxy = buildProxy(address)
            if not proxy then
                return nil
            end
            local fn = proxy[method]
            if type(fn) ~= "function" then
                local mt = type(fn) == "table" and getmetatable(fn) or nil
                if not (mt and type(mt.__call) == "function") then
                    return nil
                end
            end
            local args = { ... }
            local nargs = select("#", ...)
            if nargs == 0 then
                return fn()
            end
            return fn(unpack(args))
        end,
    }

    _G.internet = {
        request = function(url, body)
            local done = false
            return function()
                if done then
                    return nil
                end
                done = true
                local response = { assignments = cloneTable(state.cloudAssignments) }
                if #state.cloudAssignments == 0 and type(body) == "string" and body:find("iron_ingot") then
                    table.insert(response.assignments, {
                        jobId = "job-cloud-001",
                        machineAddress = "machine-lathe",
                        registry = {
                            machineAddress = "machine-lathe",
                            transposerAddress = "transposer-001",
                            storeInterfaceAddress = "iface-store",
                            stockInterfaceAddress = "iface-stock",
                            databaseAddress = "db-001",
                            sides = { transposerStore = 1, transposerStock = 2 },
                        },
                        sequenceFlow = {
                            items = { { name = "minecraft:iron_ingot", count = 64 } },
                            fluids = {},
                            steps = {
                                { type = "wait", target = "machineAddress", params = {} },
                                { type = "wait", target = "machineAddress", params = {} },
                            },
                        },
                    })
                end
                return JSON.encode(response)
            end
        end,
        socket = function()
            return {
                read = function() end,
                write = function() end,
                close = function() end,
            }
        end,
        open = function()
            return {
                read = function() end,
                write = function() end,
                close = function() end,
            }
        end,
    }

    package.loaded["component"] = _G.component
    package.loaded["internet"] = _G.internet

    if not os.sleep then
        os.sleep = function() end
    end
end

function mock_oc.reset()
    state.machines = cloneTable(DEFAULT_MACHINES)
    state.buffer = cloneTable(DEFAULT_BUFFER)
    state.cloudAssignments = {}
    state.machineActive = false
    state.transferCount = 4
    state.proxyOverrides = {}
    installGlobals()
end

function mock_oc.set_machine_active(addr, active)
    state.machines[addr] = state.machines[addr] or {}
    state.machines[addr].active = active
    state.machineActive = active
end

function mock_oc.set_buffer(items, fluids)
    state.buffer.items = cloneTable(items or {})
    state.buffer.fluids = cloneTable(fluids or {})
end

function mock_oc.set_cloud_response(assignments)
    state.cloudAssignments = cloneTable(assignments or {})
end

function mock_oc.set_transfer_count(count)
    state.transferCount = count
end

function mock_oc.set_proxy_override(address, overrides)
    state.proxyOverrides[address] = overrides or {}
end

function mock_oc.override_component_proxy(factoryFn)
    local oldProxy = _G.component.proxy
    _G.component.proxy = function(address, type)
        local proxy = oldProxy(address, type)
        return factoryFn(address, proxy) or proxy
    end
    package.loaded["component"] = _G.component
end

return mock_oc
