local compat = require("zigo.util.compat")
local node = require("zigo.node")
local closures = require("zigo.compile.closures")
local context = require("zigo.compile.context")

local rawlen = compat.rawlen
local emit, describe = closures.emit, closures.describe
local inBounds, checkBounds = closures.inBounds, closures.checkBounds
local isSequence, holeFree = closures.isSequence, closures.holeFree
local reportUnknownKeys, indexGet = closures.reportUnknownKeys, closures.indexGet
local gotValue, copyList, keyRank = closures.gotValue, closures.copyList, closures.keyRank
local collectKeys, reportExotic, emitUnion = closures.collectKeys, closures.reportExotic, closures.emitUnion
local full = closures.full
local sub = node.sub
local type, next, rawget, tostring, tonumber = type, next, rawget, tostring, tonumber
local find = string.find
local huge = math.huge

local M = {}

local structural = {}
local coercers = {}

local TWIN_DROP = {
    optional = true, chain = true, hasDefault = true, default = true,
    nilKind = true, nilAt = true, coerce = true, strip = true,
}

local function fail(ctx, depth, code, expected, got, typ)
    if ctx.collect then
        ctx.issues = emit(ctx.issues, ctx.path, depth, code, expected, got, typ)
    end
    return false
end

local function toNumber(v)
    local t = type(v)
    if t == "number" then return true, v end
    if t == "string" and not find(v, "[%s%c]") then
        local n = tonumber(v)
        if n ~= nil and n == n and n ~= huge and n ~= -huge then return true, n end
    end
    return false
end

coercers.number = toNumber
coercers.integer = toNumber

coercers.boolean = function(v)
    if v == true or v == "true" or v == 1 or v == "1" then return true, true end
    if v == false or v == "false" or v == 0 or v == "0" then return true, false end
    return false
end

coercers.string = function(v)
    local t = type(v)
    if t == "string" then return true, v end
    if t == "number" then
        if v ~= v or v == huge or v == -huge then return false end
        return true, tostring(v)
    end
    if t == "boolean" then return true, tostring(v) end
    return false
end

structural.object = function(self, lim)
    local d = self.d
    local keys, children, known, strict, strip = d.keys, d.children, d.known, d.strict, d.strip
    local n = #keys
    local get = d.meta and indexGet or rawget
    local maxDepth, maxKeys = lim.maxDepth, lim.maxKeys
    local kids = {}
    for i = 1, n do kids[i] = sub(children[i], "_parse", lim) end
    return function(v, ctx, depth)
        if depth >= maxDepth then
            return fail(ctx, depth, "too_deep", maxDepth)
        end
        if type(v) ~= "table" then
            return fail(ctx, depth, "invalid_type", "object", describe(v))
        end
        local collect = ctx.collect
        local path = ctx.path
        local out = {}
        if not strip and not strict then
            for k, x in next, v do out[k] = x end
        end
        local ok = true
        local nd = depth + 1
        for i = 1, n do
            local key = keys[i]
            if collect then path[nd] = key end
            local cok, cv = kids[i](get(v, key), ctx, nd)
            if cok then
                out[key] = cv
            elseif collect then
                ok = false
                if full(ctx.issues, path.cap) then return false end
            else
                return false
            end
        end
        if strict then
            local c = 0
            for k in next, v do
                c = c + 1
                if c > maxKeys then
                    if collect then
                        ctx.issues = emit(ctx.issues, path, depth, "too_many_keys", maxKeys)
                        ok = false
                        break
                    end
                    return false
                end
                if not known[k] then
                    if collect then
                        ctx.issues = reportUnknownKeys(v, known, path, depth, ctx.issues, maxKeys)
                        ok = false
                        break
                    end
                    return false
                end
            end
        end
        if not ok then return false end
        return true, out
    end
end

structural.array = function(self, lim)
    local d = self.d
    local min, max, len, meta = d.min, d.max, d.len, d.meta
    local maxDepth, maxKeys = lim.maxDepth, lim.maxKeys
    local item = sub(d.item, "_parse", lim)
    local get = meta and indexGet or rawget
    return function(v, ctx, depth)
        if depth >= maxDepth then
            return fail(ctx, depth, "too_deep", maxDepth)
        end
        if type(v) ~= "table" then
            return fail(ctx, depth, "invalid_type", "array", describe(v))
        end
        local n, sequence
        if meta then n = #v else n = rawlen(v) end
        if n > maxKeys then
            return fail(ctx, depth, "too_many_keys", maxKeys, n, "array")
        end
        if meta then
            sequence = holeFree(v, n)
        else
            sequence = isSequence(v, n)
        end
        if not sequence then
            return fail(ctx, depth, "invalid_array", "sequence", "table")
        end
        local collect = ctx.collect
        local path = ctx.path
        local ok = true
        if not inBounds(n, min, max, len) then
            if not collect then return false end
            ctx.issues = checkBounds(n, min, max, len, "array", ctx.issues, path, depth)
            ok = false
        end
        local out = {}
        local nd = depth + 1
        for i = 1, n do
            if collect then path[nd] = i end
            local cok, cv = item(get(v, i), ctx, nd)
            if cok then
                out[i] = cv
            elseif collect then
                ok = false
                if full(ctx.issues, path.cap) then return false end
            else
                return false
            end
        end
        if not ok then return false end
        return true, out
    end
