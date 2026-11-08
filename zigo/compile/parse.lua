local compat = require("zigo.util.compat")
local node = require("zigo.node")
local closures = require("zigo.compile.closures")
local context = require("zigo.compile.context")

local rawlen = compat.rawlen
local emit, describe = closures.emit, closures.describe
local inBounds, checkBounds = closures.inBounds, closures.checkBounds
local isSequence, holeFree = closures.isSequence, closures.holeFree
local reportUnknownKeys, indexGet = closures.reportUnknownKeys, closures.indexGet
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

local function fail(ctx, depth, code, expected, got)
    if ctx.collect then
        ctx.issues = emit(ctx.issues, ctx.path, depth, code, expected, got)
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

structural.object = function(self)
    local d = self.d
    local keys, children, known, strict, strip = d.keys, d.children, d.known, d.strict, d.strip
    local n = #keys
    local get = d.meta and indexGet or rawget
    local kids = {}
    for i = 1, n do kids[i] = children[i]._parse end
    return function(v, ctx, depth)
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
            else
                return false
            end
        end
        if strict then
            for k in next, v do
                if not known[k] then
                    if collect then
                        ctx.issues = reportUnknownKeys(v, known, path, depth, ctx.issues)
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

structural.array = function(self)
    local d = self.d
    local min, max, len, meta = d.min, d.max, d.len, d.meta
    local item = d.item._parse
    local get = meta and indexGet or rawget
    return function(v, ctx, depth)
        if type(v) ~= "table" then
            return fail(ctx, depth, "invalid_type", "array", describe(v))
        end
        local n, sequence
        if meta then
            n = #v
            sequence = holeFree(v, n)
        else
            n = rawlen(v)
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
            else
                return false
            end
        end
        if not ok then return false end
        return true, out
    end
end

local function needsStructure(self)
    local d = self.d
    if self.kind == "object" then
        if d.strip then return true end
        for i = 1, #d.children do
            if not d.children[i].pure then return true end
        end
        return false
    end
    return not d.item.pure
end

local function twinOf(self)
    local d = {}
    for k, v in pairs(self.d) do
        if not TWIN_DROP[k] then d[k] = v end
    end
    return node.new(self.kind, d)
end

local function buildBase(self)
    local build = structural[self.kind]
    if build and needsStructure(self) then return build(self) end
    local twin = twinOf(self)
    local test, check = twin._test, twin._check
    local inner = function(v, ctx, depth)
        if test(v) then return true, v end
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

local function buildStep(step)
    local op = step.op
    if op == "pipe" then return step.schema._parse end
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

function M.build(self)
    if self.pure then
        local test, check = self._test, self._check
        return function(v, ctx, depth)
            if test(v) then return true, v end
            if ctx.collect then ctx.issues = check(v, ctx.path, depth, ctx.issues) end
            return false
        end
    end
    local d = self.d
    local base = buildBase(self)
    local chain = d.chain
    local count = chain and #chain or 0
    local steps = {}
    for i = 1, count do steps[i] = buildStep(chain[i]) end
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

function M.test(self)
    local parse = self._parse
    local fast = context.fast
    return function(v)
        return (parse(v, fast(), 0))
    end
end

function M.check(self)
    local parse = self._parse
    local collect = context.collect
    return function(v, path, depth, errs)
        local ctx = collect(path, errs)
        ctx.depth = depth
        parse(v, ctx, depth)
        return ctx.issues
    end
end

return M
