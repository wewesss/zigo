local type, error, pairs, tostring = type, error, pairs, tostring
local huge = math.huge

local M = {}

local kinds = {
    maxDepth = "number",
    maxKeys = "number",
    maxErrors = "number",
    abortEarly = "boolean",
}

local defaults = { maxDepth = 64, maxKeys = 10000, maxErrors = 100, abortEarly = false }

function M.isOption(name)
    return kinds[name] ~= nil
end

function M.validate(opts, who)
    if type(opts) ~= "table" then
        error("zigo: " .. who .. "() expects a table", 3)
    end
    local unknown = {}
    for k in pairs(opts) do
        if not kinds[k] then unknown[#unknown + 1] = tostring(k) end
    end
    if #unknown > 0 then
        table.sort(unknown)
        error("zigo: " .. who .. "() unknown option '" .. unknown[1] .. "'", 3)
    end
    for name, want in pairs(kinds) do
        local value = opts[name]
        if value ~= nil then
            if type(value) ~= want then
                error("zigo: " .. who .. "() option '" .. name .. "' expects a " .. want, 3)
            end
            if want == "number" and (value ~= value or value < 1 or (value ~= huge and value % 1 ~= 0)) then
                error("zigo: " .. who .. "() option '" .. name .. "' expects a positive integer", 3)
            end
        end
    end
end

function M.configure(opts)
    for name in pairs(kinds) do
        if opts[name] ~= nil then defaults[name] = opts[name] end
    end
end

function M.current()
    return {
        maxDepth = defaults.maxDepth,
        maxKeys = defaults.maxKeys,
        maxErrors = defaults.maxErrors,
        abortEarly = defaults.abortEarly,
    }
end

function M.merge(old, new)
    local out = {}
    if old then
        for k, v in pairs(old) do out[k] = v end
    end
    for k, v in pairs(new) do out[k] = v end
    return out
end

local function pick(own, name)
    if own and own[name] ~= nil then return own[name] end
    return defaults[name]
end

function M.resolve(nd)
    local own = nd.d.limits
    local maxDepth = pick(own, "maxDepth")
    local abort = pick(own, "abortEarly")
    return {
        maxDepth = maxDepth,
        maxKeys = pick(own, "maxKeys"),
        cap = abort and 1 or pick(own, "maxErrors"),
        explicit = own ~= nil,
        tracked = nd.maxDepth > maxDepth,
    }
end

return M
