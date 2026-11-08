rockspec_format = "3.0"
package = "zigo"
version = "scm-1"

source = {
    url    = "git+https://github.com/wewesss/zigo.git",
    branch = "main",
}

description = {
    summary  = "Zod-like data validator for Lua 5.1-5.4 and LuaJIT.",
    detailed = [[
Development build (tracks main). For released versions, install zigo
without specifying scm-1.
]],
    homepage   = "https://github.com/wewesss/zigo",
    license    = "MIT",
    maintainer = "SUP2Ak <cormier.wesley@gmail.com>",
    labels     = { "validation", "schema", "validator", "zod" },
    issues_url = "https://github.com/wewesss/zigo/issues",
}

dependencies = {
    "lua >= 5.1",
}

build = {
    type = "builtin",
    modules = {
        ["zigo"]             = "zigo/init.lua",
        ["zigo.util.compat"] = "zigo/util/compat.lua",
        ["zigo.errors"]               = "zigo/errors.lua",
        ["zigo.node"]                 = "zigo/node.lua",
        ["zigo.compile.closures"]     = "zigo/compile/closures.lua",
        ["zigo.types.primitives"]     = "zigo/types/primitives.lua",
        ["zigo.types.array"]          = "zigo/types/array.lua",
        ["zigo.types.object"]         = "zigo/types/object.lua",
    },
    copy_directories = { "docs", "types" },
}

test = {
    type    = "command",
    command = "lua tests/run.lua",
}
