# zigo — release bundle

Zod-like data validator for Lua 5.1-5.4 and LuaJIT. Zero dependency.

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
a tight build. They expose the exact same API.

## Install

Drop `zigo.lua` (or `.min.lua`) anywhere on your `package.path`, then:

```lua
local z = require("zigo")
print(z._VERSION)

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

If `package.path` is awkward in your context, you can also load directly:

```lua
local z = dofile("path/to/zigo.lua")
```

Prefer a package manager? The same library is available from LuaRocks:

```sh
luarocks install zigo
```

## LuaLS / EmmyLua type support

Drop the `zigo-type/` folder anywhere in your workspace. The language server
(`lua-language-server`, a.k.a. `sumneko.lua`) picks up `---@meta` files for
completion, hover and type checks. They contain definitions only, no runtime
code.

VSCode users: place the folder at the workspace root and it is found
automatically. For other layouts, add the folder to your
`Lua.workspace.library` setting:

```json
{
  "Lua.workspace.library": ["path/to/zigo-type"]
}
```

## Documentation & sources

- Repository: https://github.com/wewesss/zigo
- Guide (English): https://github.com/wewesss/zigo/blob/main/docs/en/guide.md
- Guide (Français): https://github.com/wewesss/zigo/blob/main/docs/fr/guide.md
- Changelog: https://github.com/wewesss/zigo/blob/main/CHANGELOG.md
- Design document (French): https://github.com/wewesss/zigo/blob/main/docs/DESIGN.md
- LuaRocks: https://luarocks.org/modules/SUP2Ak/zigo

## License

[MIT](./LICENSE) — Copyright (c) 2026 Wesley Cormier (SUP2Ak).
