# zigo

> Zod-like data validator for Lua 5.1-5.4 and LuaJIT.

English · [Français](./README.fr.md)

## What is zigo?

zigo keeps the Lua side of every boundary: anything entering Lua (SQL result, FFI return, network packet, config, user input) goes through a schema that checks it and returns a safe value. Immutable fluent API, deterministic structured errors, codegen for the valid path, network limits, 64-bit integers, UTF-8, cdata and NULL sentinels. Zero dependency, single-file bundle, same family as [matchigo-lua](https://github.com/wewesss/matchigo-lua): a zigo schema is directly a matchigo pattern.

**Status: 1.0.0.** Tested on Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT 2.1.

## Install

```sh
luarocks install zigo
```

Or drop `zigo.lua` from the [release archive](https://github.com/wewesss/zigo/releases) on your `package.path`.

## Example

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

## Documentation

- [Guide (English)](./docs/en/guide.md) · [Guide (Français)](./docs/fr/guide.md)
- [Design and architecture](./docs/DESIGN.md) (French)
- [Benchmark results](./bench/results/README.md)
- [Changelog](./CHANGELOG.md)

## Development

```sh
lua tests/run.lua          # tests against the sources
lua build.lua              # bundle into dist/zigo.lua and dist/zigo.min.lua
lua tests/run.lua dist     # tests against the bundle
lua bench/run.lua          # bench (needs dist/ and a matchigo-lua clone)
```

The matchigo integration test and the bench load matchigo-lua from `MATCHIGO_PATH` (default `./matchigo-lua` for the bench):

```sh
git clone --depth 1 https://github.com/wewesss/matchigo-lua.git matchigo-lua
MATCHIGO_PATH=./matchigo-lua lua tests/run.lua
```

## License

[MIT](./LICENSE) - Copyright (c) 2026 Wesley Cormier (SUP2Ak).
