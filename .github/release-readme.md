# zigo — release bundle

Zod-like data validator for Lua 5.1-5.4 and LuaJIT. Pre-alpha: this release
is a skeleton, the schema API is not implemented yet.

## What's in this archive

```
zigo.lua          <- readable bundled distribution (with header)
zigo.min.lua      <- minified single-line distribution (same code)
zigo-type/        <- LuaLS / EmmyLua type definitions (.d.lua, ---@meta)
LICENSE
README.md         <- this file
```

Both `zigo.lua` and `zigo.min.lua` are functionally identical. Use the
readable one in development for stack traces, the minified one when shipping
a tight build.

## Install

Drop `zigo.lua` (or `.min.lua`) anywhere on your `package.path`, then:

```lua
local z = require("zigo")
print(z._VERSION)
```

Or load it directly:

```lua
local z = dofile("path/to/zigo.lua")
```

## LuaLS / EmmyLua type support

Drop the `zigo-type/` folder anywhere in your workspace. The language server
(`lua-language-server`) picks up `---@meta` files for completion and hover;
they contain definitions only, no runtime code.

## Documentation & sources

- Repository: https://github.com/wewesss/zigo
- Design document: `docs/DESIGN.md` on the repo.

## License

[MIT](./LICENSE) - Copyright (c) 2026 Wesley Cormier (SUP2Ak).
