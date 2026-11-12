---@meta

---@alias zigo.Path (string|number|boolean)[]

---@class zigo.Issue
---@field path zigo.Path
---@field code string
---@field expected any
---@field got any
---@field type? string
---@field exact? boolean
---@field message? string
---@field unionErrors? zigo.Issue[][]

---@class zigo.LimitsOptions
---@field maxDepth? integer nesting levels of containers, default 64
---@field maxKeys? integer keys of one iterated table, default 10000
---@field maxErrors? integer issues kept in an error, default 100
---@field abortEarly? boolean stop at the first issue, default false

---@class zigo.ConfigOptions : zigo.LimitsOptions
---@field codegen? boolean
---@field null? any default NULL sentinel for null() and nullable(), captured when the schema is built; never nil or NaN

---@class zigo.Config
---@field codegen boolean
---@field maxDepth integer
---@field maxKeys integer
---@field maxErrors integer
---@field abortEarly boolean
---@field null? any the default NULL sentinel, nil until z.config({ null = ... }) sets it

---@class zigo.Flattened
---@field formErrors string[]
---@field fieldErrors table<string, string[]>

---@alias zigo.Message string|fun(issue: zigo.Issue): string

---@class zigo.Error
---@field issues zigo.Issue[]
local Error = {}

---@param messages? table<string, zigo.Message>
---@return string
function Error:format(messages) end

---@param messages? table<string, zigo.Message>
---@return zigo.Flattened
function Error:flatten(messages) end

---@class zigo.Context
local Context = {}

---@param issue { message?: string, code?: string, path?: zigo.Path }
function Context:addIssue(issue) end

---@class zigo.RefineOptions
---@field message? string
---@field code? string
---@field path? zigo.Path

---@class zigo.Node
---@field kind string
---@field pure boolean
---@field maxDepth integer
---@field isOptional boolean
---@field isNullable boolean
---@field _test fun(v: any): boolean
---@field _parse fun(v: any, ctx: zigo.Context, depth: integer): boolean, any
---@field _check fun(v: any, path: zigo.Path, depth: integer, errs: zigo.Issue[]|nil): zigo.Issue[]|nil
local Node = {}

---@return zigo.Node
function Node:optional() end

---@param sentinel? any accepted in addition to the schema, compared with rawequal and returned as-is by parse; defaults to z.config({ null = ... }), distinct from optional() which accepts nil
---@return zigo.Node
function Node:nullable(sentinel) end

---@param x any value returned as-is when the input is nil, or a function called each time
---@return zigo.Node
function Node:default(x) end

---@param fn fun(v: any, ctx: zigo.Context): any
---@return zigo.Node
function Node:transform(fn) end

---@param fn fun(v: any, ctx: zigo.Context): any
---@param opts? zigo.RefineOptions
---@return zigo.Node
function Node:refine(fn, opts) end

---@param schema zigo.Node
---@return zigo.Node
function Node:pipe(schema) end

---@param opts zigo.LimitsOptions overrides z.config for this schema and the schemas below it
---@return zigo.Node
function Node:limits(opts) end

---@param v any
---@return boolean
function Node:is(v) end

---@param v any
---@return any
function Node:parse(v) end

---@param v any
---@return boolean ok
---@return any value
---@return zigo.Error? err
function Node:safeParse(v) end

---@class zigo.SizedNode : zigo.Node
local SizedNode = {}

---@param n number
---@return zigo.SizedNode
function SizedNode:min(n) end

---@param n number
---@return zigo.SizedNode
function SizedNode:max(n) end

---@param lo number
---@param hi number
---@return zigo.SizedNode
function SizedNode:between(lo, hi) end

---@param n integer
---@return zigo.SizedNode
function SizedNode:len(n) end

---@class zigo.ObjectNode : zigo.Node
local ObjectNode = {}

---@return zigo.ObjectNode
function ObjectNode:strict() end

---@return zigo.ObjectNode
function ObjectNode:strip() end

---@class zigo.TupleNode : zigo.Node
local TupleNode = {}

---@param schema zigo.Node
---@return zigo.TupleNode
function TupleNode:rest(schema) end

---@class zigo.IntegerOptions
---@field strict? boolean

