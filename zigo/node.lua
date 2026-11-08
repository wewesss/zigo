local errors = require("zigo.errors")

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

function M.new(kind, d)
    local def = kinds[kind]
    if not def then error("zigo: unknown node kind '" .. tostring(kind) .. "'", 2) end
    local pure, depth = def.analyze(d)
    local self = setmetatable({}, def.mt)
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

function M.defineKind(kind, def)
    local methods = def.methods or {}
    for name, fn in pairs(base) do
        if methods[name] == nil then methods[name] = fn end
    end
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
    kinds[kind] = { analyze = def.analyze, mt = mt }
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
            checkNumber(n, name, lengthLike)
            return M.derive(self, { [name] = n })
        end
    end
    methods.min = bound("min")
    methods.max = bound("max")
    methods.between = function(self, lo, hi)
        checkNumber(lo, "between", lengthLike)
        checkNumber(hi, "between", lengthLike)
        if lo > hi then error("zigo: between() expects min <= max", 2) end
        return M.derive(self, { min = lo, max = hi })
    end
    if lengthLike then methods.len = bound("len") end
    return methods
end

function base.optional(self)
    return M.derive(self, { optional = true })
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
