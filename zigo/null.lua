local error, rawequal = error, rawequal

local M = {}

local default, hasDefault
local known = setmetatable({}, { __mode = "k" })

local function validate(s, who, level)
    if s ~= s then
        error("zigo: " .. who .. "() sentinel must not be NaN", level)
    end
end

function M.validate(s, who, level)
    validate(s, who, level + 1)
end

function M.setDefault(s)
    default, hasDefault = s, true
    known[s] = true
end

function M.default()
    return default
end

function M.resolve(s, who)
    if rawequal(s, nil) then
        if not hasDefault then
            error("zigo: " .. who .. "() expects a sentinel when z.config({ null = ... }) is not set", 3)
        end
        s = default
    end
    validate(s, who, 4)
    known[s] = true
    return s
end

function M.isKnown(v)
    return known[v] == true
end

return M
