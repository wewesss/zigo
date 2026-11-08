local errors = require("zigo.errors")
local context = require("zigo.compile.context")

local M = {}

local kinds = {}
local compilers = {}
local metatables = {}
local fields = setmetatable({}, { __mode = "k" })
local base = {}

local function frozen()
    error("zigo: schema nodes are immutable", 2)
end

function M.setCompiler(key, fn)
    compilers[key] = fn
end

function M.isNode(x)
    return type(x) == "table" and metatables[getmetatable(x)] == true
end

local function chainLength(d)
    local chain = d.chain
    return chain and #chain or 0
end

function M.new(kind, d)
    local def = kinds[kind]
    if not def then error("zigo: unknown node kind '" .. tostring(kind) .. "'", 2) end
    local pure, depth = def.analyze(d)
    if d.coerce or d.strip or d.hasDefault or chainLength(d) > 0 then pure = false end
    local self = setmetatable({}, pure and def.mt or def.impureMt)
    fields[self] = {
        kind = kind,
        d = d,
        pure = pure,
        maxDepth = depth,
        isOptional = d.optional == true,
    }
    return self
end

function M.derive(source, changes)
    local d = {}
    for k, v in pairs(source.d) do d[k] = v end
    for k, v in pairs(changes) do d[k] = v end
    return M.new(source.kind, d)
end

local function diagnose(parse, v)
    local ctx = context.collect({}, nil)
    parse(v, ctx, 0)
    return ctx.issues or { { path = {}, code = "custom" } }
end

local function impureSafeParse(self, v)
    local parse = self._parse
    local ok, out = parse(v, context.fast(), 0)
    if ok then return true, out end
    return false, nil, errors.new(diagnose(parse, v))
end

local function impureParse(self, v)
    local parse = self._parse
    local ok, out = parse(v, context.fast(), 0)
    if ok then return out end
    error(errors.new(diagnose(parse, v)), 2)
end

local function makeMeta(kind, methods)
    local mt = {}
    mt.__index = function(self, key)
        local own = fields[self][key]
        if own ~= nil then return own end
        local m = methods[key]
        if m ~= nil then return m end
        local compile = compilers[key]
        if compile then
            local fn = compile(self)
            rawset(self, key, fn)
            return fn
        end
    end
    mt.__newindex = frozen
    mt.__tostring = function() return "zigo." .. kind end
    metatables[mt] = true
    return mt
end

function M.defineKind(kind, def)
    local methods = def.methods or {}
    local impureMethods = {}
    for name, fn in pairs(base) do
        if methods[name] == nil then methods[name] = fn end
    end
    for name, fn in pairs(methods) do impureMethods[name] = fn end
    impureMethods.safeParse = impureSafeParse
    impureMethods.parse = impureParse
    kinds[kind] = {
        analyze = def.analyze,
        mt = makeMeta(kind, methods),
        impureMt = makeMeta(kind, impureMethods),
    }
end

function M.assertBase(self, name)
    if chainLength(self.d) > 0 then
        error("zigo: " .. name .. "() must be called before transform(), refine() or pipe()", 3)
    end
end

local function checkNumber(value, name, lengthLike)
    if type(value) ~= "number" or value ~= value then
        error("zigo: " .. name .. "() expects a number", 3)
    end
    if lengthLike and (value < 0 or value % 1 ~= 0) then
        error("zigo: " .. name .. "() expects a non-negative integer", 3)
    end
end

function M.boundMethods(lengthLike)
    local methods = {}
    local function bound(name)
        return function(self, n)
            M.assertBase(self, name)
            checkNumber(n, name, lengthLike)
            return M.derive(self, { [name] = n })
        end
    end
    methods.min = bound("min")
    methods.max = bound("max")
    methods.between = function(self, lo, hi)
        M.assertBase(self, "between")
        checkNumber(lo, "between", lengthLike)
        checkNumber(hi, "between", lengthLike)
        if lo > hi then error("zigo: between() expects min <= max", 2) end
        return M.derive(self, { min = lo, max = hi })
    end
    if lengthLike then methods.len = bound("len") end
    return methods
end

function base.optional(self)
    return M.derive(self, { optional = true, nilKind = "optional", nilAt = chainLength(self.d) })
end

function base.default(self, x)
    if x == nil then error("zigo: default() expects a value or a function", 2) end
    return M.derive(self, {
        hasDefault = true, default = x, nilKind = "default", nilAt = chainLength(self.d),
    })
end

local function withStep(self, step)
    local chain = self.d.chain
    local n = chain and #chain or 0
    local extended = {}
    for i = 1, n do extended[i] = chain[i] end
    extended[n + 1] = step
    return M.derive(self, { chain = extended })
end

function base.transform(self, fn)
    if type(fn) ~= "function" then error("zigo: transform() expects a function", 2) end
    return withStep(self, { op = "transform", fn = fn })
end

function base.refine(self, fn, opts)
    if type(fn) ~= "function" then error("zigo: refine() expects a function", 2) end
    if opts ~= nil and type(opts) ~= "table" then
        error("zigo: refine() expects an options table", 2)
    end
    local message, code, path
    if opts then
        message, code, path = opts.message, opts.code, opts.path
        if message ~= nil and type(message) ~= "string" then
            error("zigo: refine() option 'message' expects a string", 2)
        end
        if code ~= nil and type(code) ~= "string" then
            error("zigo: refine() option 'code' expects a string", 2)
        end
        if path ~= nil and type(path) ~= "table" then
            error("zigo: refine() option 'path' expects a list", 2)
        end
    end
    local issue = { message = message, code = code, path = path }
    return withStep(self, { op = "refine", fn = fn, issue = issue })
end

function base.pipe(self, schema)
    if not M.isNode(schema) then error("zigo: pipe() expects a schema", 2) end
    return withStep(self, { op = "pipe", schema = schema })
end

function base.is(self, v)
    return self._test(v)
end

function base.safeParse(self, v)
    if self._test(v) then return true, v end
    return false, nil, errors.new(self._check(v, {}, 0, nil))
end

function base.parse(self, v)
    if self._test(v) then return v end
    error(errors.new(self._check(v, {}, 0, nil)), 2)
end

return M