---@class zigo.Int64Options
---@field fromString? boolean parse decimal strings into the fixed int64 form of the runtime (native integer on 5.3+, int64_t cdata on LuaJIT, number up to 2^53 otherwise)

---@class zigo.ContainerOptions
---@field meta? boolean

---@class zigo.Coerce
local Coerce = {}

---@return zigo.SizedNode
function Coerce.number() end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function Coerce.integer(opts) end

---@return zigo.Node
function Coerce.boolean() end

---@return zigo.SizedNode
function Coerce.string() end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function Coerce.u8(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function Coerce.u16(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function Coerce.u32(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function Coerce.i8(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function Coerce.i16(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function Coerce.i32(opts) end

---@class zigo
---@field _VERSION string
---@field coerce zigo.Coerce
---@field messages table<string, zigo.Message>
local zigo = {}

---@return zigo.SizedNode
function zigo.string() end

---@return zigo.SizedNode
function zigo.number() end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function zigo.integer(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function zigo.u8(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function zigo.u16(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function zigo.u32(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function zigo.i8(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function zigo.i16(opts) end

---@param opts? zigo.IntegerOptions
---@return zigo.SizedNode
function zigo.i32(opts) end

---@param opts? zigo.Int64Options
---@return zigo.Node
function zigo.int64(opts) end

---@return zigo.SizedNode same checks as string(), named to state the intent
function zigo.bytes() end

---@return zigo.SizedNode strict RFC 3629 UTF-8; min, max and len count characters
function zigo.utf8() end

---@return zigo.Node
function zigo.boolean() end

---@param sentinel? any accepted by rawequal only, defaults to z.config({ null = ... }); never nil or NaN
---@return zigo.Node
function zigo.null(sentinel) end

---@return zigo.Node accepts any function
function zigo.func() end

---@param mt? table when given, the userdata must have exactly this metatable as returned by getmetatable (a __metatable field replaces it)
---@return zigo.Node accepts userdata only (not LuaJIT cdata)
function zigo.userdata(mt) end

---@param mt table accepts tables and userdata whose getmetatable is exactly mt, with no walk along __index
---@return zigo.Node
function zigo.instanceOf(mt) end

---@param ctype string|any C type checked with ffi.istype and resolved at the first call on LuaJIT; every value is refused with invalid_type elsewhere
---@return zigo.Node
function zigo.cdata(ctype) end

---@param ctype string|any required pointer type checked with ffi.istype, resolved at the first call (it must be a pointer type); the value must not be NULL
---@return zigo.Node refuses a NULL pointer; every value is refused with invalid_type outside LuaJIT
function zigo.notNullPtr(ctype) end

---@param value string|number|boolean
---@return zigo.Node
function zigo.literal(value) end

---@param values (string|number|boolean)[]
---@return zigo.Node
function zigo.enum(values) end

---@return zigo.Node
function zigo.any() end

---@return zigo.Node
function zigo.unknown() end

---@return zigo.Node
function zigo.never() end

---@param item zigo.Node
---@param opts? zigo.ContainerOptions
---@return zigo.SizedNode
function zigo.array(item, opts) end

---@param shape table<string, zigo.Node>
---@param opts? zigo.ContainerOptions
---@return zigo.ObjectNode
function zigo.object(shape, opts) end

---@param items zigo.Node[]
---@param opts? zigo.ContainerOptions
---@return zigo.TupleNode
function zigo.tuple(items, opts) end

---@param key zigo.Node must be pure
---@param value zigo.Node
---@return zigo.Node
function zigo.record(key, value) end

---@param fn fun(): zigo.Node resolved on first use; the target must be a pure schema
---@return zigo.Node
function zigo.lazy(fn) end

---@param ... zigo.Node
---@return zigo.Node
function zigo.union(...) end

---@param key string
---@param ... zigo.ObjectNode objects whose field `key` is a plain literal
---@return zigo.Node
function zigo.discriminatedUnion(key, ...) end

---@param opts? zigo.ConfigOptions applies to schemas compiled afterwards
---@return zigo.Config
function zigo.config(opts) end

---@param x any
---@return boolean
function zigo.isNode(x) end

---@param x any
---@return boolean
function zigo.isError(x) end

---@param messages table<string, zigo.Message>
function zigo.setMessages(messages) end

return zigo
