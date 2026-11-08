local node = require("zigo.node")

local M = {}

node.defineKind("array", {
    analyze = function(d)
        return d.item.pure, 1 + d.item.maxDepth
    end,
    methods = node.boundMethods(true),
})

function M.array(item, opts)
    if not node.isNode(item) then
        error("zigo: array() expects a schema", 2)
    end
    return node.new("array", { item = item, meta = opts ~= nil and opts.meta == true })
end

return M
