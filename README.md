# zigo

> Zod-like data validator for Lua 5.1-5.4 and LuaJIT.

English · [Français](./README.fr.md)

## What is zigo?

zigo keeps the Lua side of every boundary: anything entering Lua (SQL result, FFI return, network packet, config, user input) goes through a schema that checks it and returns a safe value. Zero dependency, single-file bundle, same family as [matchigo-lua](https://github.com/wewesss/matchigo-lua).

**Status: pre-alpha, skeleton.** The repository only contains the layout (`zigo/init.lua` exposing `_VERSION`, build, tests, bench, CI). The schema API is not implemented yet.

Design and architecture: [docs/DESIGN.md](./docs/DESIGN.md) (French).

## Commands

From the project root:

```sh
lua tests/run.lua          # tests against the sources
lua build.lua              # bundle into dist/zigo.lua and dist/zigo.min.lua
lua tests/run.lua dist     # tests against the bundle
lua bench/run.lua          # bench (needs dist/ and a matchigo-lua clone)
```

The bench loads matchigo-lua from `MATCHIGO_PATH` (default `./matchigo-lua`):

```sh
git clone --depth 1 https://github.com/wewesss/matchigo-lua.git matchigo-lua
```

Results are written to `bench/results/runtime-<version>.md`.

## License

[MIT](./LICENSE) - Copyright (c) 2026 Wesley Cormier (SUP2Ak).
