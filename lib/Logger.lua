---@meta _
---@brief Local console logging facade with leveled, tagged lines.
---@class Logger
---@field configure fun(opts?: { level?: string })
---@field debug fun(tag: string, ...)
---@field info fun(tag: string, ...)
---@field warn fun(tag: string, ...)
---@field error fun(tag: string, ...)

local Logger = {}

local LEVEL_RANK = {
    debug = 1,
    info = 2,
    warn = 3,
    error = 4,
}

local LEVEL_LABEL = {
    debug = "DEBUG",
    info = "INFO",
    warn = "WARN",
    error = "ERROR",
}

local minRank = LEVEL_RANK.info

local function joinMessage(...)
    local n = select("#", ...)
    if n == 0 then
        return ""
    end
    local parts = {}
    for i = 1, n do
        parts[i] = tostring(select(i, ...))
    end
    return table.concat(parts, " ")
end

local function emit(level, tag, ...)
    local rank = LEVEL_RANK[level]
    if not rank or rank < minRank then
        return
    end
    local label = LEVEL_LABEL[level]
    local message = joinMessage(...)
    if message == "" then
        print(string.format("[%s][%s]", label, tostring(tag)))
    else
        print(string.format("[%s][%s] %s", label, tostring(tag), message))
    end
end

---Set the active minimum level. Missing/nil level defaults to info.
---@param opts? { level?: string }
---@return nil
function Logger.configure(opts)
    opts = opts or {}
    local level = opts.level
    if level == nil then
        minRank = LEVEL_RANK.info
        return
    end
    local rank = LEVEL_RANK[level]
    if not rank then
        minRank = LEVEL_RANK.info
        emit("warn", "Logger", "unknown log level:", tostring(level), "- falling back to info")
        return
    end
    minRank = rank
end

function Logger.debug(tag, ...)
    emit("debug", tag, ...)
end

function Logger.info(tag, ...)
    emit("info", tag, ...)
end

function Logger.warn(tag, ...)
    emit("warn", tag, ...)
end

function Logger.error(tag, ...)
    emit("error", tag, ...)
end

return Logger
