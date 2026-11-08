# zigo guide

English · [Français](../fr/guide.md)

zigo 1.0.0 validates data at the Lua side of a boundary (SQL rows, FFI returns, network packets, config, user input): a schema checks the value and hands back a safe one. Lua 5.1 to 5.4 and LuaJIT 2.1, zero dependency.

1. [Install](#1-install) · 2. [Quick start](#2-quick-start) · 3. [Primitives](#3-primitives) · 4. [Literals and special types](#4-literals-and-special-types) · 5. [Integers](#5-integers) · 6. [Strings and bytes](#6-strings-and-bytes) · 7. [NULL, nullable and optional](#7-null-nullable-and-optional) · 8. [Lua and FFI types](#8-lua-and-ffi-types) · 9. [Containers](#9-containers) · 10. [Unions and recursion](#10-unions-and-recursion) · 11. [Modifiers](#11-modifiers) · 12. [Errors](#12-errors) · 13. [Network limits](#13-network-limits) · 14. [Codegen](#14-codegen) · 15. [Runtime differences](#15-runtime-differences) · 16. [LuaCATS annotations](#16-luacats-annotations) · 17. [matchigo interop](#17-matchigo-interop) · 18. [Performance](#18-performance)

## 1. Install

LuaRocks:

```sh
luarocks install zigo
```

Single-file bundle: download the release archive `zigo-<tag>.zip` from the [GitHub releases](https://github.com/wewesss/zigo/releases). It holds `zigo.lua` (readable), `zigo.min.lua` (same code, minified) and `zigo-type/` (LuaCATS annotations). Put one of the two files on your `package.path`, or load it directly:

```lua skip
local z = require("zigo")
local z2 = dofile("path/to/zigo.lua")
```

Sources: clone the repository and add its root to `package.path`. `lua build.lua` regenerates `dist/zigo.lua` and `dist/zigo.min.lua`.

```lua skip
package.path = "path/to/zigo/?.lua;path/to/zigo/?/init.lua;" .. package.path
local z = require("zigo")
```

## 2. Quick start

```lua
local z = require("zigo")

local User = z.object({
    name = z.string():min(1),
    age = z.integer():between(0, 150):optional(),
    role = z.enum({ "admin", "user" }),
}):strict()

local ok, user, err = User:safeParse({ name = "ann", role = "admin" })
print(ok) --> true
print(user.name) --> ann
print(err) --> nil
```

`safeParse` never raises on bad input and returns three values: `ok, value, err`. On success `err` is `nil`. On failure `value` is `nil` and `err` is an error object.

```lua
local z = require("zigo")

local User = z.object({
    name = z.string():min(1),
    role = z.enum({ "admin", "user" }),
}):strict()

local ok, value, err = User:safeParse({ name = "", role = "root", extra = 1 })
print(ok) --> false
print(value) --> nil
print(err:format())
--> name: Expected length of at least 1, got 0
--> role: Expected one of: "admin", "user", got "root"
--> extra: Unrecognized key
```

The three entry points of every schema:

| Call | Returns | On invalid input |
| --- | --- | --- |
| `schema:safeParse(v)` | `ok, value, err` | `false, nil, err` |
| `schema:parse(v)` | `value` | raises the error object (use `pcall`, test it with `z.isError`) |
| `schema:is(v)` | `boolean` | `false` |

```lua
local z = require("zigo")

local Age = z.integer():min(0)
print(Age:is(3)) --> true
print(Age:parse(3)) --> 3

local ok, e = pcall(Age.parse, Age, -1)
print(ok) --> false
print(z.isError(e)) --> true
print(tostring(e))
--> ZigoError: 1 issue(s)
--> <root>: Expected value of at least 0, got -1
```

Rules that hold everywhere:

- Schemas are immutable: every modifier returns a new node and never changes the source. A schema can be shared freely.
- Compilation is lazy (first use) and cached on the node. Build schemas once, at load time, never inside a request handler.
- No implicit coercion: `"12"` is not an integer. Coercion exists only through `z.coerce.*` ([section 11](#11-modifiers)).
- Same input, same issues, same order, on every runtime.
- A schema without `default`, `transform`, `refine`, `pipe`, `coerce` or `strip` is pure: a valid call allocates nothing and `safeParse` returns the very value you passed.

## 3. Primitives

| Constructor | Accepts | Modifiers |
| --- | --- | --- |
| `z.string()` | a string | `:min(n) :max(n) :between(lo, hi) :len(n)` on the byte length |
| `z.number()` | any number except NaN (infinities pass) | `:min(n) :max(n) :between(lo, hi)` |
| `z.integer(opts?)` | a number with an integral value, never NaN or infinity; `3.0` passes | `:min(n) :max(n) :between(lo, hi)` |
| `z.boolean()` | `true` or `false` | none |

Bounds are inclusive. `len` checks an exact size. The arguments of `min`, `max`, `between` and `len` are checked at construction, and `len` takes a non-negative integer. `integer({ strict = true })` refuses `3.0` on Lua 5.3 and 5.4 (see [section 15](#15-runtime-differences)).

```lua
local z = require("zigo")

print(z.string():min(2):max(8):is("zigo")) --> true
print(z.string():len(3):is("zigo")) --> false
print(z.number():between(0, 1):is(0.5)) --> true
print(z.number():is(0 / 0)) --> false
print(z.integer():is(3.5)) --> false
print(z.integer():is(7)) --> true
print(z.boolean():is("true")) --> false
```

```lua lua53
local z = require("zigo")

print(z.integer():is(3.0)) --> true
print(z.integer({ strict = true }):is(3.0)) --> false
```

Bounds and `strict`, `strip`, `rest` must come before the first `transform`, `refine` or `pipe`; later they raise an error.

## 4. Literals and special types

| Constructor | Accepts |
| --- | --- |
| `z.literal(v)` | exactly `v`: a string, a number (not NaN) or a boolean |
| `z.enum(list)` | one value of a non-empty list of strings, numbers or booleans |
| `z.any()` | every value, `nil` included |
| `z.unknown()` | every value, `nil` included (same checks as `any`) |
| `z.never()` | nothing |

```lua
local z = require("zigo")

print(z.literal("ok"):is("ok")) --> true
print(z.literal(1):is(2)) --> false
print(z.enum({ "a", "b" }):is("c")) --> false
print(z.any():is(nil)) --> true
print(z.unknown():is({})) --> true
print(z.never():is(1)) --> false
```

## 5. Integers

### Fixed-size integers

`z.u8()`, `z.u16()`, `z.u32()`, `z.i8()`, `z.i16()` and `z.i32()` follow the rule of `integer()` (`3.0` passes, `{ strict = true }` refuses it) and add the range of the type: `u8` 0 to 255, `u16` 0 to 65535, `u32` 0 to 4294967295, `i8` -128 to 127, `i16` -32768 to 32767, `i32` -2147483648 to 2147483647. `:min`, `:max` and `:between` narrow that range. A non-integer gives `invalid_type`; a value out of range gives `too_small` or `too_big`.

```lua
local z = require("zigo")

print(z.u8():is(255)) --> true
print(z.u8():is(256)) --> false
print(z.u8():max(100):is(101)) --> false

local _, _, err = z.i8():safeParse(-129)
print(err:format()) --> <root>: Expected value of at least -128, got -129
```

### int64

`z.int64()` accepts what the runtime can hold as a 64-bit integer:

- Lua 5.3 and 5.4: every native integer, and floats with an integral value up to 2^53;
- LuaJIT: `int64_t` cdata (`5LL`), and numbers with an integral value up to 2^53; the `uint64_t` cdata (`5ULL`) is refused;
- Lua 5.1 and 5.2: numbers with an integral value up to 2^53 (a larger one cannot be told apart from its neighbours).

`z.int64({ fromString = true })` also accepts a decimal string (`-?%d+`, no spaces, no sign `+`) and returns a fixed form per runtime: a native integer on 5.3 and 5.4, an `int64_t` cdata on LuaJIT, a number up to 2^53 elsewhere. A string out of range gives `too_big` or `too_small`. Anything that is not a string passes through the normal `int64` check unchanged.

```lua
local z = require("zigo")

local Id = z.int64()
print(Id:is(2 ^ 53)) --> true
print(Id:is(1.5)) --> false
print(Id:is("12")) --> false

local FromText = z.int64({ fromString = true })
local ok, id = FromText:safeParse("12")
print(ok) --> true
print(tonumber(id)) --> 12
print(FromText:is("12x")) --> false
```

```lua lua53
local z = require("zigo")

local FromText = z.int64({ fromString = true })
local _, id = FromText:safeParse("9007199254740993")
print(math.type(id)) --> integer
print(id) --> 9007199254740993

local ok, _, err = FromText:safeParse("9223372036854775808")
print(ok) --> false
print(err.issues[1].code) --> too_big
```

```lua luajit
local z = require("zigo")
local ffi = require("ffi")

local FromText = z.int64({ fromString = true })
local _, id = FromText:safeParse("9007199254740993")
print(tostring(id)) --> 9007199254740993LL
print(ffi.istype("int64_t", id)) --> true
print(z.int64():is(ffi.new("int64_t", 5))) --> true
print(z.int64():is(ffi.new("uint64_t", 5))) --> false
```

```lua lua51
local z = require("zigo")

local FromText = z.int64({ fromString = true })
print(FromText:is("9007199254740992")) --> true

local ok, _, err = FromText:safeParse("9007199254740993")
print(ok) --> false
print(err.issues[1].code) --> too_big
```

## 6. Strings and bytes

`z.bytes()` has the same checks as `z.string()` and states the intent: binary data, sizes in bytes. `z.string()` does not check the encoding.

`z.utf8()` accepts only valid UTF-8 as defined by RFC 3629 (no overlong forms, no surrogates, nothing above U+10FFFF). The verdict is the same on every runtime. For `utf8`, `:min`, `:max`, `:between` and `:len` count characters, not bytes. An invalid sequence gives `invalid_type` with `got = "bytes"`.

```lua
local z = require("zigo")

print(z.utf8():min(1):max(3):is("héé")) --> true
print(z.string():max(3):is("héé")) --> false
print(z.utf8():is("\255")) --> false
print(z.bytes():len(2):is("\0\255")) --> true

local _, _, err = z.utf8():safeParse("\255")
print(err:format()) --> <root>: Expected utf8, got bytes
```

## 7. NULL, nullable and optional

Lua has no value for SQL `NULL` or JSON `null`: libraries use a sentinel (`cjson.null`, `ngx.null`, `vim.NIL`, or a table of your own). zigo keeps the two ideas apart:

- `:optional()` accepts `nil` (a missing key).
- `:nullable(sentinel)` accepts the sentinel, compared with `rawequal`, and `parse` returns it as is. It does not accept `nil`.
- `z.null(sentinel)` accepts only the sentinel.

```lua
local z = require("zigo")

local NULL = setmetatable({}, { __tostring = function() return "NULL" end })

local Row = z.object({
    id = z.integer(),
    nickname = z.string():nullable(NULL),
    bio = z.string():optional(),
})

print(Row:is({ id = 1, nickname = NULL })) --> true
print(Row:is({ id = 1, nickname = "bo", bio = "hi" })) --> true
print(Row:is({ id = 1 })) --> false
print(Row:is({ id = 1, nickname = NULL, bio = NULL })) --> false
```

`z.config({ null = NULL })` sets the default sentinel, so that `z.null()` and `:nullable()` can be called without an argument. A schema captures its sentinel when it is built. A sentinel can be any value except `nil` and NaN. The set of sentinels is global: a sentinel table, userdata or cdata is named `null` in the messages of every schema, so do not choose a shared object such as `io.stdout`.

```lua
local z = require("zigo")

local NULL = {}
z.config({ null = NULL })

print(z.null():is(NULL)) --> true
print(z.null():is(nil)) --> false
local ok, v = z.string():nullable():safeParse(NULL)
print(v == NULL) --> true
```

## 8. Lua and FFI types

| Constructor | Accepts |
| --- | --- |
| `z.func()` | a function |
| `z.userdata(mt?)` | a userdata (not a LuaJIT cdata); with `mt`, its `getmetatable` must be exactly `mt` |
| `z.instanceOf(mt)` | a table or a userdata whose `getmetatable` is exactly `mt`; no walk along `__index`, so a subclass does not match |
| `z.cdata(ctype)` | LuaJIT only: a cdata for which `ffi.istype(ctype, v)` holds; the type is resolved at the first call |
| `z.notNullPtr(ctype)` | LuaJIT only: same, `ctype` must be a pointer type and the pointer must not be NULL |

Outside LuaJIT, `cdata` and `notNullPtr` can still be built, and they refuse every value with `invalid_type`.

```lua
local z = require("zigo")

local Point = {}
Point.__index = Point
local p = setmetatable({ x = 1 }, Point)

print(z.instanceOf(Point):is(p)) --> true
print(z.instanceOf(Point):is({ x = 1 })) --> false
print(z.func():is(print)) --> true
print(z.userdata():is(io.stdout)) --> true
print(z.userdata(getmetatable(io.stdout)):is(io.stdout)) --> true
```

```lua luajit
local z = require("zigo")
local ffi = require("ffi")

ffi.cdef("typedef struct { int x; } point_t;")
local obj = ffi.new("point_t", 1)
local p = ffi.cast("point_t *", obj)
local null = ffi.cast("point_t *", nil)

local Ptr = z.cdata("point_t *")
local NonNull = z.notNullPtr("point_t *")
print(Ptr:is(p)) --> true
print(Ptr:is(null)) --> true
print(NonNull:is(p)) --> true
print(NonNull:is(null)) --> false

local _, _, err = NonNull:safeParse(null)
print(err:format()) --> <root>: Expected non-null point_t *, got NULL
```

Under LuaJIT a NULL pointer compares equal to `nil`. `:optional()` on other types, and the hole checks of arrays and tuples, therefore see it as absent; only `cdata` and `notNullPtr` tell it apart.

## 9. Containers

### object

`z.object(shape, opts?)` takes a table of string keys to schemas. Fields are checked in alphabetical order of their keys (fixed at construction), which makes the errors deterministic. A missing key reaches its schema as `nil`.

| Mode | Unknown keys | Cost |
| --- | --- | --- |
| passthrough (default) | kept | no copy |
| `:strict()` | `unrecognized_key` error | no copy, one more iteration |
| `:strip()` | removed | copies the table (impure schema) |

The last of `:strict()` and `:strip()` wins. For anything that comes from the network, prefer `:strict()`.

```lua
local z = require("zigo")

local Shape = z.object({ id = z.integer() })
local input = { id = 1, extra = true }

print(Shape:is(input)) --> true
print(Shape:strict():is(input)) --> false

local ok, same = Shape:safeParse(input)
print(same == input) --> true

local _, stripped = Shape:strip():safeParse(input)
print(stripped.extra) --> nil
print(stripped == input) --> false

local _, _, err = Shape:strict():safeParse(input)
print(err:format()) --> extra: Unrecognized key
```

By default, `object`, `array` and `tuple` read fields with `rawget`. `{ meta = true }` as the second argument reads them with normal indexing (`__index`, `__len`).

```lua
local z = require("zigo")

local proxy = setmetatable({}, { __index = { name = "x" } })
print(z.object({ name = z.string() }):is(proxy)) --> false
print(z.object({ name = z.string() }, { meta = true }):is(proxy)) --> true
```

### array

`z.array(item, opts?)` accepts a sequence: no holes, no key other than `1..n`. `{}` is valid. `:min`, `:max`, `:between` and `:len` bound the length. A table that is not a clean sequence gives `invalid_array`.

```lua
local z = require("zigo")

local Tags = z.array(z.string()):max(3)
print(Tags:is({ "a", "b" })) --> true
print(Tags:is({})) --> true
print(Tags:is({ "a", nil, "c" })) --> false
print(Tags:is({ a = "x" })) --> false

local _, _, err = Tags:safeParse({ "a", 2 })
print(err:format()) --> [2]: Expected string, got number
```

### tuple

`z.tuple(items, opts?)` is a fixed-length list, one schema per position. Extra elements are refused, unless `:rest(schema)` checks them.

```lua
local z = require("zigo")

local Pair = z.tuple({ z.string(), z.integer() })
print(Pair:is({ "a", 1 })) --> true
print(Pair:is({ "a", 1, 2 })) --> false

local Row = Pair:rest(z.boolean())
print(Row:is({ "a", 1, true, false })) --> true
print(Row:is({ "a", 1, true, 1 })) --> false
```

### record

`z.record(key, value)` is a table with any number of keys that all match `key` and whose values match `value`. The key schema must be pure (no `default`, `transform`, `refine`, `pipe` or `coerce`). Errors come out with keys sorted: numbers, then strings, then booleans.

```lua
local z = require("zigo")

local Scores = z.record(z.string():min(1), z.integer())
print(Scores:is({ ann = 3, bo = 5 })) --> true
print(Scores:is({ [""] = 1 })) --> false

local _, _, err = Scores:safeParse({ ann = "x" })
print(err:format()) --> ann: Expected integer, got string
```

## 10. Unions and recursion

### union

`z.union(a, b, ...)`: the first variant that passes wins. When none passes, the issue is `invalid_union`, and its `unionErrors` field holds the list of issues of each variant.

```lua
local z = require("zigo")

local Id = z.union(z.integer(), z.string():min(1))
print(Id:is(7)) --> true
print(Id:is("u7")) --> true
print(Id:is(true)) --> false

local _, _, err = Id:safeParse(true)
local issue = err.issues[1]
print(issue.code) --> invalid_union
print(#issue.unionErrors) --> 2
print(issue.unionErrors[1][1].code) --> invalid_type
```

### discriminatedUnion

`z.discriminatedUnion(key, variants...)` picks the variant with a hash table on the field `key`. Each variant must be a `z.object` that has a plain literal at `key` (not optional, nullable or defaulted), and two variants cannot share a value; otherwise construction raises an error. There is no sequential fallback: an absent or unknown discriminant gives `invalid_union_discriminator` at the path `key`, with the expected values. When the discriminant matches, you get the issues of that variant only.

```lua
local z = require("zigo")

local Packet = z.discriminatedUnion("kind",
    z.object({ kind = z.literal("ping"), id = z.integer() }),
    z.object({ kind = z.literal("chat"), text = z.utf8():max(200) })
)

print(Packet:is({ kind = "ping", id = 1 })) --> true

local _, _, unknown = Packet:safeParse({ kind = "pong" })
print(unknown:format()) --> kind: Expected discriminator one of: "ping", "chat", got "pong"

local _, _, bad = Packet:safeParse({ kind = "chat", text = 5 })
print(bad:format()) --> text: Expected utf8, got number

print((pcall(z.discriminatedUnion, "kind", z.object({ kind = z.string() })))) --> false
```

### lazy

`z.lazy(fn)` defers a schema, which makes recursive types possible. `fn` is called on first use and must return a pure schema. The depth is counted at run time and bounded by `maxDepth` ([section 13](#13-network-limits)), so cyclic data ends with `too_deep` instead of a stack overflow.

```lua
local z = require("zigo")

local Tree
Tree = z.object({
    value = z.integer(),
    children = z.array(z.lazy(function() return Tree end)),
})

print(Tree:is({ value = 1, children = { { value = 2, children = {} } } })) --> true

local cyclic = { value = 1 }
cyclic.children = { cyclic }
local _, _, err = Tree:safeParse(cyclic)
print(err.issues[1].code) --> too_deep
```

## 11. Modifiers

| Modifier | Effect |
| --- | --- |
| `:optional()` | accepts `nil` |
| `:nullable(sentinel?)` | accepts the NULL sentinel ([section 7](#7-null-nullable-and-optional)) |
| `:default(x)` | when the input is `nil`, the result is `x` as is, or `x()` if `x` is a function; the default is not validated |
| `:transform(fn)` | replaces the validated value by `fn(value, ctx)` |
| `:refine(fn, opts?)` | `fn(value, ctx)` must return a truthy value; otherwise an issue is added |
| `:pipe(schema)` | runs another schema on the current value |
| `:limits(opts)` | per-schema limits ([section 13](#13-network-limits)) |

Steps run in the order they are written. Each one receives the output of the previous one.

```lua
local z = require("zigo")

local Settings = z.object({
    port = z.integer():between(1, 65535):default(8080),
    tags = z.array(z.string()):default(function() return {} end),
    name = z.string():transform(function(s) return s:lower() end),
})

local _, cfg = Settings:safeParse({ name = "Zigo" })
print(cfg.port) --> 8080
print(#cfg.tags) --> 0
print(cfg.name) --> zigo
```

A default that is a table is shared between calls: pass a function to get a fresh table each time.

### transform and refine

`refine` takes the options `message`, `code` (default `"custom"`) and `path` (a list appended to the current path). A `transform` signals failure with `ctx:addIssue({ message, code, path })`, all three fields optional; `refine` can call it too, and any call counts as a failure.

```lua
local z = require("zigo")

local Even = z.integer():refine(function(n)
    return n % 2 == 0
end, { message = "must be even", code = "odd" })

local _, _, err = Even:safeParse(3)
print(err:format()) --> <root>: must be even
print(err.issues[1].code) --> odd

local Port = z.string():transform(function(s, ctx)
    local n = tonumber(s)
    if not n then
        ctx:addIssue({ message = "not a number", code = "nan_port" })
        return nil
    end
    return n
end)

local _, port = Port:safeParse("80")
print(port) --> 80
local _, _, bad = Port:safeParse("x")
print(bad:format()) --> <root>: not a number
```

Two traps. `fn` is called as `fn(value, ctx)`: a function that reads a second argument, such as `tonumber`, must be wrapped. And a `transform` must be free of side effects, because after a failure the diagnostic pass can call it again.

### pipe

```lua
local z = require("zigo")

local Age = z.string()
    :transform(function(s) return tonumber(s) end)
    :pipe(z.integer():between(0, 150))

print(Age:is("42")) --> true
print(Age:is("200")) --> false
print(Age:is("x")) --> false
```

### coerce

`z.coerce.*` converts, then validates, with strict rules:

| Constructor | Converts |
| --- | --- |
| `z.coerce.number()` | a string without whitespace or control characters, through `tonumber` (`"0x10"` and `"1e2"` pass); NaN and infinities are refused |
| `z.coerce.integer(opts?)` | the same, then the `integer` check |
| `z.coerce.u8()` ... `z.coerce.i32()` | the same, then the range of the type |
| `z.coerce.boolean()` | `"true"`, `"false"`, `"1"`, `"0"`, `1`, `0` only |
| `z.coerce.string()` | numbers and booleans through `tostring`; tables and `nil` are refused |

Bounds and `strict` apply after the conversion. `z.int64({ fromString = true })` is the coercion of `int64` ([section 5](#5-integers)).

```lua
local z = require("zigo")

print(z.coerce.number():parse("1.5")) --> 1.5
print(z.coerce.integer():parse("42")) --> 42
print(z.coerce.boolean():parse("false")) --> false
print(z.coerce.string():parse(12)) --> 12
print(z.coerce.integer():is("4.5")) --> false
print(z.coerce.number():is(" 7")) --> false
print(z.coerce.u8():is("300")) --> false
```

### Pure and impure schemas

A schema that uses `default`, `transform`, `refine`, `pipe`, `coerce` or `strip` (or contains one) is impure. A single pass validates and builds the output, so `is` gives the same verdict as `safeParse` and runs your functions. The output of an impure object is a new table. A pure schema returns the input untouched and allocates nothing on a valid call.

## 12. Errors

`err.issues` is a list of tables, in a fixed order:

| Field | Meaning |
| --- | --- |
| `path` | list of keys and indexes from the root (`{}` for the root) |
| `code` | stable code, see below |
| `expected`, `got` | what was expected and what was found; depends on the code |
| `type` | for size and range codes, the kind (`string`, `integer`, `array`, ...) |
| `exact` | `true` when the failure comes from `len` |
| `message` | set only by `refine`, `transform` or `addIssue`; it wins over the code table |
| `unionErrors` | for `invalid_union`, the issues of each variant |

| Code | Raised when | `expected` / `got` |
| --- | --- | --- |
| `invalid_type` | wrong type | type name / type found (`nil`, `float`, `nan`, `null`, `bytes`, ...) |
| `too_small` | below `min`, shorter than `len`, below the range of the type | bound / value or length |
| `too_big` | above `max`, longer than `len`, above the range of the type | bound / value or length |
| `invalid_literal` | not the literal | the literal / value found |
| `invalid_enum` | not in the list | the list of values / value found |
| `invalid_array` | table that is not a sequence (hole, stray key) | `"sequence"` / `"table"` |
| `unrecognized_key` | unknown key in a `:strict()` object | the path ends with the key; for a key that is a function, table, thread, userdata or cdata, the path stops at the table and `got` is the key type |
| `invalid_union` | no variant passes | `unionErrors` |
| `invalid_union_discriminator` | absent or unknown discriminant | list of values / value found |
| `too_deep` | nesting deeper than `maxDepth` | the limit |
| `too_many_keys` | more keys than `maxKeys` | the limit |
| `custom` | `refine` or `transform` failure without a code | none |

Reading an error:

```lua
local z = require("zigo")

local Form = z.object({
    email = z.string():min(5),
    age = z.integer():min(18),
    address = z.object({ zip = z.string():len(5) }),
})

local _, _, err = Form:safeParse({ email = "a", age = 12, address = { zip = "1" } })

local first = err.issues[1]
print(table.concat(first.path, ".")) --> address.zip
print(first.code) --> too_small
print(first.exact) --> true

print(err:format())
--> address.zip: Expected length of exactly 5, got 1
--> age: Expected value of at least 18, got 12
--> email: Expected length of at least 5, got 1

local flat = err:flatten()
print(flat.fieldErrors["age"][1]) --> Expected value of at least 18, got 12
print(#flat.formErrors) --> 0
```

- `err:format(messages?)` returns one `path: message` line per issue. Paths read `a.b[2].c`, and the root is `<root>`.
- `err:flatten(messages?)` returns `{ formErrors = {...}, fieldErrors = { ["a.b"] = {...} } }`: messages of the root go to `formErrors`, the others to `fieldErrors` under their path.
- `tostring(err)` gives `ZigoError: N issue(s)` followed by `format()`.
- Messages are built on demand, never during validation.

### Translating messages

Messages live in a table `code -> string | function(issue)`. A string may use `{field}` placeholders replaced by fields of the issue (`{expected}`, `{got}`, `{type}`, `{code}`). `err:format(table)` and `err:flatten(table)` use the given table for that call, and codes it lacks fall back to the built-in English. `z.setMessages(table)` replaces entries for the whole process, and `z.messages` is the live table of the defaults.

```lua
local z = require("zigo")

local Form = z.object({
    age = z.integer():min(18),
    email = z.string():min(5),
})
local _, _, err = Form:safeParse({ age = 12, email = 7 })

local fr = {
    too_small = "trop petit : {got} (minimum {expected})",
    invalid_type = function(i) return "attendu " .. tostring(i.expected) .. ", reçu " .. tostring(i.got) end,
}

print(err:format(fr))
--> age: trop petit : 12 (minimum 18)
--> email: attendu string, reçu number

z.setMessages(fr)
print(err:format())
--> age: trop petit : 12 (minimum 18)
--> email: attendu string, reçu number
```

## 13. Network limits

Four limits protect against hostile input. They are active by default:

| Option | Default | Effect |
| --- | --- | --- |
| `maxDepth` | `64` | levels of nesting; deeper gives `too_deep` (this also stops cyclic data) |
| `maxKeys` | `10000` | keys of one table that the validator iterates (arrays, tuples, records, `:strict()` and `:strip()` objects); more gives `too_many_keys`. A passthrough object does not iterate its keys, so the limit costs it nothing |
| `maxErrors` | `100` | issues kept in an error |
| `abortEarly` | `false` | `true` stops at the first issue |

Two ways to set them. `z.config({ ... })` changes the defaults of the process and applies to schemas compiled afterwards, which means before their first use. `schema:limits({ ... })` sets them for one schema and the schemas below it (a child that has its own `:limits` keeps it). The signature of `safeParse` does not change. Values must be positive integers (or `math.huge`), and `abortEarly` a boolean; an unknown option raises an error.

```lua
local z = require("zigo")

local Items = z.array(z.integer())
local junk = {}
for i = 1, 300 do junk[i] = "x" end

local _, _, err = Items:safeParse(junk)
print(#err.issues) --> 100

local _, _, err5 = Items:limits({ maxErrors = 5 }):safeParse(junk)
print(#err5.issues) --> 5

local _, _, err1 = Items:limits({ abortEarly = true }):safeParse(junk)
print(#err1.issues) --> 1

local Small = z.array(z.integer()):limits({ maxKeys = 3 })
local _, _, tooMany = Small:safeParse({ 1, 2, 3, 4 })
print(tooMany.issues[1].code) --> too_many_keys

local Nested = z.object({ a = z.object({ b = z.integer() }) }):limits({ maxDepth = 1 })
local _, _, tooDeep = Nested:safeParse({ a = { b = 1 } })
print(tooDeep.issues[1].code) --> too_deep
```

```lua
local z = require("zigo")

z.config({ maxDepth = 8, maxErrors = 20 })
local cfg = z.config()
print(cfg.maxDepth) --> 8
print(cfg.maxKeys) --> 10000
print(cfg.codegen) --> true
```

`z.config()` without argument returns the current values (`maxDepth`, `maxKeys`, `maxErrors`, `abortEarly`, `codegen`, `null`). For network input, combine `:strict()` objects with an explicit `maxKeys` and `maxDepth`, and set `abortEarly` if you only need a yes or no.

## 14. Codegen

On first use, the valid-path test (`_test`) of a schema is compiled with `load` into one flat function. Keys and literals go through `%q` or a constants table, never through raw concatenation, so a hostile key name cannot inject code. The diagnostic pass (`_check`) always uses closures, since it only runs on failure.

If `load` is missing or refuses the code (some game sandboxes), zigo falls back to closures by itself. `z.config({ codegen = false })` forces the closures; it applies to schemas compiled afterwards. Verdicts, errors and their order are the same either way (a fuzz test compares the two implementations).

```lua
local z = require("zigo")

z.config({ codegen = false })
local S = z.string():min(1)
print(S:is("a")) --> true
print(z.config().codegen) --> false
```

## 15. Runtime differences

zigo is tested on Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT 2.1 (CI matrix, sources and bundle, with and without codegen). Only these points differ:

| | Lua 5.1 / 5.2 | Lua 5.3 / 5.4 | LuaJIT 2.1 |
| --- | --- | --- | --- |
| `integer({ strict = true })` | no integer/float distinction: `3.0` passes | refuses `3.0` | like 5.1 |
| `int64()` accepts | integral numbers up to 2^53 | native integers, integral floats up to 2^53 | `int64_t` cdata, integral numbers up to 2^53 |
| `int64({ fromString = true })` returns | number up to 2^53, `too_big` / `too_small` beyond | native integer, `too_big` / `too_small` beyond the 64-bit range | `int64_t` cdata (`tostring` gives `123LL`) |
| `cdata`, `notNullPtr` | refuse every value | refuse every value | work |
| NULL pointer equal to `nil` | no | no | yes ([section 8](#8-lua-and-ffi-types)) |

`utf8`, arrays, objects, errors and every other type give the same verdict everywhere.

## 16. LuaCATS annotations

`types/zigo.d.lua` is a `---@meta` file for [lua-language-server](https://github.com/LuaLS/lua-language-server): completion and hover for `require("zigo")`, schemas (`zigo.Node`, `zigo.SizedNode`, `zigo.ObjectNode`, `zigo.TupleNode`), errors (`zigo.Error`, `zigo.Issue`) and options. It is a definition file with no runtime code. A test checks that every public key of `zigo` is declared in it.

Where to find it: in the repository (`types/`), in the release archive (`zigo-type/zigo.d.lua`), and in the rock directory (`.../lib/luarocks/rocks-<lua version>/zigo/<version>/types/` inside your LuaRocks tree). Add it to your workspace library in `.luarc.json`:

```json
{
  "workspace.library": ["path/to/zigo/types"]
}
```

```lua
local z = require("zigo")

---@type zigo.ObjectNode
local User = z.object({ name = z.string() })
print(User:is({ name = "ann" })) --> true
```

The annotations are approximate: they describe the API, not the shape of the validated data (there is no equivalent of `z.infer`).

## 17. matchigo interop

[matchigo-lua](https://github.com/wewesss/matchigo-lua) is the pattern-matching library of the same family. zigo does not depend on it. A zigo node exposes `_test`, the function matchigo reads first when it builds a pattern, so a **schema is a matchigo pattern**: it works in `m.isMatching`, `m.compile`, `m.matcher():with`, in shapes, in `P.intersection`, `P.anyOf` and `P.select`. The test `tests/matchigo_test.lua` runs these cases against the real matchigo in CI.

```lua
local z = require("zigo")
local m = require("matchigo")
local P = m.P

local User = z.object({ name = z.string():min(1), age = z.integer():min(0) })
local Ping = z.object({ kind = z.literal("ping") })

print(m.isMatching(User, { name = "ann", age = 3 })) --> true
print(m.isMatching(User, { name = "", age = 3 })) --> false

local route = m.compile({
    { with = Ping, handler = "ping" },
    { with = User, handler = function(v) return v.name end },
    { with = z.integer():min(100), handler = "big" },
    { otherwise = "other" },
})
print(route({ kind = "ping" })) --> ping
print(route({ name = "bo", age = 2 })) --> bo
print(route(150)) --> big
print(route("zz")) --> other

local run = m.matcher()
    :with(Ping, function() return "ping" end)
    :with(User, function(v) return v.age >= 18 end, function() return "adult" end)
    :with(User, function(v) return "user:" .. v.name end)
    :otherwise("none")
print(run({ kind = "ping" })) --> ping
print(run({ name = "cy", age = 30 })) --> adult
print(run({ name = "cy", age = 9 })) --> user:cy
print(run(1)) --> none

local pick = m.compile({
    { with = P.select(User), handler = function(sel) return sel.name end },
    { otherwise = "none" },
})
print(pick({ name = "di", age = 4 })) --> di
print(pick({ name = "", age = 4 })) --> none
```

Nodes also compose inside matchigo patterns:

```lua
local z = require("zigo")
local m = require("matchigo")
local P = m.P

local User = z.object({ name = z.string():min(1), age = z.integer():min(0) })

local pat = { user = User, tag = "x" }
print(m.isMatching(pat, { user = { name = "a", age = 1 }, tag = "x" })) --> true
print(m.isMatching(pat, { user = { name = "a", age = -1 }, tag = "x" })) --> false

local either = P.anyOf(z.string(), z.boolean())
print(m.isMatching(either, false)) --> true
print(m.isMatching(either, 1)) --> false

local both = P.intersection(z.number(), P.gte(10))
print(m.isMatching(both, 11)) --> true
```

Three points to know:

- `P.union` builds a set of literal values, so `P.union(z.string(), z.boolean())` never matches. Use `P.anyOf` to combine schemas.
- matchigo only reads the verdict: with an impure schema (`transform`, `default`), the handler still receives the original value. Call `schema:parse(v)` in the handler if you need the output.
- zigo has `discriminatedUnion` for a validated union by tag; use matchigo to dispatch once the value is known to be valid.

```lua
local z = require("zigo")
local m = require("matchigo")
local P = m.P

print(m.isMatching(P.union(z.string(), z.boolean()), "a")) --> false
print(m.isMatching(P.anyOf(z.string(), z.boolean()), "a")) --> true

local Upper = z.string():transform(function(s) return s:upper() end)
local seen
local f = m.compile({
    { with = Upper, handler = function(v) seen = v return "ok" end },
    { otherwise = "no" },
})
print(f("abc")) --> ok
print(seen) --> abc
```

## 18. Performance

Measures are in [bench/results](../../bench/results/README.md), one file per runtime (Lua 5.4 and LuaJIT 2.1 are published), with the method: the reference schema, nesting, large arrays and a discriminated union of 10 variants, each against hand-written code. `bench/run.lua` reproduces them and `bench/budgets.lua` enforces the budgets for pure schemas: valid input at P50 within 1.2x of equivalent hand-written code, and no allocation on the valid path. Absolute numbers depend on the machine; do not trust those of a shared CI runner.

Three habits that matter more than any option: build schemas once at load time, prefer pure schemas on hot paths (`:strict()` over `:strip()`), and use `is` when you do not need the error.

---

Design and architecture: [DESIGN.md](../DESIGN.md) (French) · [Changelog](../../CHANGELOG.md) · [License](../../LICENSE)
