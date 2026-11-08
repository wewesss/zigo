local node = require("zigo.node")

local M = {}

node.defineKind("lazy", {
    analyze = function()
        return true, math.huge
    end,
})

function M.lazy(fn)
    if type(fn) ~= "function" then
        error("zigo: lazy() expects a function returning a schema", 2)
    end
    return node.new("lazy", { fn = fn })
end

return M
