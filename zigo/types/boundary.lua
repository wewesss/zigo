local node = require("zigo.node")

local M = {}

local function leaf()
    return true, 1
end

node.defineKind("bytes", { analyze = leaf, methods = node.boundMethods(true) })
node.defineKind("utf8", { analyze = leaf, methods = node.boundMethods(true) })

function M.bytes()
    return node.new("bytes", {})
end

function M.utf8()
    return node.new("utf8", {})
end

return M
