---@meta _
---@brief Formats AE2 CommonNetworkAPI results into plain item and fluid snapshots.
---@version 1.0.0
---
---Does not call components or proxies; callers must fetch raw data first.
---@class NetworkSnapshotItem
---@field name string
---@field label string
---@field size integer
---@field damage integer
---@field hasTag any # Source value, or false when absent.
---@field nbt any|nil
---@field isCraftable any|nil
---@class NetworkSnapshotFluid
---@field name string
---@field label string
---@field amount integer
---@field hasTag any # Source value, or false when absent.
---@field nbt any|nil
---@field isCraftable any|nil
---@class NetworkContentsSnapshot
---@field items NetworkSnapshotItem[]
---@field fluids NetworkSnapshotFluid[]
---@class NetworkItems

local NetworkItems = {}

---Convert a numeric value to a floor integer, defaulting non-numbers to zero.
---@param value any
---@return integer value
local function toInt(value)
    if type(value) == "number" then
        return math.floor(value)
    end
    return 0
end

---Read a direct field or invoke its Java-style getter.
---Direct values take precedence. Getter exceptions are swallowed and treated as missing values.
---@param entry table|userdata|nil
---@param field string
---@return any|nil value
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

---Return whether a value exposes at least one recognizable item-stack field.
---@param entry table|userdata|nil
---@return boolean
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

---Return whether a value exposes a name/label and fluid amount.
---@param entry table|userdata|nil
---@return boolean
local function isFluidEntry(entry)
    if entry == nil then
        return false
    end

    if readField(entry, "name") == nil and readField(entry, "label") == nil then
        return false
    end

    return readField(entry, "amount") ~= nil
end

---Normalize supported collection shapes into a deduplicated entry array.
---Functions are consumed as iterators; tables and userdata are scanned as one-based arrays,
---zero-based arrays, `ipairs` sequences, and numeric-key maps. Duplicate keys are discarded.
---@param raw table|userdata|fun():any|nil
---@param isEntry fun(entry: any): boolean
---@param buildKey fun(entry: any): string
---@return any[] entries
local function iterateEntries(raw, isEntry, buildKey)
    local entries = {}
    local seen = {}

    ---Validate and append one entry unless its generated key was already seen.
    ---@param entry any
    ---@return nil
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

    ---Consume a function iterator.
    ---Generic-for exceptions are swallowed. When it yields nothing, the same function is retried
    ---as a simple null-terminated iterator, where exceptions propagate.
    ---@param iter any
    ---@return nil
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

    ---Scan the numeric entries of a table-like collection through supported indexing styles.
    ---Iteration errors in `ipairs` and `pairs` are swallowed; length/index errors outside those
    ---protected loops propagate.
    ---@param value any
    ---@return nil
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

---Normalize item-like entries, deduplicating by name/label, damage, and size.
---@param raw table|userdata|fun():any|nil
---@return any[] entries
local function iterateItemEntries(raw)
    return iterateEntries(raw, isStackEntry, function(entry)
        return tostring(readField(entry, "name") or readField(entry, "label") or "?")
            .. ":" .. tostring(readField(entry, "damage") or 0)
            .. ":" .. tostring(readField(entry, "size") or 0)
    end)
end

---Normalize fluid-like entries, deduplicating by name/label and amount.
---@param raw table|userdata|fun():any|nil
---@return any[] entries
local function iterateFluidEntries(raw)
    return iterateEntries(raw, isFluidEntry, function(entry)
        return tostring(readField(entry, "name") or readField(entry, "label") or "?")
            .. ":" .. tostring(readField(entry, "amount") or 0)
    end)
end

---Append a fluid snapshot once per name or label.
---Skips entries with no name or label and duplicate keys; an empty string is accepted as a key.
---@param fluids NetworkSnapshotFluid[]
---@param seen table<string, boolean>
---@param snapshot NetworkSnapshotFluid
---@return nil
local function addSnapshotFluid(fluids, seen, snapshot)
    local key = snapshot.name or snapshot.label
    if not key or seen[key] then
        return
    end

    seen[key] = true
    table.insert(fluids, snapshot)
end

---Convert an item-like API object to a plain snapshot.
---Missing names and labels become `"unknown"`; missing numeric fields become zero.
---@param entry table|userdata
---@return NetworkSnapshotItem snapshot
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

---Convert a fluid-like API object to a plain snapshot.
---Missing names and labels become `"unknown"`; missing amounts become zero.
---@param entry table|userdata
---@return NetworkSnapshotFluid snapshot
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

---Convert an AE2FC fluid-drop item entry to a plain fluid snapshot.
---The drop's item name is retained when present, while its nested fluid label is preferred.
---@param entry table|userdata
---@return NetworkSnapshotFluid snapshot
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
---Fluid-drop entries are omitted because `formatContents` handles them as fluids.
---@param raw table|userdata|fun():any|nil
---@return NetworkSnapshotItem[] items
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
---@param raw table|userdata|fun():any|nil
---@return NetworkSnapshotFluid[] fluids
function NetworkItems.formatFluids(raw)
    local fluids = {}

    for _, entry in ipairs(iterateFluidEntries(raw)) do
        table.insert(fluids, NetworkItems.toSnapshotFluid(entry))
    end

    return fluids
end

---Format raw item and fluid network results into a buffer snapshot.
---AE2FC fluid drops from the item result are merged with native fluids, deduplicated by name.
---@param itemsRaw table|userdata|fun():any|nil
---@param fluidsRaw table|userdata|fun():any|nil
---@return NetworkContentsSnapshot snapshot
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
---This uses item-entry recognition, which also recognizes named fluid records.
---@param raw table|userdata|fun():any|nil
---@return boolean empty
function NetworkItems.isEmpty(raw)
    return #iterateItemEntries(raw) == 0
end

return NetworkItems
