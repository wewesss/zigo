local node = require("zigo.node")
local errors = require("zigo.errors")
local closures = require("zigo.compile.closures")
local codegen = require("zigo.compile.codegen")
local primitives = require("zigo.types.primitives")
local array = require("zigo.types.array")
local object = require("zigo.types.object")

node.setCompiler("_test", codegen.test)
node.setCompiler("_check", closures.check)

local function config(opts)
    if opts ~= nil then
        if type(opts) ~= "table" then
            error("zigo: config() expects a table", 2)
        end
        local unknown = {}
        for k in pairs(opts) do
            if k ~= "codegen" then unknown[#unknown + 1] = tostring(k) end
        end
        if #unknown > 0 then
            table.sort(unknown)
            error("zigo: config() unknown option '" .. unknown[1] .. "'", 2)
        end
        if opts.codegen ~= nil then
            if type(opts.codegen) ~= "boolean" then
                error("zigo: config() option 'codegen' expects a boolean", 2)
            end
            codegen.setEnabled(opts.codegen)
        end
    end
    return { codegen = codegen.isEnabled() }
end

return {
    _VERSION = "0.0.0",
    string = primitives.string,
    number = primitives.number,
    integer = primitives.integer,
    boolean = primitives.boolean,
    literal = primitives.literal,
    enum = primitives.enum,
    any = primitives.any,
    unknown = primitives.unknown,
    never = primitives.never,
    array = array.array,
    object = object.object,
    config = config,
    isNode = node.isNode,
    isError = errors.isError,
    messages = errors.messages,
    setMessages = errors.setMessages,
    _isGenerated = codegen.isGenerated,
}
