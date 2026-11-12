local compat = require("zigo.util.compat")
local closures = require("zigo.compile.closures")
local nodeLib = require("zigo.node")

local mathType = compat.mathType
local type, next, pcall, tostring = type, next, pcall, tostring
local huge = math.huge
local SAFE = 2 ^ 53
local getmetatable, rawequal = getmetatable, rawequal
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

for i = 1, #closures.fixedInts do
    leaves[closures.fixedInts[i][1]] = function(ctx, d, v)
        local lo, hi = closures.fixedBounds(d)
        local conds
        if d.strict then
            conds = { "mathType(" .. v .. ") ~= \"integer\"" }
        else
            conds = { "type(" .. v .. ") ~= \"number\"", v .. " % 1 ~= 0" }
        end
        conds[#conds + 1] = v .. " < " .. const(ctx, lo)
        conds[#conds + 1] = v .. " > " .. const(ctx, hi)
        return conds
    end
end

leaves.int64 = function(ctx, _, v)
    local lo, hi = const(ctx, -SAFE), const(ctx, SAFE)
    local reject = "type(" .. v .. ") ~= \"number\" or not (" .. v .. " >= " .. lo .. " and " .. v
        .. " <= " .. hi .. " and " .. v .. " % 1 == 0)"
    if compat.nativeInt64 then
        return { "mathType(" .. v .. ") ~= \"integer\" and (" .. reject .. ")" }
    end
    if compat.ffi then
        return { "(" .. reject .. ") and not istype(I64, " .. v .. ")" }
    end
    return { reject }
end

leaves.bytes = leaves.string

leaves.utf8 = function(ctx, d, v)
    local n = fresh(ctx, "u")
    add(ctx, "local " .. n .. " = type(" .. v .. ") == \"string\" and " .. const(ctx, compat.utf8Length) .. "(" .. v .. ")")
    local conds = { "not " .. n }
    bounds(ctx, n, d, conds)
    return conds
end

leaves.boolean = function(_, _, v)
    return { "(" .. v .. " ~= true and " .. v .. " ~= false)" }
end

leaves.literal = function(ctx, d, v)
    if compat.ffi then
        return { "not rawequal(" .. v .. ", " .. literalExpr(ctx, d.value) .. ")" }
    end
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

leaves.null = function(ctx, d, v)
    return { "not rawequal(" .. v .. ", " .. const(ctx, d.value) .. ")" }
end

leaves.func = function(_, _, v)
    return { "type(" .. v .. ") ~= \"function\"" }
end

leaves.userdata = function(ctx, d, v)
    local conds = { "type(" .. v .. ") ~= \"userdata\"" }
    if d.mt ~= nil then
        conds[2] = "not rawequal(getmetatable(" .. v .. "), " .. const(ctx, d.mt) .. ")"
    end
    return conds
end

leaves.instanceOf = function(ctx, d, v)
    return {
        "(type(" .. v .. ") ~= \"table\" and type(" .. v .. ") ~= \"userdata\")",
        "not rawequal(getmetatable(" .. v .. "), " .. const(ctx, d.mt) .. ")",
    }
end

local function delegated(kind)
    return function(ctx, d, v)
        if not compat.istype then return { "true" } end
        return { "not " .. const(ctx, closures.testBuilders[kind](d)) .. "(" .. v .. ")" }
    end
end

leaves.cdata = delegated("cdata")
leaves.notNullPtr = delegated("notNullPtr")

local gen, build

local function limitExpr(ctx, value)
    if value ~= huge and value % 1 == 0 and value < 1e15 then return format("%d", value) end
    return const(ctx, value)
end

local function dArg(ctx, s)
    if not ctx.dyn then return "" end
    if s > 0 then return ", D + " .. s end
    return ", D"
end

local function slowCall(ctx)
    if ctx.dyn then return "slow(v, D)" end
    return "slow(v)"
end

local function depthGuard(ctx, s)
    if not ctx.dyn then return end
    local at = s > 0 and ("D + " .. s) or "D"
    add(ctx, "if " .. at .. " >= " .. limitExpr(ctx, ctx.lim.maxDepth) .. " then return false end")
end

local function tableGuard(ctx, d, v)
    add(ctx, "if type(" .. v .. ") ~= \"table\" then return false end")
    if not d.meta then
        add(ctx, "if getmetatable(" .. v .. ") ~= nil then return " .. slowCall(ctx) .. " end")
    end
end

local pointerKinds = { cdata = true, notNullPtr = true }

local function skipGuard(ctx, d, v, kind)
    local present = v .. " ~= nil"
    if compat.ffi and pointerKinds[kind] then present = "not rawequal(" .. v .. ", nil)" end
    if d.nullable then
        local sentinel = "not rawequal(" .. v .. ", " .. const(ctx, d.nullValue) .. ")"
        if d.optional then return present .. " and " .. sentinel end
        return sentinel
    end
    if d.optional then return present end
end

local function rejectsNil(node)
    return not node.d.optional and node.kind ~= "any" and node.kind ~= "unknown"
        and node.kind ~= "union" and node.kind ~= "lazy"
end

containers.object = function(ctx, d, v, s)
    depthGuard(ctx, s)
    tableGuard(ctx, d, v)
    local keys, children = d.keys, d.children
    for i = 1, #keys do
        local f = fresh(ctx, "f")
        local mark = ctx.nl
        add(ctx, "do local " .. f .. " = " .. v .. "[" .. quote(keys[i]) .. "]")
        local opened = ctx.nl
        gen(ctx, children[i], f, s + 1)
        if ctx.nl == opened then
            ctx.nl = mark
        else
            add(ctx, "end")
        end
    end
    if d.strict then
        local k = fresh(ctx, "y")
        local maxKeys = ctx.lim.maxKeys
        if #keys > maxKeys then
            local c = fresh(ctx, "c")
            add(ctx, "local " .. c .. " = 0")
            add(ctx, "for " .. k .. " in next, " .. v .. " do " .. c .. " = " .. c .. " + 1 if " .. c .. " > "
                .. limitExpr(ctx, maxKeys) .. " or not " .. const(ctx, d.known) .. "[" .. k .. "] then return false end end")
        else
            add(ctx, "for " .. k .. " in next, " .. v .. " do if not "
                .. const(ctx, d.known) .. "[" .. k .. "] then return false end end")
        end
    end
end

containers.array = function(ctx, d, v, s)
    depthGuard(ctx, s)
    tableGuard(ctx, d, v)
    local n, i, e = fresh(ctx, "n"), fresh(ctx, "i"), fresh(ctx, "e")
    local conds = {}
    bounds(ctx, n, { min = d.min, max = closures.arrayMax(d, ctx.lim.maxKeys), len = d.len }, conds)
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
    gen(ctx, d.item, e, s + 1)
    add(ctx, "end")
end

local function variantTest(ctx, node)
    if node.d.limits ~= nil then
        return nodeLib.sub(node, ctx.dyn and "_testD" or "_test", ctx.lim)
    end
    local fn = build(node, ctx.lim, ctx.dyn)
    if not fn then error("zigo: codegen failed for a union variant") end
    return fn
end

containers.union = function(ctx, d, v, s)
    local calls = {}
    local extra = dArg(ctx, s)
    for i = 1, #d.variants do
        calls[i] = const(ctx, variantTest(ctx, d.variants[i])) .. "(" .. v .. extra .. ")"
    end
    add(ctx, "if not (" .. concat(calls, " or ") .. ") then return false end")
end

containers.discriminatedUnion = function(ctx, d, v, s)
    add(ctx, "if type(" .. v .. ") ~= \"table\" then return false end")
    if not d.meta then
        add(ctx, "if getmetatable(" .. v .. ") ~= nil then return " .. slowCall(ctx) .. " end")
    end
    local dispatch = {}
    for i = 1, #d.values do dispatch[d.values[i]] = variantTest(ctx, d.variants[i]) end
    local t = fresh(ctx, "u")
    add(ctx, "do local " .. t .. " = " .. const(ctx, dispatch) .. "[" .. v .. "[" .. quote(d.key) .. "]]")
    add(ctx, "if " .. t .. " == nil or not " .. t .. "(" .. v .. dArg(ctx, s) .. ") then return false end end")
end

containers.tuple = function(ctx, d, v, s)
    depthGuard(ctx, s)
    tableGuard(ctx, d, v)
    local items, rest = d.items, d.rest
    local count = #items
    local n = fresh(ctx, "n")
    add(ctx, "local " .. n .. " = #" .. v)
    local limitN = closures.tupleMax(d, ctx.lim.maxKeys)
    if limitN then
        add(ctx, "if " .. n .. " > " .. limitExpr(ctx, limitN) .. " then return false end")
    end
    if not d.meta then
        local c = fresh(ctx, "c")
        add(ctx, "local " .. c .. " = 0")
        add(ctx, "for _ in next, " .. v .. " do " .. c .. " = " .. c .. " + 1 if " .. c .. " > " .. n
            .. " then return false end end")
        add(ctx, "if " .. c .. " ~= " .. n .. " then return false end")
    end
    local hole = fresh(ctx, "i")
    add(ctx, "for " .. hole .. " = 1, " .. n .. " do if " .. v .. "[" .. hole .. "] == nil then return false end end")
    for i = 1, count do
        local f = fresh(ctx, "f")
        local mark = ctx.nl
        add(ctx, "do local " .. f .. " = " .. v .. "[" .. i .. "]")
        local opened = ctx.nl
        gen(ctx, items[i], f, s + 1)
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
        gen(ctx, rest, e, s + 1)
        if ctx.nl == opened then
            ctx.nl = mark
        else
            add(ctx, "end")
        end
    end
end

containers.record = function(ctx, d, v, s)
    depthGuard(ctx, s)
    add(ctx, "if type(" .. v .. ") ~= \"table\" then return false end")
    local k, x, t, c = fresh(ctx, "k"), fresh(ctx, "x"), fresh(ctx, "t"), fresh(ctx, "c")
    add(ctx, "local " .. c .. " = 0")
    add(ctx, "for " .. k .. ", " .. x .. " in next, " .. v .. " do")
    add(ctx, c .. " = " .. c .. " + 1 if " .. c .. " > " .. limitExpr(ctx, ctx.lim.maxKeys) .. " then return false end")
    add(ctx, "local " .. t .. " = type(" .. k .. ")")
    add(ctx, "if " .. t .. " ~= \"string\" and " .. t .. " ~= \"number\" and " .. t
        .. " ~= \"boolean\" then return false end")
    gen(ctx, d.key, k, s + 1)
    gen(ctx, d.value, x, s + 1)
    add(ctx, "end")
end

containers.lazy = function(ctx, d, v, s)
    local call = const(ctx, closures.lazyTest(d, ctx.lim, ctx.dyn))
    add(ctx, "if not " .. call .. "(" .. v .. dArg(ctx, s) .. ") then return false end")
end

gen = function(ctx, node, v, s)
    local kind, d = node.kind, node.d
    local leaf = leaves[kind]
    if leaf then
        local conds = leaf(ctx, d, v)
        if #conds == 0 then return end
        local cond = concat(conds, " or ")
        local guard = skipGuard(ctx, d, v, kind)
        if guard then
            add(ctx, "if " .. guard .. " and (" .. cond .. ") then return false end")
        else
            add(ctx, "if " .. cond .. " then return false end")
        end
        return
    end
    local container = containers[kind]
    if not container then
        error("zigo: no codegen for kind '" .. tostring(kind) .. "'")
    end
    if d.limits ~= nil and node ~= ctx.root then
        local fn = nodeLib.sub(node, ctx.dyn and "_testD" or "_test", ctx.lim)
        add(ctx, "if not " .. const(ctx, fn) .. "(" .. v .. dArg(ctx, s) .. ") then return false end")
        return
    end
    local guard = skipGuard(ctx, d, v, kind)
    if guard then add(ctx, "if " .. guard .. " then") end
    container(ctx, d, v, s)
    if guard then add(ctx, "end") end
end

function build(node, lim, dyn)
    local loader = loadstring or load
    if not loader then return nil end
    local ctx = { lines = {}, nl = 0, consts = {}, nc = 0, index = {}, uid = 0, lim = lim, dyn = dyn, root = node }
    gen(ctx, node, "v", 0)
    local reference
    local function slow(root, D)
        if not reference then reference = closures.test(node, lim, dyn) end
        return reference(root, D)
    end
    local head = { "local KT, type, next, getmetatable, mathType, slow, istype, I64, rawequal = ..." }
    local inline = ctx.nc < MAX_INLINE_CONSTS and ctx.nc or MAX_INLINE_CONSTS
    if inline > 0 then
        local names, values = {}, {}
        for i = 1, inline do
            names[i] = "K" .. i
            values[i] = "KT[" .. i .. "]"
        end
        head[#head + 1] = "local " .. concat(names, ", ") .. " = " .. concat(values, ", ")
    end
    if dyn then
        head[#head + 1] = "return function(v, D)\nD = D or 0"
    else
        head[#head + 1] = "return function(v)"
    end
    local body = concat(ctx.lines, "\n", 1, ctx.nl)
    local src = concat(head, "\n") .. "\n" .. body .. "\nreturn true\nend"
    local chunk = loader(src, "=zigo.codegen")
    if not chunk then return nil end
    return chunk(ctx.consts, type, next, getmetatable, mathType, slow, compat.istype, compat.int64Type, rawequal)
end

function M.test(node, lim, dyn)
    lim = lim or node._limits
    if enabled then
        local ok, fn = pcall(build, node, lim, dyn)
        if ok and fn then
            generated[fn] = true
            return fn
        end
    end
    return closures.test(node, lim, dyn)
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
