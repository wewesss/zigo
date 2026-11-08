local compat = require("zigo.util.compat")
local nodeLib = require("zigo.node")

local mathType = compat.mathType
local isInt64, utf8Length = compat.isInt64, compat.utf8Length
local rawlen = compat.rawlen
local huge = math.huge
local type, next, rawget = type, next, rawget
local sort = table.sort
local sub = nodeLib.sub

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
    local cap = path.cap
    if cap and errs and #errs >= cap then return errs end
    local p = {}
    for i = 1, depth do p[i] = path[i] end
    local issue = { path = p, code = code, expected = expected, got = got, type = typ, exact = exact }
    if errs then
        errs[#errs + 1] = issue
        return errs
    end
    return { issue }
end

local function full(errs, cap)
    return cap ~= nil and errs ~= nil and #errs >= cap
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

local function arrayMax(d, maxKeys)
    local max = d.max
    if maxKeys == huge then return max end
    if max == nil or max > maxKeys then
        if d.len ~= nil and d.len <= maxKeys then return max end
        return maxKeys
    end
    return max
end

local function tupleMax(d, maxKeys)
    if d.rest then
        if maxKeys == huge then return nil end
        return maxKeys
    end
    local count = #d.items
    if count < maxKeys then return count end
    return maxKeys
end

local keyRank = { number = 1, string = 2, boolean = 3 }
local exoticTypes = { "function", "table", "thread", "userdata", "cdata" }

local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return keyRank[ta] < keyRank[tb] end
    if ta == "boolean" then return (not a) and b end
    return a < b
end

local function reportUnknownKeys(v, known, path, depth, errs, maxKeys)
    local list, n, exotic, total = nil, 0, nil, 0
    for k in next, v do
        total = total + 1
        if total > maxKeys then
            return emit(errs, path, depth, "too_many_keys", maxKeys)
        end
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

local function collectKeys(v, maxKeys)
    local list, n, exotic, total = nil, 0, nil, 0
    for k in next, v do
        total = total + 1
        if total > maxKeys then return nil, 0, nil, true end
        if keyRank[type(k)] then
            if not list then list = {} end
            n = n + 1
            list[n] = k
        else
            if not exotic then exotic = {} end
            exotic[type(k)] = true
        end
    end
    if list then sort(list, keyLess) end
    return list, n, exotic, false
end

local function reportExotic(exotic, path, depth, errs)
    for i = 1, #exoticTypes do
        local t = exoticTypes[i]
        if exotic[t] then
            errs = emit(errs, path, depth, "unrecognized_key", nil, t)
        end
    end
    return errs
end

local function emitUnion(errs, path, depth, lists)
    local cap = path.cap
    if cap and errs and #errs >= cap then return errs end
    local p = {}
    for i = 1, depth do p[i] = path[i] end
    local issue = { path = p, code = "invalid_union", unionErrors = lists }
    if errs then
        errs[#errs + 1] = issue
        return errs
    end
    return { issue }
end

local function strictCounted(v, known, maxKeys)
    local c = 0
    for k in next, v do
        c = c + 1
        if c > maxKeys or not known[k] then return false end
    end
    return true
end

local function resolveTarget(d)
    local target = d.target
    if target == nil then
        target = d.fn()
        if not nodeLib.isNode(target) then
            error("zigo: lazy() function must return a schema", 0)
        end
        if not target.pure then
            error("zigo: lazy() target must be a pure schema", 0)
        end
        d.target = target
    end
    return target
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

local function stringCheck(kind)
    return function(d)
        local min, max, len = d.min, d.max, d.len
        return function(v, path, depth, errs)
            if type(v) ~= "string" then
                return emit(errs, path, depth, "invalid_type", kind, describe(v))
            end
            return checkBounds(#v, min, max, len, kind, errs, path, depth)
        end
    end
end

checkBuilders.string = stringCheck("string")
testBuilders.bytes = testBuilders.string
checkBuilders.bytes = stringCheck("bytes")

local function utf8Within(d)
    local min, max, len = d.min, d.max, d.len
    if not (min or max or len) then
        return function(s) return utf8Length(s) ~= nil end
    end
    return function(s)
        local n = utf8Length(s)
        return n ~= nil and inBounds(n, min, max, len)
    end
end

testBuilders.utf8 = function(d)
    local within = utf8Within(d)
    return function(v)
        return type(v) == "string" and within(v)
    end
end

checkBuilders.utf8 = function(d)
    local min, max, len = d.min, d.max, d.len
    return function(v, path, depth, errs)
        if type(v) ~= "string" then
            return emit(errs, path, depth, "invalid_type", "utf8", describe(v))
        end
        local n = utf8Length(v)
        if n == nil then
            return emit(errs, path, depth, "invalid_type", "utf8", "bytes")
        end
        return checkBounds(n, min, max, len, "utf8", errs, path, depth)
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

local fixedInts = {
    { "u8", 0, 255 },
    { "u16", 0, 65535 },
    { "u32", 0, 4294967295 },
    { "i8", -128, 127 },
    { "i16", -32768, 32767 },
    { "i32", -2147483648, 2147483647 },
}

local function fixedBounds(d)
    local lo, hi = d.typeMin, d.typeMax
    local min, max = d.min, d.max
    if min and min > lo then lo = min end
    if max and max < hi then hi = max end
    return lo, hi
end

for i = 1, #fixedInts do
    local name = fixedInts[i][1]
    testBuilders[name] = function(d)
        local lo, hi = fixedBounds(d)
        local strict = d.strict
        return function(v)
            return isIntegerValue(v, strict) and v >= lo and v <= hi
        end
    end
    checkBuilders[name] = function(d)
        local lo, hi = fixedBounds(d)
        local strict = d.strict
        return function(v, path, depth, errs)
            if not isIntegerValue(v, strict) then
                local got = describe(v)
                if got == "number" then got = "float" end
                return emit(errs, path, depth, "invalid_type", name, got)
            end
            return checkBounds(v, lo, hi, nil, "integer", errs, path, depth)
        end
    end
end

testBuilders.int64 = function()
    return function(v) return isInt64(v) end
end

checkBuilders.int64 = function()
    return function(v, path, depth, errs)
        if not isInt64(v) then
            local got = describe(v)
            if got == "number" then got = "float" end
            return emit(errs, path, depth, "invalid_type", "int64", got)
        end
        return errs
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

testBuilders.lazy = function(d, lim, dyn)
    local key = dyn and "_testD" or "_test"
    local fn
    if dyn then
        return function(v, D)
            if not fn then fn = sub(resolveTarget(d), key, lim) end
            return fn(v, D)
        end
    end
    return function(v)
        if not fn then fn = sub(resolveTarget(d), key, lim) end
        return fn(v)
    end
end

checkBuilders.lazy = function(d, lim)
    local fn
    return function(v, path, depth, errs)
        if not fn then fn = sub(resolveTarget(d), "_check", lim) end
        return fn(v, path, depth, errs)
    end
end

testBuilders.object = function(d, lim, dyn)
    local keys, children, known, strict = d.keys, d.children, d.known, d.strict
    local n = #keys
    local get = d.meta and indexGet or rawget
    local maxDepth, maxKeys = lim.maxDepth, lim.maxKeys
    local counted = n > maxKeys
    local childKey = dyn and "_testD" or "_test"
    local tests = {}
    for i = 1, n do tests[i] = sub(children[i], childKey, lim) end
    if dyn then
        return function(v, D)
            D = D or 0
            if D >= maxDepth or type(v) ~= "table" then return false end
            local nd = D + 1
            for i = 1, n do
                if not tests[i](get(v, keys[i]), nd) then return false end
            end
            if strict then
                if counted then
                    if not strictCounted(v, known, maxKeys) then return false end
                else
                    for k in next, v do
                        if not known[k] then return false end
                    end
                end
            end
            return true
        end
    end
    return function(v)
        if type(v) ~= "table" then return false end
        for i = 1, n do
            if not tests[i](get(v, keys[i])) then return false end
        end
        if strict then
            if counted then
                if not strictCounted(v, known, maxKeys) then return false end
            else
                for k in next, v do
                    if not known[k] then return false end
                end
            end
        end
        return true
    end
end

checkBuilders.object = function(d, lim)
    local keys, children, known, strict = d.keys, d.children, d.known, d.strict
    local n = #keys
    local get = d.meta and indexGet or rawget
    local maxDepth, maxKeys = lim.maxDepth, lim.maxKeys
    local checks = {}
    for i = 1, n do checks[i] = sub(children[i], "_check", lim) end
    return function(v, path, depth, errs)
        if depth >= maxDepth then
            return emit(errs, path, depth, "too_deep", maxDepth)
        end
        if type(v) ~= "table" then
            return emit(errs, path, depth, "invalid_type", "object", describe(v))
        end
        local cap = path.cap
        local nd = depth + 1
        for i = 1, n do
            local key = keys[i]
            path[nd] = key
            errs = checks[i](get(v, key), path, nd, errs)
            if full(errs, cap) then return errs end
        end
        if strict then errs = reportUnknownKeys(v, known, path, depth, errs, maxKeys) end
        return errs
    end
end

local function holeFree(v, n)
    for i = 1, n do
        if v[i] == nil then return false end
    end
    return true
end

testBuilders.array = function(d, lim, dyn)
    local min, len, meta = d.min, d.len, d.meta
    local max = arrayMax(d, lim.maxKeys)
    local maxDepth = lim.maxDepth
    local itemTest = sub(d.item, dyn and "_testD" or "_test", lim)
    if dyn then
        return function(v, D)
            D = D or 0
            if D >= maxDepth or type(v) ~= "table" then return false end
            local n
            if meta then n = #v else n = rawlen(v) end
            if not inBounds(n, min, max, len) then return false end
            if meta then
                if not holeFree(v, n) then return false end
            elseif not isSequence(v, n) then
                return false
            end
            local nd = D + 1
            if meta then
                for i = 1, n do
                    if not itemTest(v[i], nd) then return false end
                end
            else
                for i = 1, n do
                    if not itemTest(rawget(v, i), nd) then return false end
                end
            end
            return true
        end
    end
    return function(v)
        if type(v) ~= "table" then return false end
        local n
        if meta then n = #v else n = rawlen(v) end
        if not inBounds(n, min, max, len) then return false end
        if meta then
            if not holeFree(v, n) then return false end
        elseif not isSequence(v, n) then
            return false
        end
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

checkBuilders.array = function(d, lim)
    local min, max, len, meta = d.min, d.max, d.len, d.meta
    local maxDepth, maxKeys = lim.maxDepth, lim.maxKeys
    local itemCheck = sub(d.item, "_check", lim)
    local get = meta and indexGet or rawget
    return function(v, path, depth, errs)
        if depth >= maxDepth then
            return emit(errs, path, depth, "too_deep", maxDepth)
        end
        if type(v) ~= "table" then
            return emit(errs, path, depth, "invalid_type", "array", describe(v))
        end
        local n
        if meta then n = #v else n = rawlen(v) end
        if n > maxKeys then
            return emit(errs, path, depth, "too_many_keys", maxKeys, n, "array")
        end
        local ok
        if meta then ok = holeFree(v, n) else ok = isSequence(v, n) end
        if not ok then
            return emit(errs, path, depth, "invalid_array", "sequence", "table")
        end
        errs = checkBounds(n, min, max, len, "array", errs, path, depth)
        local cap = path.cap
        local nd = depth + 1
        for i = 1, n do
            if full(errs, cap) then return errs end
            path[nd] = i
            errs = itemCheck(get(v, i), path, nd, errs)
        end
        return errs
    end
end

testBuilders.union = function(d, lim, dyn)
    local variants = d.variants
    local n = #variants
    local childKey = dyn and "_testD" or "_test"
    local tests = {}
    for i = 1, n do tests[i] = sub(variants[i], childKey, lim) end
    if dyn then
        return function(v, D)
            D = D or 0
            for i = 1, n do
                if tests[i](v, D) then return true end
            end
            return false
        end
    end
    return function(v)
        for i = 1, n do
            if tests[i](v) then return true end
        end
        return false
    end
end

checkBuilders.union = function(d, lim)
    local variants = d.variants
    local n = #variants
    local testKey = lim.tracked and "_testD" or "_test"
    local tests, checks = {}, {}
    for i = 1, n do
        tests[i] = sub(variants[i], testKey, lim)
        checks[i] = sub(variants[i], "_check", lim)
    end
    return function(v, path, depth, errs)
        for i = 1, n do
            if tests[i](v, depth) then return errs end
        end
        if path.cap == 1 then return emitUnion(errs, path, depth, nil) end
        local lists = {}
        for i = 1, n do
            lists[i] = checks[i](v, path, depth, nil) or {}
        end
        return emitUnion(errs, path, depth, lists)
    end
end

testBuilders.discriminatedUnion = function(d, lim, dyn)
    local key, values, variants = d.key, d.values, d.variants
    local get = d.meta and indexGet or rawget
    local childKey = dyn and "_testD" or "_test"
    local map = {}
    for i = 1, #values do map[values[i]] = sub(variants[i], childKey, lim) end
    if dyn then
        return function(v, D)
            if type(v) ~= "table" then return false end
            local test = map[get(v, key)]
            if test == nil then return false end
            return test(v, D or 0)
        end
    end
    return function(v)
        if type(v) ~= "table" then return false end
        local test = map[get(v, key)]
        if test == nil then return false end
        return test(v)
    end
end

checkBuilders.discriminatedUnion = function(d, lim)
    local key, values, variants = d.key, d.values, d.variants
    local get = d.meta and indexGet or rawget
    local map = {}
    for i = 1, #values do map[values[i]] = sub(variants[i], "_check", lim) end
    return function(v, path, depth, errs)
        if type(v) ~= "table" then
            return emit(errs, path, depth, "invalid_type", "object", describe(v))
        end
        local x = get(v, key)
        local check = map[x]
        if check == nil then
            local nd = depth + 1
            path[nd] = key
            return emit(errs, path, nd, "invalid_union_discriminator", copyList(values), gotValue(x))
        end
        return check(v, path, depth, errs)
    end
end

testBuilders.tuple = function(d, lim, dyn)
    local items, rest, meta = d.items, d.rest, d.meta
    local count = #items
    local limitN = tupleMax(d, lim.maxKeys)
    local maxDepth = lim.maxDepth
    local childKey = dyn and "_testD" or "_test"
    local tests = {}
    for i = 1, count do tests[i] = sub(items[i], childKey, lim) end
    local restTest = rest and sub(rest, childKey, lim)
    local get = meta and indexGet or rawget
    if dyn then
        return function(v, D)
            D = D or 0
            if D >= maxDepth or type(v) ~= "table" then return false end
            local n
            if meta then n = #v else n = rawlen(v) end
            if limitN and n > limitN then return false end
            if meta then
                if not holeFree(v, n) then return false end
            elseif not isSequence(v, n) then
                return false
            end
            local nd = D + 1
            for i = 1, count do
                if not tests[i](get(v, i), nd) then return false end
            end
            if restTest then
                for i = count + 1, n do
                    if not restTest(get(v, i), nd) then return false end
                end
            end
            return true
        end
    end
    return function(v)
        if type(v) ~= "table" then return false end
        local n
        if meta then n = #v else n = rawlen(v) end
        if limitN and n > limitN then return false end
        if meta then
            if not holeFree(v, n) then return false end
        elseif not isSequence(v, n) then
            return false
        end
        for i = 1, count do
            if not tests[i](get(v, i)) then return false end
        end
        if restTest then
            for i = count + 1, n do
                if not restTest(get(v, i)) then return false end
            end
        end
        return true
    end
end

checkBuilders.tuple = function(d, lim)
    local items, rest, meta = d.items, d.rest, d.meta
    local count = #items
    local maxDepth, maxKeys = lim.maxDepth, lim.maxKeys
    local checks = {}
    for i = 1, count do checks[i] = sub(items[i], "_check", lim) end
    local restCheck = rest and sub(rest, "_check", lim)
    local get = meta and indexGet or rawget
    return function(v, path, depth, errs)
        if depth >= maxDepth then
            return emit(errs, path, depth, "too_deep", maxDepth)
        end
        if type(v) ~= "table" then
            return emit(errs, path, depth, "invalid_type", "tuple", describe(v))
        end
        local n
        if meta then n = #v else n = rawlen(v) end
        if n > maxKeys then
            return emit(errs, path, depth, "too_many_keys", maxKeys, n, "array")
        end
        local ok
        if meta then ok = holeFree(v, n) else ok = isSequence(v, n) end
        if not ok then
            return emit(errs, path, depth, "invalid_array", "sequence", "table")
        end
        if n > count and not restCheck then
            errs = emit(errs, path, depth, "too_big", count, n, "array")
        end
        local cap = path.cap
        local nd = depth + 1
        for i = 1, count do
            if full(errs, cap) then return errs end
            path[nd] = i
            errs = checks[i](get(v, i), path, nd, errs)
        end
        if restCheck then
            for i = count + 1, n do
                if full(errs, cap) then return errs end
                path[nd] = i
                errs = restCheck(get(v, i), path, nd, errs)
            end
        end
        return errs
    end
end

testBuilders.record = function(d, lim, dyn)
    local maxDepth, maxKeys = lim.maxDepth, lim.maxKeys
    local childKey = dyn and "_testD" or "_test"
    local keyTest, valueTest = sub(d.key, childKey, lim), sub(d.value, childKey, lim)
    if dyn then
        return function(v, D)
            D = D or 0
            if D >= maxDepth or type(v) ~= "table" then return false end
            local nd = D + 1
            local c = 0
            for k, x in next, v do
                c = c + 1
                if c > maxKeys or not keyRank[type(k)] or not keyTest(k, nd) or not valueTest(x, nd) then
                    return false
                end
            end
            return true
        end
    end
    return function(v)
        if type(v) ~= "table" then return false end
        local c = 0
        for k, x in next, v do
            c = c + 1
            if c > maxKeys or not keyRank[type(k)] or not keyTest(k) or not valueTest(x) then return false end
        end
        return true
    end
end

checkBuilders.record = function(d, lim)
    local maxDepth, maxKeys = lim.maxDepth, lim.maxKeys
    local keyCheck, valueCheck = sub(d.key, "_check", lim), sub(d.value, "_check", lim)
    return function(v, path, depth, errs)
        if depth >= maxDepth then
            return emit(errs, path, depth, "too_deep", maxDepth)
        end
        if type(v) ~= "table" then
            return emit(errs, path, depth, "invalid_type", "record", describe(v))
        end
        local list, n, exotic, over = collectKeys(v, maxKeys)
        if over then
            return emit(errs, path, depth, "too_many_keys", maxKeys)
        end
        local cap = path.cap
        local nd = depth + 1
        for i = 1, n do
            if full(errs, cap) then return errs end
            local k = list[i]
            path[nd] = k
            errs = keyCheck(k, path, nd, errs)
            errs = valueCheck(rawget(v, k), path, nd, errs)
        end
        if exotic then errs = reportExotic(exotic, path, depth, errs) end
        return errs
    end
end

M.fixedInts = fixedInts
M.fixedBounds = fixedBounds
M.utf8Within = utf8Within
M.emit = emit
M.full = full
M.describe = describe
M.gotValue = gotValue
M.copyList = copyList
M.keyRank = keyRank
M.collectKeys = collectKeys
M.reportExotic = reportExotic
M.emitUnion = emitUnion
M.inBounds = inBounds
M.checkBounds = checkBounds
M.isSequence = isSequence
M.holeFree = holeFree
M.reportUnknownKeys = reportUnknownKeys
M.indexGet = indexGet
M.arrayMax = arrayMax
M.tupleMax = tupleMax
M.resolveTarget = resolveTarget

function M.lazyTest(d, lim, dyn)
    return testBuilders.lazy(d, lim, dyn)
end

function M.test(nd, lim, dyn)
    local build = testBuilders[nd.kind]
    if not build then error("zigo: no test compiler for kind '" .. tostring(nd.kind) .. "'", 2) end
    lim = lim or nd._limits
    local fn = build(nd.d, lim, dyn)
    if nd.d.optional then
        local inner = fn
        if dyn then
            return function(v, D) return v == nil or inner(v, D) end
        end
        return function(v) return v == nil or inner(v) end
    end
    return fn
end

function M.check(nd, lim)
    local build = checkBuilders[nd.kind]
    if not build then error("zigo: no check compiler for kind '" .. tostring(nd.kind) .. "'", 2) end
    lim = lim or nd._limits
    local fn = build(nd.d, lim)
    if nd.d.optional then
        local inner = fn
        return function(v, path, depth, errs)
            if v == nil then return errs end
            return inner(v, path, depth, errs)
        end
    end
    return fn
end

return M
