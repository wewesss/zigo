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
---@field _test fun(v: any): boolean
---@field _parse fun(v: any, ctx: zigo.Context, depth: integer): boolean, any
---@field _check fun(v: any, path: zigo.Path, depth: integer, errs: zigo.Issue[]|nil): zigo.Issue[]|nil
local Node = {}

---@return zigo.Node
function Node:optional() end

---@param x any value returned as-is when the input is nil, or a function called each time
---@return zigo.Node
function Node:default(x) end

---@param fn fun(v: any, ctx: zigo.Context): any must be free of side effects
---@return zigo.Node
function Node:transform(fn) end

---@param fn fun(v: any, ctx: zigo.Context): any
---@param opts? zigo.RefineOptions
---@return zigo.Node
function Node:refine(fn, opts) end

---@param schema zigo.Node
---@return zigo.Node
function Node:pipe(schema) end

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

---@return zigo.Node
function zigo.boolean() end

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

---@param ... zigo.Node
---@return zigo.Node
function zigo.union(...) end

---@param key string
---@param ... zigo.ObjectNode objects whose field `key` is a plain literal
---@return zigo.Node
function zigo.discriminatedUnion(key, ...) end

---@param x any
---@return boolean
function zigo.isNode(x) end

---@param x any
---@return boolean
function zigo.isError(x) end

---@param messages table<string, zigo.Message>
function zigo.setMessages(messages) end

return zigo
