local node = require("zigo.node")

local M = {}

node.defineKind("tuple", {
    analyze = function(d)
        local pure, depth = true, 0
        local items = d.items
        for i = 1, #items do
            local child = items[i]
            if not child.pure then pure = false end
            if child.maxDepth > depth then depth = child.maxDepth end
        end
        local rest = d.rest
        if rest then
            if not rest.pure then pure = false end
            if rest.maxDepth > depth then depth = rest.maxDepth end
        end
        return pure, depth + 1
    end,
    methods = {
        rest = function(self, schema)
            node.assertBase(self, "rest")
            if not node.isNode(schema) then
                error("zigo: rest() expects a schema", 2)
            end
            return node.derive(self, { rest = schema })
        end,
    },
})

function M.tuple(list, opts)
    if type(list) ~= "table" then
        error("zigo: tuple() expects a list of schemas", 2)
    end
    local n, count = #list, 0
    for k in next, list do
        count = count + 1
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
            error("zigo: tuple() expects a list of schemas", 2)
        end
    end
    if count ~= n then
        error("zigo: tuple() expects a list of schemas without holes", 2)
    end
    local items = {}
    for i = 1, n do
        if not node.isNode(list[i]) then
            error("zigo: tuple() item " .. i .. " is not a schema", 2)
        end
        items[i] = list[i]
    end
    return node.new("tuple", { items = items, meta = opts ~= nil and opts.meta == true })
end

return M
