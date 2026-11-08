---@meta

---@alias zigo.Path (string|number|boolean)[]

---@class zigo.Issue
---@field path zigo.Path
---@field code string
---@field expected any
---@field got any
---@field type? string
---@field exact? boolean

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

---@class zigo.Node
---@field kind string
---@field pure boolean
---@field maxDepth integer
---@field isOptional boolean
---@field _test fun(v: any): boolean
---@field _check fun(v: any, path: zigo.Path, depth: integer, errs: zigo.Issue[]|nil): zigo.Issue[]|nil
local Node = {}

---@return zigo.Node
function Node:optional() end

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

---@class zigo.IntegerOptions
---@field strict? boolean

---@class zigo.ContainerOptions
---@field meta? boolean

---@class zigo
---@field _VERSION string
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

---@param x any
---@return boolean
function zigo.isNode(x) end

---@param x any
---@return boolean
function zigo.isError(x) end

---@param messages table<string, zigo.Message>
function zigo.setMessages(messages) end

return zigo
