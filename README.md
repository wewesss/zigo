# zigo

[![CI](https://github.com/wewesss/zigo/actions/workflows/ci.yml/badge.svg)](https://github.com/wewesss/zigo/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/wewesss/zigo)](https://github.com/wewesss/zigo/releases/latest) [![LuaRocks](https://img.shields.io/luarocks/v/SUP2Ak/zigo?color=blue)](https://luarocks.org/modules/SUP2Ak/zigo) [![lang](https://img.shields.io/badge/lang-Lua%205.1%2B%20%2F%20LuaJIT-green)](https://github.com/wewesss/zigo) [![runtime deps](https://img.shields.io/badge/runtime%20deps-0-brightgreen)](https://github.com/wewesss/zigo) [![license](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

> "Zod-like data validator for Lua 5.1-5.4 and LuaJIT."

📖 English · [Français](./README.fr.md)

[Quick start](./docs/en/guide.md#2-quick-start) · [Primitives](./docs/en/guide.md#3-primitives) · [Containers](./docs/en/guide.md#9-containers) · [Unions](./docs/en/guide.md#10-unions-and-recursion) · [Errors](./docs/en/guide.md#12-errors) · [Network limits](./docs/en/guide.md#13-network-limits) · [matchigo interop](./docs/en/guide.md#17-matchigo-interop) · [Performance](./docs/en/guide.md#18-performance)

---

## 🧠 What is zigo?

zigo keeps the Lua side of every boundary: anything entering Lua (SQL result, FFI return, network packet, config, user input) goes through a schema that checks it and returns a safe value. Immutable fluent API, deterministic structured errors, codegen for the valid path, network limits, 64-bit integers, UTF-8, cdata and NULL sentinels. Zero dependency, single-file bundle, same family as [matchigo-lua](https://github.com/wewesss/matchigo-lua): a zigo schema is directly a matchigo pattern.

**Status: 1.0.0.** Tested on Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT 2.1.

---

## 🚀 Quickstart

```lua
local z = require("zigo")

local User = z.object({
    name = z.utf8():min(1):max(32),
    age = z.integer():between(0, 150):optional(),
    role = z.enum({ "admin", "user" }),
}):strict()

local ok, user, err = User:safeParse({ name = "", role = "root" })
print(ok) --> false
print(err:format())
--> name: Expected length of at least 1, got 0
--> role: Expected one of: "admin", "user", got "root"
```

A validated union by tag, dispatched through a hash table:

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

More in the [guide](./docs/en/guide.md), including the [matchigo interop](./docs/en/guide.md#17-matchigo-interop).

---

## 📦 Install

### LuaRocks

```sh
luarocks install zigo
```

### Download from the release

Download `zigo-<tag>.zip` (for example `zigo-v1.0.0.zip`) from the [latest release](https://github.com/wewesss/zigo/releases/latest). It holds a `zigo-<tag>/` folder with:

```
zigo.lua          <- readable bundled distribution (with header)
zigo.min.lua      <- minified single-line distribution (same code)
zigo-type/        <- LuaLS / EmmyLua type definitions (zigo.d.lua)
LICENSE
README.md
```

Put `zigo.lua` (or `zigo.min.lua`) on your `package.path`, or load it directly:

```lua
package.path = "path/to/zigo-v1.0.0/?.lua;" .. package.path
local z = require("zigo")

local z2 = dofile("path/to/zigo-v1.0.0/zigo.lua")
```

For completion and hover in [lua-language-server](https://github.com/LuaLS/lua-language-server), drop the `zigo-type/` folder in your workspace, or add it to `Lua.workspace.library` in your VSCode settings (the key is `workspace.library` in a `.luarc.json`):

```json
{
  "Lua.workspace.library": ["path/to/zigo-v1.0.0/zigo-type"]
}
```

### From source

```sh
git clone https://github.com/wewesss/zigo.git
cd zigo
lua build.lua              # -> dist/zigo.lua and dist/zigo.min.lua
lua tests/run.lua          # tests against the sources
lua tests/run.lua dist     # tests against the bundle
```

The readable bundle is about 3,600 lines (120 KB), the minified one 80 KB (`wc -c dist/*.lua`, `wc -l dist/zigo.lua`).

Tested on **Lua 5.1, 5.2, 5.3, 5.4** and **LuaJIT 2.1**. Zero dependency.

---

## ✨ Features

- **Core**: immutable schema nodes, `parse` / `safeParse` (`ok, value, err`) / `is`, `string`, `number`, `integer`, `boolean`, `literal`, `enum`, `any`, `unknown`, `never`, `object`, `array`, `:optional()`, `:min()` / `:max()` / `:between()` / `:len()`.
- **Errors**: structured errors with stable codes, `err:format()`, `err:flatten()`, replaceable English messages (`z.setMessages`, `z.messages`).
- **Codegen**: the valid path is compiled with `load` into one flat function, with an automatic fallback to closures (`z.config({ codegen = false })`). Pure schemas allocate nothing on a valid call.
- **Impure schemas**: `:default()`, `:transform()`, `:refine()`, `:pipe()`, `:strip()`, `ctx:addIssue()`, strict `z.coerce.*`.
- **Containers**: `union`, `discriminatedUnion` (hash dispatch), `tuple` with `:rest()`, `record`, `lazy` for recursive schemas.
- **Network limits**: `maxDepth` (64), `maxKeys` (10000), `maxErrors` (100), `abortEarly`, set with `z.config` or `schema:limits()`.
- **Boundary types**: `u8` ... `u32`, `i8` ... `i32`, `int64` (with `fromString`), `bytes`, `utf8` (strict RFC 3629), `cdata` and `notNullPtr` (LuaJIT), `null` / `:nullable()` with a configurable NULL sentinel, `userdata`, `instanceOf`, `func`.
- **Tooling**: LuaCATS annotations in `types/zigo.d.lua`, direct [matchigo-lua](https://github.com/wewesss/matchigo-lua) interop.

→ Full reference: [`docs/en/guide.md`](./docs/en/guide.md)

---

## 📚 Documentation

- [Guide (English)](./docs/en/guide.md) · [Guide (Français)](./docs/fr/guide.md)
- [Design and architecture](./docs/DESIGN.md) (French)
- [Benchmark results](./bench/results/README.md)
- [Changelog](./CHANGELOG.md)

---

## 🛠️ Build & tests

```sh
lua tests/run.lua                # tests against the sources
lua tests/run.lua --no-codegen   # same suite, closures only
lua build.lua                    # bundle into dist/zigo.lua and dist/zigo.min.lua
lua tests/run.lua dist           # tests against the bundle
lua bench/run.lua                # bench (needs dist/ and a matchigo-lua clone)
```

The matchigo integration test and the bench load matchigo-lua from `MATCHIGO_PATH` (default `./matchigo-lua` for the bench):

```sh
git clone --depth 1 https://github.com/wewesss/matchigo-lua.git matchigo-lua
MATCHIGO_PATH=./matchigo-lua lua tests/run.lua
```

---

## 🤝 Contributing

Read [CONTRIBUTING.md](./CONTRIBUTING.md) before opening a pull request. Community rules are in [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md), and security reports go through [SECURITY.md](./SECURITY.md).

---

## ❤️ Support

If zigo helps you:

👉 [Star the repo](https://github.com/wewesss/zigo) · [Open an issue](https://github.com/wewesss/zigo/issues) · [Sibling project: matchigo-lua](https://github.com/wewesss/matchigo-lua)

---

## 📜 License

[MIT](./LICENSE) - Copyright (c) 2026 Wesley Cormier (SUP2Ak).
