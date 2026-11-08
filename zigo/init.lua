local node = require("zigo.node")
local errors = require("zigo.errors")
local closures = require("zigo.compile.closures")
local primitives = require("zigo.types.primitives")
local array = require("zigo.types.array")
local object = require("zigo.types.object")

node.setCompiler("_test", closures.test)
node.setCompiler("_check", closures.check)

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
    isNode = node.isNode,
    isError = errors.isError,
    messages = errors.messages,
    setMessages = errors.setMessages,
}
