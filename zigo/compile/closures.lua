local compat = require("zigo.util.compat")

local mathType = compat.mathType
local rawlen = compat.rawlen
local huge = math.huge
local type, next, rawget = type, next, rawget
local sort = table.sort

local M = {}

local testBuilders = {}
local checkBuilders = {}

local function describe(v)
    local t = type(v)
    if t == "number" then
        if v ~= v then return "nan" end
        if v == huge then return "inf" end
        if v == -huge then return "-inf" end
    end
    return t
end

local function gotValue(v)
    local t = type(v)
    if t == "string" or t == "boolean" then return v end
    if t == "number" then
        if v ~= v then return "nan" end
        return v
    end
    return t
end

local function emit(errs, path, depth, code, expected, got, typ, exact)
    local p = {}
    for i = 1, depth do p[i] = path[i] end
    local issue = { path = p, code = code, expected = expected, got = got, type = typ, exact = exact }
    if errs then
        errs[#errs + 1] = issue
        return errs
    end
    return { issue }
end

local function inBounds(x, min, max, len)
    if min and x < min then return false end
    if max and x > max then return false end
    if len and x ~= len then return false end
    return true
end

local function checkBounds(x, min, max, len, typ, errs, path, depth)
    if min and x < min then errs = emit(errs, path, depth, "too_small", min, x, typ) end
    if max and x > max then errs = emit(errs, path, depth, "too_big", max, x, typ) end
    if len and x ~= len then
        errs = emit(errs, path, depth, x < len and "too_small" or "too_big", len, x, typ, true)
    end
    return errs
end

local function copyList(list)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

local function indexGet(t, k)
    return t[k]
end

local function isSequence(v, n)
    local count = 0
    for k in next, v do
        count = count + 1
        if count > n or type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
            return false
        end
    end
    return count == n
end

local keyRank = { number = 1, string = 2, boolean = 3 }
local exoticTypes = { "function", "table", "thread", "userdata", "cdata" }

local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return keyRank[ta] < keyRank[tb] end
    if ta == "boolean" then return (not a) and b end
    return a < b
end

local function reportUnknownKeys(v, known, path, depth, errs)
    local list, n, exotic = nil, 0, nil
    for k in next, v do
        if not known[k] then
            if keyRank[type(k)] then
                if not list then list = {} end
                n = n + 1
                list[n] = k
            else
                if not exotic then exotic = {} end
                exotic[type(k)] = true
            end
        end
    end
    if list then
        sort(list, keyLess)
        local nd = depth + 1
        for i = 1, n do
            path[nd] = list[i]
            errs = emit(errs, path, nd, "unrecognized_key")
        end
    end
    if exotic then
        for i = 1, #exoticTypes do
            local t = exoticTypes[i]
            if exotic[t] then
                errs = emit(errs, path, depth, "unrecognized_key", nil, t)
            end
        end
    end
    return errs
end

testBuilders.string = function(d)
    local min, max, len = d.min, d.max, d.len
    if not (min or max or len) then
        return function(v) return type(v) == "string" end
    end
    return function(v)
        return type(v) == "string" and inBounds(#v, min, max, len)
    end
end

checkBuilders.string = function(d)
    local min, max, len = d.min, d.max, d.len
    return function(v, path, depth, errs)
        if type(v) ~= "string" then
            return emit(errs, path, depth, "invalid_type", "string", describe(v))
        end
        return checkBounds(#v, min, max, len, "string", errs, path, depth)
    end
end

testBuilders.number = function(d)
    local min, max = d.min, d.max
    return function(v)
        return type(v) == "number" and v == v and inBounds(v, min, max, nil)
    end
end

checkBuilders.number = function(d)
    local min, max = d.min, d.max
    return function(v, path, depth, errs)
        if type(v) ~= "number" or v ~= v then
            return emit(errs, path, depth, "invalid_type", "number", describe(v))
        end
        return checkBounds(v, min, max, nil, "number", errs, path, depth)
    end
end

local function isIntegerValue(v, strict)
    if type(v) ~= "number" or v ~= v or v == huge or v == -huge then return false end
    if strict then return mathType(v) == "integer" end
    return v % 1 == 0
end

testBuilders.integer = function(d)
    local min, max, strict = d.min, d.max, d.strict
    return function(v)
        return isIntegerValue(v, strict) and inBounds(v, min, max, nil)
    end
end

checkBuilders.integer = function(d)
    local min, max, strict = d.min, d.max, d.strict
    return function(v, path, depth, errs)
        if not isIntegerValue(v, strict) then
            local got = describe(v)
            if got == "number" then got = "float" end
            return emit(errs, path, depth, "invalid_type", "integer", got)
        end
        return checkBounds(v, min, max, nil, "integer", errs, path, depth)
    end
end

testBuilders.boolean = function()
    return function(v) return type(v) == "boolean" end
end

checkBuilders.boolean = function()
    return function(v, path, depth, errs)
        if type(v) ~= "boolean" then
            return emit(errs, path, depth, "invalid_type", "boolean", describe(v))
        end
        return errs
    end
end

testBuilders.literal = function(d)
    local value = d.value
    return function(v) return v == value end
end

checkBuilders.literal = function(d)
    local value = d.value
    return function(v, path, depth, errs)
        if v ~= value then
            return emit(errs, path, depth, "invalid_literal", value, gotValue(v))
        end
        return errs
    end
end

testBuilders.enum = function(d)
    local set = d.set
    return function(v) return set[v] == true end
end

checkBuilders.enum = function(d)
    local set, values = d.set, d.values
    return function(v, path, depth, errs)
        if set[v] ~= true then
            return emit(errs, path, depth, "invalid_enum", copyList(values), gotValue(v))
        end
        return errs
    end
end

testBuilders.any = function()
    return function() return true end
end

checkBuilders.any = function()
    return function(_, _, _, errs) return errs end
end

testBuilders.unknown = testBuilders.any
checkBuilders.unknown = checkBuilders.any

testBuilders.never = function()
    return function() return false end
end

checkBuilders.never = function()
    return function(v, path, depth, errs)
        return emit(errs, path, depth, "invalid_type", "never", describe(v))
    end
end

testBuilders.object = function(d)
    local keys, children, known, strict = d.keys, d.children, d.known, d.strict
    local n = #keys
    local get = d.meta and indexGet or rawget
    local tests = {}
    for i = 1, n do tests[i] = children[i]._test end
    return function(v)
        if type(v) ~= "table" then return false end
        for i = 1, n do
            if not tests[i](get(v, keys[i])) then return false end
        end
        if strict then
            for k in next, v do
                if not known[k] then return false end
            end
        end
        return true
    end
end

checkBuilders.object = function(d)
    local keys, children, known, strict = d.keys, d.children, d.known, d.strict
    local n = #keys
    local get = d.meta and indexGet or rawget
    local checks = {}
    for i = 1, n do checks[i] = children[i]._check end
    return function(v, path, depth, errs)
        if type(v) ~= "table" then
            return emit(errs, path, depth, "invalid_type", "object", describe(v))
        end
        local nd = depth + 1
        for i = 1, n do
            local key = keys[i]
            path[nd] = key
            errs = checks[i](get(v, key), path, nd, errs)
        end
        if strict then errs = reportUnknownKeys(v, known, path, depth, errs) end
        return errs
    end
end

local function holeFree(v, n)
    for i = 1, n do
        if v[i] == nil then return false end
    end
    return true
end

testBuilders.array = function(d)
    local min, max, len, meta = d.min, d.max, d.len, d.meta
    local itemTest = d.item._test
    return function(v)
        if type(v) ~= "table" then return false end
        local n
        if meta then
            n = #v
            if not holeFree(v, n) then return false end
        else
            n = rawlen(v)
            if not isSequence(v, n) then return false end
        end
        if not inBounds(n, min, max, len) then return false end
        if meta then
            for i = 1, n do
                if not itemTest(v[i]) then return false end
            end
        else
            for i = 1, n do
                if not itemTest(rawget(v, i)) then return false end
            end
        end
        return true
    end
end

checkBuilders.array = function(d)
    local min, max, len, meta = d.min, d.max, d.len, d.meta
    local itemCheck = d.item._check
    local get = meta and indexGet or rawget
    return function(v, path, depth, errs)
        if type(v) ~= "table" then
            return emit(errs, path, depth, "invalid_type", "array", describe(v))
        end
        local n, ok
        if meta then
            n = #v
            ok = holeFree(v, n)
        else
            n = rawlen(v)
            ok = isSequence(v, n)
        end
        if not ok then
            return emit(errs, path, depth, "invalid_array", "sequence", "table")
        end
        errs = checkBounds(n, min, max, len, "array", errs, path, depth)
        local nd = depth + 1
        for i = 1, n do
            path[nd] = i
            errs = itemCheck(get(v, i), path, nd, errs)
        end
        return errs
    end
end

function M.test(node)
    local build = testBuilders[node.kind]
    if not build then error("zigo: no test compiler for kind '" .. tostring(node.kind) .. "'", 2) end
    local fn = build(node.d)
    if node.d.optional then
        local inner = fn
        return function(v) return v == nil or inner(v) end
    end
    return fn
end

function M.check(node)
    local build = checkBuilders[node.kind]
    if not build then error("zigo: no check compiler for kind '" .. tostring(node.kind) .. "'", 2) end
    local fn = build(node.d)
    if node.d.optional then
        local inner = fn
        return function(v, path, depth, errs)
            if v == nil then return errs end
            return inner(v, path, depth, errs)
        end
    end
    return fn
end

return M
