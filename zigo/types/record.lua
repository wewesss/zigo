local node = require("zigo.node")

local M = {}

node.defineKind("record", {
    analyze = function(d)
        local depth = d.key.maxDepth
        if d.value.maxDepth > depth then depth = d.value.maxDepth end
        return d.value.pure, depth + 1
    end,
})

function M.record(key, value)
    if not node.isNode(key) then
        error("zigo: record() expects a key schema", 2)
    end
    if not node.isNode(value) then
        error("zigo: record() expects a value schema", 2)
    end
    if not key.pure then
        error("zigo: record() key schema must not use default, transform, refine, pipe or coerce", 2)
    end
    return node.new("record", { key = key, value = value })
end

return M
