local node = require("zigo.node")

local M = {}

local function leaf()
    return true, 1
end

node.defineKind("string", { analyze = leaf, methods = node.boundMethods(true) })
node.defineKind("number", { analyze = leaf, methods = node.boundMethods(false) })
node.defineKind("integer", { analyze = leaf, methods = node.boundMethods(false) })
node.defineKind("boolean", { analyze = leaf })
node.defineKind("literal", { analyze = leaf })
node.defineKind("enum", { analyze = leaf })
node.defineKind("any", { analyze = leaf })
node.defineKind("unknown", { analyze = leaf })
node.defineKind("never", { analyze = leaf })

function M.string()
    return node.new("string", {})
end

function M.number()
    return node.new("number", {})
end

function M.integer(opts)
    if opts ~= nil and type(opts) ~= "table" then
        error("zigo: integer() expects an options table", 2)
    end
    return node.new("integer", { strict = opts ~= nil and opts.strict == true })
end

function M.boolean()
    return node.new("boolean", {})
end

local function isPrimitiveLiteral(x)
    local t = type(x)
    if t == "number" then return x == x end
    return t == "string" or t == "boolean"
end

function M.literal(value)
    if not isPrimitiveLiteral(value) then
        error("zigo: literal() expects a string, a number or a boolean", 2)
    end
    return node.new("literal", { value = value })
end

function M.enum(values)
    if type(values) ~= "table" or #values == 0 then
        error("zigo: enum() expects a non-empty list", 2)
    end
    local list, set = {}, {}
    for i = 1, #values do
        local x = values[i]
        if not isPrimitiveLiteral(x) then
            error("zigo: enum() values must be strings, numbers or booleans", 2)
        end
        list[i] = x
        set[x] = true
    end
    return node.new("enum", { values = list, set = set })
end

function M.any()
    return node.new("any", {})
end

function M.unknown()
    return node.new("unknown", {})
end

function M.never()
    return node.new("never", {})
end

return M
