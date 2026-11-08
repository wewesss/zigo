local node = require("zigo.node")

local M = {}

function M.number()
    return node.new("number", { coerce = true })
end

function M.integer(opts)
    if opts ~= nil and type(opts) ~= "table" then
        error("zigo: coerce.integer() expects an options table", 2)
    end
    return node.new("integer", { strict = opts ~= nil and opts.strict == true, coerce = true })
end

function M.boolean()
    return node.new("boolean", { coerce = true })
end

function M.string()
    return node.new("string", { coerce = true })
end

return M
