local node = require("zigo.node")
local closures = require("zigo.compile.closures")

local M = {}

local function leaf()
    return true, 1
end

local specs = {}

for _, spec in ipairs(closures.fixedInts) do
    specs[spec[1]] = spec
    node.defineKind(spec[1], { analyze = leaf, methods = node.boundMethods(false) })
end

function M.make(name, opts, coerce)
    if opts ~= nil and type(opts) ~= "table" then
        error("zigo: " .. name .. "() expects an options table", 3)
    end
    local spec = specs[name]
    local d = {
        strict = opts ~= nil and opts.strict == true,
        typeMin = spec[2],
        typeMax = spec[3],
    }
    if coerce then d.coerce = true end
    return node.new(name, d)
end

for _, spec in ipairs(closures.fixedInts) do
    local name = spec[1]
    M[name] = function(opts) return M.make(name, opts, false) end
end

return M
