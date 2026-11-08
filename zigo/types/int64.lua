local node = require("zigo.node")

local M = {}

node.defineKind("int64", {
    analyze = function() return true, 1 end,
})

function M.int64(opts)
    if opts ~= nil and type(opts) ~= "table" then
        error("zigo: int64() expects an options table", 2)
    end
    if opts ~= nil and opts.fromString == true then
        return node.new("int64", { fromString = true, coerce = true })
    end
    return node.new("int64", {})
end

return M
