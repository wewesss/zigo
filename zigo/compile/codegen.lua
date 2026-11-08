local compat = require("zigo.util.compat")
local closures = require("zigo.compile.closures")

local mathType = compat.mathType
local type, next, pcall, tostring = type, next, pcall, tostring
local getmetatable = getmetatable
local format, concat = string.format, table.concat

local M = {}

local enabled = true
local generated = setmetatable({}, { __mode = "k" })
local MAX_INLINE_CONSTS = 40

local leaves = {}
local containers = {}

local function add(ctx, line)
    local n = ctx.nl + 1
    ctx.nl = n
    ctx.lines[n] = line
end

local function fresh(ctx, prefix)
    ctx.uid = ctx.uid + 1
    return prefix .. ctx.uid
end

local function const(ctx, value)
    local idx = ctx.index[value]
    if not idx then
        idx = ctx.nc + 1
        ctx.nc = idx
        ctx.consts[idx] = value
        ctx.index[value] = idx
    end
    if idx <= MAX_INLINE_CONSTS then return "K" .. idx end
    return "KT[" .. idx .. "]"
end

local function quote(s)
    return format("%q", s)
end

local function bounds(ctx, expr, d, conds)
    if d.min then conds[#conds + 1] = expr .. " < " .. const(ctx, d.min) end
    if d.max then conds[#conds + 1] = expr .. " > " .. const(ctx, d.max) end
    if d.len then conds[#conds + 1] = expr .. " ~= " .. const(ctx, d.len) end
end

local function literalExpr(ctx, value)
    local t = type(value)
    if t == "string" then return quote(value) end
    if t == "boolean" then return value and "true" or "false" end
    return const(ctx, value)
end

leaves.string = function(ctx, d, v)
    local conds = { "type(" .. v .. ") ~= \"string\"" }
    bounds(ctx, "#" .. v, d, conds)
    return conds
end

leaves.number = function(ctx, d, v)
    local conds = { "type(" .. v .. ") ~= \"number\"", v .. " ~= " .. v }
    bounds(ctx, v, d, conds)
    return conds
end

leaves.integer = function(ctx, d, v)
    local conds
    if d.strict then
        conds = { "mathType(" .. v .. ") ~= \"integer\"" }
    else
        conds = { "type(" .. v .. ") ~= \"number\"", v .. " % 1 ~= 0" }
    end
    bounds(ctx, v, d, conds)
    return conds
end

leaves.boolean = function(_, _, v)
    return { "type(" .. v .. ") ~= \"boolean\"" }
end

leaves.literal = function(ctx, d, v)
    return { v .. " ~= " .. literalExpr(ctx, d.value) }
end

leaves.enum = function(ctx, d, v)
    return { const(ctx, d.set) .. "[" .. v .. "] ~= true" }
end

leaves.any = function()
    return {}
end

leaves.unknown = leaves.any

leaves.never = function()
    return { "true" }
end

local gen, build

local function tableGuard(ctx, d, v)
    add(ctx, "if type(" .. v .. ") ~= \"table\" then return false end")
    if not d.meta then
        add(ctx, "if getmetatable(" .. v .. ") ~= nil then return slow(v) end")
    end
end

local function rejectsNil(node)
    return not node.d.optional and node.kind ~= "any" and node.kind ~= "unknown" and node.kind ~= "union"
end

containers.object = function(ctx, d, v)
    tableGuard(ctx, d, v)
    local keys, children = d.keys, d.children
    for i = 1, #keys do
        local f = fresh(ctx, "f")
        local mark = ctx.nl
        add(ctx, "do local " .. f .. " = " .. v .. "[" .. quote(keys[i]) .. "]")
        local opened = ctx.nl
        gen(ctx, children[i], f)
        if ctx.nl == opened then
            ctx.nl = mark
        else
            add(ctx, "end")
        end
    end
    if d.strict then
        local k = fresh(ctx, "y")
        add(ctx, "for " .. k .. " in next, " .. v .. " do if not "
            .. const(ctx, d.known) .. "[" .. k .. "] then return false end end")
    end
end

containers.array = function(ctx, d, v)
    tableGuard(ctx, d, v)
    local n, i, e = fresh(ctx, "n"), fresh(ctx, "i"), fresh(ctx, "e")
    local conds = {}
    bounds(ctx, n, d, conds)
    add(ctx, "local " .. n .. " = #" .. v)
    if #conds > 0 then
        add(ctx, "if " .. concat(conds, " or ") .. " then return false end")
    end
    if not d.meta then
        local c = fresh(ctx, "c")
        add(ctx, "local " .. c .. " = 0")
        add(ctx, "for _ in next, " .. v .. " do " .. c .. " = " .. c .. " + 1 if " .. c .. " > " .. n
            .. " then return false end end")
        add(ctx, "if " .. c .. " ~= " .. n .. " then return false end")
    end
    add(ctx, "for " .. i .. " = 1, " .. n .. " do local " .. e .. " = " .. v .. "[" .. i .. "]")
    if not rejectsNil(d.item) then
        add(ctx, "if " .. e .. " == nil then return false end")
    end
    gen(ctx, d.item, e)
    add(ctx, "end")
end

local function variantTest(node)
    local fn = build(node)
    if not fn then error("zigo: codegen failed for a union variant") end
    return fn
end

containers.union = function(ctx, d, v)
    local calls = {}
    for i = 1, #d.variants do
        calls[i] = const(ctx, variantTest(d.variants[i])) .. "(" .. v .. ")"
    end
    add(ctx, "if not (" .. concat(calls, " or ") .. ") then return false end")
end

containers.discriminatedUnion = function(ctx, d, v)
    add(ctx, "if type(" .. v .. ") ~= \"table\" then return false end")
    if not d.meta then
        add(ctx, "if getmetatable(" .. v .. ") ~= nil then return slow(v) end")
    end
    local dispatch = {}
    for i = 1, #d.values do dispatch[d.values[i]] = variantTest(d.variants[i]) end
    local t = fresh(ctx, "u")
    add(ctx, "do local " .. t .. " = " .. const(ctx, dispatch) .. "[" .. v .. "[" .. quote(d.key) .. "]]")
    add(ctx, "if " .. t .. " == nil or not " .. t .. "(" .. v .. ") then return false end end")
end

containers.tuple = function(ctx, d, v)
    tableGuard(ctx, d, v)
    local items, rest = d.items, d.rest
    local count = #items
    local n = fresh(ctx, "n")
    add(ctx, "local " .. n .. " = #" .. v)
    if d.meta then
        local i = fresh(ctx, "i")
        add(ctx, "for " .. i .. " = 1, " .. n .. " do if " .. v .. "[" .. i .. "] == nil then return false end end")
    else
        local c = fresh(ctx, "c")
        add(ctx, "local " .. c .. " = 0")
        add(ctx, "for _ in next, " .. v .. " do " .. c .. " = " .. c .. " + 1 if " .. c .. " > " .. n
            .. " then return false end end")
        add(ctx, "if " .. c .. " ~= " .. n .. " then return false end")
    end
    if not rest then
        add(ctx, "if " .. n .. " > " .. count .. " then return false end")
    end
    for i = 1, count do
        local f = fresh(ctx, "f")
        local mark = ctx.nl
        add(ctx, "do local " .. f .. " = " .. v .. "[" .. i .. "]")
        local opened = ctx.nl
        gen(ctx, items[i], f)
        if ctx.nl == opened then
            ctx.nl = mark
        else
            add(ctx, "end")
        end
    end
    if rest then
        local i, e = fresh(ctx, "i"), fresh(ctx, "e")
        local mark = ctx.nl
        add(ctx, "for " .. i .. " = " .. (count + 1) .. ", " .. n .. " do local " .. e .. " = " .. v .. "[" .. i .. "]")
        local opened = ctx.nl
        gen(ctx, rest, e)
        if ctx.nl == opened then
            ctx.nl = mark
        else
            add(ctx, "end")
        end
    end
end

containers.record = function(ctx, d, v)
    add(ctx, "if type(" .. v .. ") ~= \"table\" then return false end")
    local k, x, t = fresh(ctx, "k"), fresh(ctx, "x"), fresh(ctx, "t")
    add(ctx, "for " .. k .. ", " .. x .. " in next, " .. v .. " do")
    add(ctx, "local " .. t .. " = type(" .. k .. ")")
    add(ctx, "if " .. t .. " ~= \"string\" and " .. t .. " ~= \"number\" and " .. t
        .. " ~= \"boolean\" then return false end")
    gen(ctx, d.key, k)
    gen(ctx, d.value, x)
    add(ctx, "end")
end

gen = function(ctx, node, v)
    local kind, d = node.kind, node.d
    local leaf = leaves[kind]
    if leaf then
        local conds = leaf(ctx, d, v)
        if #conds == 0 then return end
        local cond = concat(conds, " or ")
        if d.optional then
            add(ctx, "if " .. v .. " ~= nil and (" .. cond .. ") then return false end")
        else
            add(ctx, "if " .. cond .. " then return false end")
        end
        return
    end
    local container = containers[kind]
    if not container then
        error("zigo: no codegen for kind '" .. tostring(kind) .. "'")
    end
    if d.optional then add(ctx, "if " .. v .. " ~= nil then") end
    container(ctx, d, v)
    if d.optional then add(ctx, "end") end
end

function build(node)
    local loader = loadstring or load
    if not loader then return nil end
    local ctx = { lines = {}, nl = 0, consts = {}, nc = 0, index = {}, uid = 0 }
    gen(ctx, node, "v")
    local reference
    local function slow(root)
        if not reference then reference = closures.test(node) end
        return reference(root)
    end
    local head = { "local KT, type, next, getmetatable, mathType, slow = ..." }
    local inline = ctx.nc < MAX_INLINE_CONSTS and ctx.nc or MAX_INLINE_CONSTS
    if inline > 0 then
        local names, values = {}, {}
        for i = 1, inline do
            names[i] = "K" .. i
            values[i] = "KT[" .. i .. "]"
        end
        head[#head + 1] = "local " .. concat(names, ", ") .. " = " .. concat(values, ", ")
    end
    head[#head + 1] = "return function(v)"
    local body = concat(ctx.lines, "\n", 1, ctx.nl)
    local src = concat(head, "\n") .. "\n" .. body .. "\nreturn true\nend"
    local chunk = loader(src, "=zigo.codegen")
    if not chunk then return nil end
    return chunk(ctx.consts, type, next, getmetatable, mathType, slow)
end

function M.test(node)
    if enabled then
        local ok, fn = pcall(build, node)
        if ok and fn then
            generated[fn] = true
            return fn
        end
    end
    return closures.test(node)
end

function M.setEnabled(flag)
    enabled = flag
end

function M.isEnabled()
    return enabled
end

function M.isGenerated(fn)
    return generated[fn] == true
end

return M