end

structural.union = function(self, lim)
    local variants = self.d.variants
    local n = #variants
    local kids = {}
    for i = 1, n do kids[i] = sub(variants[i], "_parse", lim) end
    return function(v, ctx, depth)
        if not ctx.collect then
            for i = 1, n do
                local ok, out = kids[i](v, ctx, depth)
                if ok then return true, out end
            end
            return false
        end
        local saved = ctx.issues
        if ctx.path.cap == 1 then
            ctx.collect = false
            for i = 1, n do
                local ok, out = kids[i](v, ctx, depth)
                if ok then
                    ctx.collect = true
                    return true, out
                end
            end
            ctx.collect = true
            ctx.issues = emitUnion(saved, ctx.path, depth, nil)
            return false
        end
        local lists = {}
        for i = 1, n do
            ctx.issues = nil
            local ok, out = kids[i](v, ctx, depth)
            if ok then
                ctx.issues = saved
                return true, out
            end
            lists[i] = ctx.issues or {}
        end
        ctx.issues = emitUnion(saved, ctx.path, depth, lists)
        return false
    end
end

structural.discriminatedUnion = function(self, lim)
    local d = self.d
    local key, values, variants = d.key, d.values, d.variants
    local get = d.meta and indexGet or rawget
    local map = {}
    for i = 1, #values do map[values[i]] = sub(variants[i], "_parse", lim) end
    return function(v, ctx, depth)
        if type(v) ~= "table" then
            return fail(ctx, depth, "invalid_type", "object", describe(v))
        end
        local x = get(v, key)
        local parseVariant = map[x]
        if parseVariant == nil then
            if ctx.collect then
                local nd = depth + 1
                ctx.path[nd] = key
                ctx.issues = emit(ctx.issues, ctx.path, nd, "invalid_union_discriminator", copyList(values), gotValue(x))
            end
            return false
        end
        return parseVariant(v, ctx, depth)
    end
end

structural.tuple = function(self, lim)
    local d = self.d
    local items, meta = d.items, d.meta
    local count = #items
    local maxDepth, maxKeys = lim.maxDepth, lim.maxKeys
    local kids = {}
    for i = 1, count do kids[i] = sub(items[i], "_parse", lim) end
    local rest = d.rest and sub(d.rest, "_parse", lim)
    local get = meta and indexGet or rawget
    return function(v, ctx, depth)
        if depth >= maxDepth then
            return fail(ctx, depth, "too_deep", maxDepth)
        end
        if type(v) ~= "table" then
            return fail(ctx, depth, "invalid_type", "tuple", describe(v))
        end
        local n, sequence
        if meta then n = #v else n = rawlen(v) end
        if n > maxKeys then
            return fail(ctx, depth, "too_many_keys", maxKeys, n, "array")
        end
        if meta then
            sequence = holeFree(v, n)
        else
            sequence = isSequence(v, n)
        end
        if not sequence then
            return fail(ctx, depth, "invalid_array", "sequence", "table")
        end
        local collect = ctx.collect
        local path = ctx.path
        local ok = true
        if n > count and not rest then
            if not collect then return false end
            ctx.issues = emit(ctx.issues, path, depth, "too_big", count, n, "array")
            ok = false
        end
        local out = {}
        local nd = depth + 1
        for i = 1, count do
            if collect then path[nd] = i end
            local cok, cv = kids[i](get(v, i), ctx, nd)
            if cok then
                out[i] = cv
            elseif collect then
                ok = false
                if full(ctx.issues, path.cap) then return false end
            else
                return false
            end
        end
        if rest then
            for i = count + 1, n do
                if collect then path[nd] = i end
                local cok, cv = rest(get(v, i), ctx, nd)
                if cok then
                    out[i] = cv
                elseif collect then
                    ok = false
                    if full(ctx.issues, path.cap) then return false end
                else
                    return false
                end
            end
        end
        if not ok then return false end
        return true, out
    end
end

