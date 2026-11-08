local node = require("zigo.node")
local nulls = require("zigo.null")

local M = {}

local function leaf()
    return true, 1
end

node.defineKind("null", { analyze = leaf })
node.defineKind("func", { analyze = leaf })
node.defineKind("userdata", { analyze = leaf })
node.defineKind("instanceOf", { analyze = leaf })
node.defineKind("cdata", { analyze = leaf })
node.defineKind("notNullPtr", { analyze = leaf })

function M.null(sentinel)
    return node.new("null", { value = nulls.resolve(sentinel, "null") })
end

function M.func()
    return node.new("func", {})
end

function M.userdata(mt)
    if mt ~= nil and type(mt) ~= "table" then
        error("zigo: userdata() expects a metatable (a table)", 2)
    end
    return node.new("userdata", { mt = mt })
end

function M.instanceOf(mt)
    if type(mt) ~= "table" then
        error("zigo: instanceOf() expects a metatable (a table)", 2)
    end
    return node.new("instanceOf", { mt = mt })
end

local function ctypeName(ctype, who)
    local t = type(ctype)
    if t == "string" and ctype ~= "" then return ctype end
    if t == "cdata" then return tostring(ctype) end
    error("zigo: " .. who .. "() expects a C type (a string)", 3)
end

function M.cdata(ctype)
    return node.new("cdata", { ctype = ctype, name = ctypeName(ctype, "cdata") })
end

function M.notNullPtr(ctype)
    local t = type(ctype)
    if not ((t == "string" and ctype ~= "") or t == "cdata") then
        error("zigo: notNullPtr() expects a C pointer type", 2)
    end
    return node.new("notNullPtr", { ctype = ctype, name = tostring(ctype) })
end

return M
