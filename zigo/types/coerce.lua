local node = require("zigo.node")
local fixed = require("zigo.types.fixed")
local closures = require("zigo.compile.closures")

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

for _, spec in ipairs(closures.fixedInts) do
    local name = spec[1]
    M[name] = function(opts)
        return fixed.make(name, opts, true)
    end
end

function M.boolean()
    return node.new("boolean", { coerce = true })
end

function M.string()
    return node.new("string", { coerce = true })
end

return M
