local huge = math.huge

local M = {}

local function tableshapeBuilders(codegen)
    local ts = require("tableshape")
    local types = ts.types
    local cg = codegen and require("tableshape.codegen") or nil

    local function whole(lo, hi)
        return types.range(lo, hi) * types.custom(function(v) return v % 1 == 0 end)
    end
    local integer = types.number * types.custom(function(v) return v % 1 == 0 end)
    local function str(lo, hi) return types.string:length(lo, hi) end
    local function object(fields) return types.shape(fields, { open = true }) end

    local function finish(node)
        if cg then
            local compiled = cg.compile(node)
            return function(v) return compiled:check_value(v) end
        end
        return function(v) return node:check_value(v) end
    end

    local notes = "integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked"
    local noHoles = "integers by predicate; unknown keys allowed (open shape)"

    return {
        s1 = function() return finish(str(3, huge)), "length by range" end,
        s2 = function()
            return finish(object({
                id = whole(1, 1000000),
                name = str(3, 32),
                role = types.one_of({ "admin", "user", "guest" }),
                active = types.boolean,
                age = whole(0, 150):is_optional(),
                tags = types.array_of(str(0, 16), { length = types.range(0, 10) }),
                address = object({ city = str(1, huge), zip = str(5, 5) }),
            })), notes
        end,
        s3 = function()
            local node = object({ n = integer, label = str(1, huge) })
            for _ = 7, 1, -1 do
                node = object({ n = integer, child = node })
            end
            return finish(node), noHoles
        end,
        s4 = function()
            return finish(types.array_of(object({
                id = whole(0, huge),
                name = str(1, huge),
                active = types.boolean,
            }))), notes
        end,
        s5 = function()
            local variants = {}
            for i = 1, 10 do
                variants[i] = object({
                    kind = types.literal("k" .. i),
                    x = whole(i, huge),
                    label = str(1, 16),
                })
            end
            return finish(types.one_of(variants)), noHoles .. "; no discriminator, variants tried in order"
        end,
    }
end

local function ljsonschemaBuilders()
    local js = require("resty.ljsonschema")

    local function finish(schema)
        return assert(js.generate_validator(schema, { array_mt = false }))
    end
    local function int(min, max) return { type = "integer", minimum = min, maximum = max } end
    local function str(min, max) return { type = "string", minLength = min, maxLength = max } end
    local function obj(properties, required)
        return { type = "object", properties = properties, required = required }
    end

    local length = "string length counted in UTF-8 characters"
    local notes = length .. "; unknown keys allowed (JSON Schema default)"
    local arrayNotes = notes .. "; arrays detected by the shape of the Lua table"

    return {
        s1 = function() return finish(str(3)), length end,
        s2 = function()
            return finish(obj({
                id = int(1, 1000000),
                name = str(3, 32),
                role = { enum = { "admin", "user", "guest" } },
                active = { type = "boolean" },
                age = int(0, 150),
                tags = { type = "array", items = str(nil, 16), maxItems = 10 },
                address = obj({ city = str(1), zip = str(5, 5) }, { "city", "zip" }),
            }, { "id", "name", "role", "active", "tags", "address" })), arrayNotes
        end,
        s3 = function()
            local node = obj({ n = int(), label = str(1) }, { "n", "label" })
            for _ = 7, 1, -1 do
                node = obj({ n = int(), child = node }, { "n", "child" })
            end
            return finish(node), notes
        end,
        s4 = function()
            return finish({
                type = "array",
                items = obj({ id = int(0), name = str(1), active = { type = "boolean" } }, { "id", "name", "active" }),
            }), arrayNotes
        end,
        s5 = function()
            local variants = {}
            for i = 1, 10 do
                variants[i] = obj({
                    kind = { enum = { "k" .. i } },
                    x = int(i),
                    label = str(1, 16),
                }, { "kind", "x", "label" })
            end
            return finish({ anyOf = variants }), notes .. "; no discriminator, anyOf tried in order"
        end,
    }
end

local function lshapeBuilders()
    local lshape = require("lshape")
    local T, check = lshape.t, lshape.check

    local function finish(schema)
        return function(v) return check.check(v, schema) end
    end

    local notes = "unknown keys allowed (open shape, default)"
    local arrayNotes = notes .. "; arrays must be dense"

    return {
        s1 = function() return finish(T.string:min_len(3)), "length by min_len" end,
        s2 = function()
            return finish(T.shape({
                id = T.integer:min(1):max(1000000),
                name = T.string:min_len(3):max_len(32),
                role = T.one_of({ "admin", "user", "guest" }),
                active = T.boolean,
                age = T.integer:min(0):max(150):is_optional(),
                tags = T.array_of(T.string:max_len(16)):max_len(10),
                address = T.shape({ city = T.string:min_len(1), zip = T.string:min_len(5):max_len(5) }),
            })), arrayNotes
        end,
        s3 = function()
            local node = T.shape({ n = T.integer, label = T.string:min_len(1) })
            for _ = 7, 1, -1 do
                node = T.shape({ n = T.integer, child = node })
            end
            return finish(node), notes
        end,
        s4 = function()
            return finish(T.array_of(T.shape({
                id = T.integer:min(0),
                name = T.string:min_len(1),
                active = T.boolean,
            }))), arrayNotes
        end,
        s5 = function()
            local variants = {}
            for i = 1, 10 do
                variants["k" .. i] = T.shape({
                    kind = T.literal("k" .. i),
                    x = T.integer:min(i),
                    label = T.string:min_len(1):max_len(16),
                })
            end
            return finish(T.discriminated("kind", variants)), notes .. "; native discriminated union"
        end,
    }
end

local function versionOf(modName, field)
    local ok, mod = pcall(require, modName)
    if ok and type(mod) == "table" and mod[field] then return tostring(mod[field]) end
    return "(version not exposed, see COMPARE.md)"
end

M.libraries = {
    {
        id = "tableshape",
        module = "tableshape",
        version = function() return versionOf("tableshape", "VERSION") end,
        variants = {
            { label = "tableshape (interpreted)", builders = function() return tableshapeBuilders(false) end },
            {
                label = "tableshape (codegen)",
                module = "tableshape.codegen",
                builders = function() return tableshapeBuilders(true) end,
            },
        },
    },
    {
        id = "ljsonschema",
        module = "resty.ljsonschema",
        version = function() return versionOf("resty.ljsonschema", "_VERSION") end,
        variants = {
            { label = "lua-resty-ljsonschema", builders = ljsonschemaBuilders },
        },
    },
    {
        id = "lshape",
        module = "lshape",
        version = function() return versionOf("lshape", "_VERSION") end,
        variants = {
            { label = "lshape", builders = lshapeBuilders },
        },
    },
}

return M
