local node = require("zigo.node")

local M = {}

local function analyze(d)
    local pure, depth = true, 0
    local variants = d.variants
    for i = 1, #variants do
        local variant = variants[i]
        if not variant.pure then pure = false end
        if variant.maxDepth > depth then depth = variant.maxDepth end
    end
    return pure, depth + 1
end

node.defineKind("union", { analyze = analyze })
node.defineKind("discriminatedUnion", { analyze = analyze })

function M.union(...)
    local n = select("#", ...)
    if n == 0 then
        error("zigo: union() expects at least one schema", 2)
    end
    local variants = {}
    for i = 1, n do
        local variant = select(i, ...)
        if not node.isNode(variant) then
            error("zigo: union() argument " .. i .. " is not a schema", 2)
        end
        variants[i] = variant
    end
    return node.new("union", { variants = variants })
end

local function discriminantOf(variant, key, position)
    if variant.kind ~= "object" then
        error("zigo: discriminatedUnion() variant " .. position .. " is not an object schema", 3)
    end
    local d = variant.d
    if d.optional or d.nullable or d.hasDefault then
        error("zigo: discriminatedUnion() variant " .. position .. " must not be optional, nullable or have a default", 3)
    end
    for i = 1, #d.keys do
        if d.keys[i] == key then
            local child = d.children[i]
            if child.kind ~= "literal" or not child.pure or child.d.optional or child.d.nullable then
                error("zigo: discriminatedUnion() variant " .. position .. " must have a plain literal at '" .. key .. "'", 3)
            end
            return child.d.value
        end
    end
    error("zigo: discriminatedUnion() variant " .. position .. " has no field '" .. key .. "'", 3)
end

function M.discriminatedUnion(key, ...)
    if type(key) ~= "string" then
        error("zigo: discriminatedUnion() expects the discriminant key as a string", 2)
    end
    local n = select("#", ...)
    if n == 0 then
        error("zigo: discriminatedUnion() expects at least one object schema", 2)
    end
    local variants, values, seen, meta = {}, {}, {}, false
    for i = 1, n do
        local variant = select(i, ...)
        if not node.isNode(variant) then
            error("zigo: discriminatedUnion() argument " .. i + 1 .. " is not a schema", 2)
        end
        local value = discriminantOf(variant, key, i)
        if seen[value] then
            error("zigo: discriminatedUnion() variants " .. seen[value] .. " and " .. i .. " share a discriminant value", 2)
        end
        seen[value] = i
        variants[i] = variant
        values[i] = value
        if variant.d.meta then meta = true end
    end
    return node.new("discriminatedUnion", { key = key, variants = variants, values = values, meta = meta })
end

return M
