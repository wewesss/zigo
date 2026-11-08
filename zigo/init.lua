local node = require("zigo.node")
local errors = require("zigo.errors")
local closures = require("zigo.compile.closures")
local codegen = require("zigo.compile.codegen")
local parse = require("zigo.compile.parse")
local primitives = require("zigo.types.primitives")
local fixed = require("zigo.types.fixed")
local int64 = require("zigo.types.int64")
local boundary = require("zigo.types.boundary")
local array = require("zigo.types.array")
local object = require("zigo.types.object")
local coerce = require("zigo.types.coerce")
local tuple = require("zigo.types.tuple")
local record = require("zigo.types.record")
local union = require("zigo.types.union")
local lazy = require("zigo.types.lazy")
local limits = require("zigo.limits")

local leafKinds = {
    string = true, number = true, integer = true, boolean = true, literal = true,
    enum = true, any = true, unknown = true, never = true,
    int64 = true, bytes = true, utf8 = true,
}
for _, spec in ipairs(closures.fixedInts) do leafKinds[spec[1]] = true end

node.setCompiler("_limits", function(self)
    return limits.resolve(self)
end)
node.setCompiler("_test", function(self, lim)
    lim = lim or self._limits
    if not self.pure then return parse.test(self, lim) end
    if lim.tracked and not leafKinds[self.kind] then return node.sub(self, "_testD", lim) end
    return codegen.test(self, lim, false)
end)
node.setCompiler("_testD", function(self, lim)
    lim = lim or self._limits
    if not self.pure then return parse.test(self, lim) end
    return codegen.test(self, lim, not leafKinds[self.kind])
end)
node.setCompiler("_check", function(self, lim)
    lim = lim or self._limits
    if self.pure then return closures.check(self, lim) end
    return parse.check(self, lim)
end)
node.setCompiler("_parse", parse.build)

local function config(opts)
    if opts ~= nil then
        if type(opts) ~= "table" then
            error("zigo: config() expects a table", 2)
        end
        local own, unknown = {}, {}
        for k, v in pairs(opts) do
            if k == "codegen" then
                if type(v) ~= "boolean" then
                    error("zigo: config() option 'codegen' expects a boolean", 2)
                end
            elseif limits.isOption(k) then
                own[k] = v
            else
                unknown[#unknown + 1] = tostring(k)
            end
        end
        if #unknown > 0 then
            table.sort(unknown)
            error("zigo: config() unknown option '" .. unknown[1] .. "'", 2)
        end
        limits.validate(own, "config")
        limits.configure(own)
        if opts.codegen ~= nil then codegen.setEnabled(opts.codegen) end
    end
    local out = limits.current()
    out.codegen = codegen.isEnabled()
    return out
end

local api = {
    _VERSION = "0.0.0",
    string = primitives.string,
    number = primitives.number,
    integer = primitives.integer,
    int64 = int64.int64,
    bytes = boundary.bytes,
    utf8 = boundary.utf8,
    boolean = primitives.boolean,
    literal = primitives.literal,
    enum = primitives.enum,
    any = primitives.any,
    unknown = primitives.unknown,
    never = primitives.never,
    array = array.array,
    object = object.object,
    tuple = tuple.tuple,
    record = record.record,
    lazy = lazy.lazy,
    union = union.union,
    discriminatedUnion = union.discriminatedUnion,
    coerce = {
        number = coerce.number,
        integer = coerce.integer,
        boolean = coerce.boolean,
        string = coerce.string,
    },
    config = config,
    isNode = node.isNode,
    isError = errors.isError,
    messages = errors.messages,
    setMessages = errors.setMessages,
    _isGenerated = codegen.isGenerated,
}

for _, spec in ipairs(closures.fixedInts) do
    local name = spec[1]
    api[name] = fixed[name]
    api.coerce[name] = coerce[name]
end

return api
