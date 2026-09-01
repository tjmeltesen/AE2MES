---Format AE2 CommonNetworkAPI raw results into plain Lua tables.
---Does not call components or proxies — callers fetch raw data first.

local NetworkItems = {}

local function toInt(value)
    if type(value) == "number" then
        return math.floor(value)
    end
    return 0
end

local function readField(entry, field)
    if entry == nil then
        return nil
    end

    local value = entry[field]
    if value ~= nil then
        return value
    end

    local getterName = "get" .. field:sub(1, 1):upper() .. field:sub(2)
    local getter = entry[getterName]
    if type(getter) == "function" then
        local ok, result = pcall(getter, entry)
        if ok and result ~= nil then
            return result
        end
    end

    return nil
end

local function isStackEntry(entry)
    if entry == nil then
        return false
    end

    if entry.fluidDrop ~= nil then
        return true
    end

    if readField(entry, "name") ~= nil then
        return true
    end

    if readField(entry, "label") ~= nil then
        return true
    end

    return readField(entry, "size") ~= nil
end

local function isFluidEntry(entry)
    if entry == nil then
        return false
    end

    if readField(entry, "name") == nil and readField(entry, "label") == nil then
        return false
    end

    return readField(entry, "amount") ~= nil
end

local function iterateEntries(raw, isEntry, buildKey)
    local entries = {}
    local seen = {}

    local function add(entry)
        if not isEntry(entry) then
            return
        end

        local key = buildKey(entry)
        if seen[key] then
            return
        end

        seen[key] = true
        table.insert(entries, entry)
    end

    local function addFromIterator(iter)
        if type(iter) ~= "function" then
            return
        end

        local sawAny = false

        pcall(function()
            for entry in iter do
                sawAny = true
                add(entry)
            end
        end)

        if sawAny then
            return
        end

        while true do
            local entry = iter()
            if entry == nil then
                break
            end
            add(entry)
        end
    end

    local function addFromIndexed(value)
        if value == nil then
            return
        end

        local length = #value
        if length > 0 then
            for index = 1, length do
                add(value[index])
            end
        end

        if value[0] ~= nil then
            local index = 0
            while value[index] ~= nil do
                add(value[index])
                index = index + 1
            end
        end

        pcall(function()
            for _, entry in ipairs(value) do
                add(entry)
            end
        end)

        pcall(function()
            for key, entry in pairs(value) do
                if type(key) == "number" then
                    add(entry)
                end
            end
        end)
    end

    if raw == nil then
        return entries
    end

    if type(raw) == "function" then
        addFromIterator(raw)
        return entries
    end

    if type(raw) == "table" or type(raw) == "userdata" then
        addFromIndexed(raw)
    end

    return entries
end

local function iterateItemEntries(raw)
    return iterateEntries(raw, isStackEntry, function(entry)
        return tostring(readField(entry, "name") or readField(entry, "label") or "?")
            .. ":" .. tostring(readField(entry, "damage") or 0)
            .. ":" .. tostring(readField(entry, "size") or 0)
    end)
end

local function iterateFluidEntries(raw)
    return iterateEntries(raw, isFluidEntry, function(entry)
        return tostring(readField(entry, "name") or readField(entry, "label") or "?")
            .. ":" .. tostring(readField(entry, "amount") or 0)
    end)
end

local function addSnapshotFluid(fluids, seen, snapshot)
    local key = snapshot.name or snapshot.label
    if not key or seen[key] then
        return
    end

    seen[key] = true
    table.insert(fluids, snapshot)
end

---@param entry any
---@return table
function NetworkItems.toSnapshotItem(entry)
    return {
        name = readField(entry, "name") or "unknown",
        label = readField(entry, "label") or readField(entry, "name") or "unknown",
        size = toInt(readField(entry, "size") or 0),
        damage = toInt(readField(entry, "damage") or 0),
        hasTag = readField(entry, "hasTag") or false,
        nbt = readField(entry, "tag"),
        isCraftable = readField(entry, "isCraftable"),
    }
end

---@param entry any
---@return table
function NetworkItems.toSnapshotFluid(entry)
    return {
        name = readField(entry, "name") or readField(entry, "label") or "unknown",
        label = readField(entry, "label") or readField(entry, "name") or "unknown",
        amount = toInt(readField(entry, "amount") or 0),
        hasTag = readField(entry, "hasTag") or false,
        nbt = readField(entry, "tag"),
        isCraftable = readField(entry, "isCraftable"),
    }
end

---@param entry any
---@return table
function NetworkItems.fluidDropToSnapshot(entry)
    local fluid = entry.fluidDrop or {}
    local fluidName = readField(fluid, "name")
        or readField(fluid, "label")
        or readField(entry, "name")
        or "unknown"

    return {
        name = readField(entry, "name") or fluidName,
        label = readField(fluid, "label") or fluidName,
        amount = toInt(readField(entry, "size") or readField(fluid, "amount") or 0),
        hasTag = readField(entry, "hasTag") or false,
        nbt = readField(entry, "tag"),
    }
end

---Format a raw getItemsInNetwork / allItems result into plain item tables.
---@param raw any
---@return table
function NetworkItems.formatItems(raw)
    local items = {}

    for _, entry in ipairs(iterateItemEntries(raw)) do
        if entry.fluidDrop then
            -- fluid drops are handled in formatContents
        else
            table.insert(items, NetworkItems.toSnapshotItem(entry))
        end
    end

    return items
end

---Format a raw getFluidsInNetwork result into plain fluid tables.
---@param raw any
---@return table
function NetworkItems.formatFluids(raw)
    local fluids = {}

    for _, entry in ipairs(iterateFluidEntries(raw)) do
        table.insert(fluids, NetworkItems.toSnapshotFluid(entry))
    end

    return fluids
end

---Format raw item and fluid network results into a buffer snapshot.
---@param itemsRaw any
---@param fluidsRaw any
---@return table
function NetworkItems.formatContents(itemsRaw, fluidsRaw)
    local items = {}
    local fluids = {}
    local seenFluids = {}

    for _, entry in ipairs(iterateItemEntries(itemsRaw)) do
        if entry.fluidDrop then
            addSnapshotFluid(fluids, seenFluids, NetworkItems.fluidDropToSnapshot(entry))
        else
            table.insert(items, NetworkItems.toSnapshotItem(entry))
        end
    end

    for _, entry in ipairs(iterateFluidEntries(fluidsRaw)) do
        addSnapshotFluid(fluids, seenFluids, NetworkItems.toSnapshotFluid(entry))
    end

    return {
        items = items,
        fluids = fluids,
    }
end

---True when a raw network list has no usable entries after formatting.
---@param raw any
---@return boolean
function NetworkItems.isEmpty(raw)
    return #iterateItemEntries(raw) == 0
end

return NetworkItems