structural.record = function(self, lim)
    local d = self.d
    local maxDepth, maxKeys = lim.maxDepth, lim.maxKeys
    local testKey = lim.tracked and "_testD" or "_test"
    local keyTest, keyCheck = sub(d.key, testKey, lim), sub(d.key, "_check", lim)
    local value = sub(d.value, "_parse", lim)
    return function(v, ctx, depth)
        if depth >= maxDepth then
            return fail(ctx, depth, "too_deep", maxDepth)
        end
        if type(v) ~= "table" then
            return fail(ctx, depth, "invalid_type", "record", describe(v))
        end
        local out = {}
        local nd = depth + 1
        if not ctx.collect then
            local c = 0
            for k, x in next, v do
                c = c + 1
                if c > maxKeys or not keyRank[type(k)] or not keyTest(k, nd) then return false end
                local ok, cv = value(x, ctx, nd)
                if not ok then return false end
                out[k] = cv
            end
            return true, out
        end
        local path = ctx.path
        local list, n, exotic, over = collectKeys(v, maxKeys)
        if over then
            ctx.issues = emit(ctx.issues, path, depth, "too_many_keys", maxKeys)
            return false
        end
        local ok = true
        for i = 1, n do
            local k = list[i]
            path[nd] = k
            if not keyTest(k, nd) then
                ctx.issues = keyCheck(k, path, nd, ctx.issues)
                ok = false
            end
            local cok, cv = value(rawget(v, k), ctx, nd)
            if cok then
                out[k] = cv
            else
                ok = false
            end
            if full(ctx.issues, path.cap) then return false end
        end
        if exotic then
            ctx.issues = reportExotic(exotic, path, depth, ctx.issues)
            ok = false
        end
        if not ok then return false end
        return true, out
    end
end

local function allPure(list)
    for i = 1, #list do
        if not list[i].pure then return false end
    end
    return true
end

local needing = {}

needing.object = function(d)
    return d.strip == true or not allPure(d.children)
end

needing.array = function(d)
    return not d.item.pure
end

needing.tuple = function(d)
    return not allPure(d.items) or (d.rest ~= nil and not d.rest.pure)
end

needing.record = function(d)
    return not d.value.pure
end

needing.union = function(d)
    return not allPure(d.variants)
end

needing.discriminatedUnion = needing.union

local function needsStructure(self)
    return needing[self.kind](self.d)
end

local function twinOf(self)
    local d = {}
    for k, v in pairs(self.d) do
        if not TWIN_DROP[k] then d[k] = v end
    end
    return node.new(self.kind, d)
end

local function buildBase(self, lim)
    local build = structural[self.kind]
    if build and needsStructure(self) then return build(self, lim) end
    local twin = twinOf(self)
    local test = sub(twin, lim.tracked and "_testD" or "_test", lim)
    local check = sub(twin, "_check", lim)
    local inner = function(v, ctx, depth)
        if test(v, depth) then return true, v end
        if ctx.collect then ctx.issues = check(v, ctx.path, depth, ctx.issues) end
        return false
    end
    local coerce = self.d.coerce and coercers[self.kind]
    if not coerce then return inner end
    local expected = self.kind
    return function(v, ctx, depth)
        local ok, converted = coerce(v)
        if not ok then
            return fail(ctx, depth, "invalid_type", expected, describe(v))
        end
        return inner(converted, ctx, depth)
    end
end

local function buildStep(step, lim)
    local op = step.op
    if op == "pipe" then return sub(step.schema, "_parse", lim) end
    local fn = step.fn
    if op == "transform" then
        return function(x, ctx, depth)
            ctx.depth = depth
            local before = ctx.count
            local y = fn(x, ctx)
            if ctx.count ~= before then return false end
            return true, y
        end
    end
    local issue = step.issue
    return function(x, ctx, depth)
        ctx.depth = depth
        local before = ctx.count
        local pass = fn(x, ctx)
        if ctx.count ~= before then return false end
        if not pass then
            ctx:addIssue(issue)
            return false
        end
        return true, x
    end
end

function M.build(self, lim)
    lim = lim or self._limits
    if self.pure then
        local test = sub(self, lim.tracked and "_testD" or "_test", lim)
        local check = sub(self, "_check", lim)
        return function(v, ctx, depth)
            if test(v, depth) then return true, v end
            if ctx.collect then ctx.issues = check(v, ctx.path, depth, ctx.issues) end
            return false
        end
    end
    local d = self.d
    local base = buildBase(self, lim)
    local chain = d.chain
    local count = chain and #chain or 0
    local steps = {}
    for i = 1, count do steps[i] = buildStep(chain[i], lim) end
    local nilKind, nilAt, default = d.nilKind, d.nilAt, d.default
    local defaultIsFunction = type(default) == "function"
    return function(v, ctx, depth)
        local x, ok, first
        if v == nil and nilKind then
            first = nilAt + 1
            if nilKind == "default" then
                if defaultIsFunction then x = default() else x = default end
            end
        else
            ok, x = base(v, ctx, depth)
            if not ok then return false end
            first = 1
        end
        for i = first, count do
            ok, x = steps[i](x, ctx, depth)
            if not ok then return false end
        end
        return true, x
    end
end

function M.test(self, lim)
    local parse = sub(self, "_parse", lim or self._limits)
    local fast = context.fast
    return function(v)
        return (parse(v, fast(), 0))
    end
end

function M.check(self, lim)
    local parse = sub(self, "_parse", lim or self._limits)
    local collect = context.collect
    return function(v, path, depth, errs)
        local ctx = collect(path, errs)
        ctx.depth = depth
        parse(v, ctx, depth)
        return ctx.issues
    end
end

return M
