local node = require("zigo.node")

local M = {}

node.defineKind("object", {
    analyze = function(d)
        local pure, depth = true, 0
        for i = 1, #d.children do
            local child = d.children[i]
            if not child.pure then pure = false end
            if child.maxDepth > depth then depth = child.maxDepth end
        end
        return pure, depth + 1
    end,
    methods = {
        strict = function(self)
            return node.derive(self, { strict = true })
        end,
    },
})

function M.object(shape, opts)
    if type(shape) ~= "table" then
        error("zigo: object() expects a table of schemas", 2)
    end
    local keys, n = {}, 0
    for k, child in pairs(shape) do
        if type(k) ~= "string" then
            error("zigo: object() keys must be strings", 2)
        end
        if not node.isNode(child) then
            error("zigo: object() field '" .. k .. "' is not a schema", 2)
        end
        n = n + 1
        keys[n] = k
    end
    table.sort(keys)
    local children, known = {}, {}
    for i = 1, n do
        children[i] = shape[keys[i]]
        known[keys[i]] = true
    end
    return node.new("object", {
        keys = keys,
        children = children,
        known = known,
        strict = false,
        meta = opts ~= nil and opts.meta == true,
    })
end

return M
