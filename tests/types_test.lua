return function(env)
    local test, z = env.test, env.z
    local assertTrue = env.assertTrue

    local function readDeclarations()
        local candidates = { "types/zigo.d.lua", "./types/zigo.d.lua" }
        for i = 1, #candidates do
            local f = io.open(candidates[i], "rb")
            if f then
                local text = f:read("*a")
                f:close()
                return text
            end
        end
        error("types/zigo.d.lua not found: run the tests from the repository root", 0)
    end

    local text = (readDeclarations():gsub("\r\n", "\n"))

    local function section(startPattern)
        local from = text:find(startPattern)
        if not from then error("declaration block not found: " .. startPattern, 0) end
        local to = text:find("\n%-%-%-@class ", from + 1)
        return text:sub(from, to or #text)
    end

    local function declared(block, owner)
        local names = {}
        for name in block:gmatch("\nfunction " .. owner .. "[.:]([%w_]+)%(") do names[name] = true end
        for name in block:gmatch("\n%-%-%-@field ([%w_]+)%??") do names[name] = true end
        return names
    end

    local function sortedKeys(t)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        return keys
    end

    local function publicKeys(t)
        local out = {}
        for _, k in ipairs(sortedKeys(t)) do
            if type(k) == "string" and k:sub(1, 1) ~= "_" then out[#out + 1] = k end
        end
        return out
    end

    local function coverage(t, names, label)
        local missing = {}
        for _, k in ipairs(publicKeys(t)) do
            if not names[k] then missing[#missing + 1] = k end
        end
        if #missing > 0 then
            error(label .. " not declared in types/zigo.d.lua: " .. table.concat(missing, ", "), 0)
        end
    end

    local api = declared(section("\n%-%-%-@class zigo\n"), "zigo")
    local coerceNames = declared(section("\n%-%-%-@class zigo%.Coerce\n"), "Coerce")

    test("types: every public key of zigo is declared", function()
        coverage(z, api, "zigo keys")
    end)

    test("types: every public key of zigo.coerce is declared", function()
        assertTrue(type(z.coerce) == "table")
        coverage(z.coerce, coerceNames, "zigo.coerce keys")
    end)

    test("types: fixed-size integers and their coerce variants are declared", function()
        local names = { "u8", "u16", "u32", "i8", "i16", "i32" }
        for _, n in ipairs(names) do
            assertTrue(z[n] ~= nil)
            assertTrue(api[n])
            assertTrue(coerceNames[n])
        end
    end)

    test("types: the declarations expose no name missing at runtime", function()
        local stale = {}
        for name in pairs(coerceNames) do
            if z.coerce[name] == nil then stale[#stale + 1] = "coerce." .. name end
        end
        for name in pairs(api) do
            if z[name] == nil and name ~= "coerce" then stale[#stale + 1] = name end
        end
        table.sort(stale)
        if #stale > 0 then error("declared but absent: " .. table.concat(stale, ", "), 0) end
    end)

    test("types: node methods are declared", function()
        local expected = {
            { "zigo.Node", { "optional", "nullable", "default", "transform", "refine", "pipe", "limits", "is", "parse", "safeParse" } },
            { "zigo.SizedNode", { "min", "max", "between", "len" } },
            { "zigo.ObjectNode", { "strict", "strip" } },
            { "zigo.TupleNode", { "rest" } },
        }
        for _, group in ipairs(expected) do
            local block = section("\n%-%-%-@class " .. group[1]:gsub("%.", "%%.") .. "[ \n]")
            for _, m in ipairs(group[2]) do
                if not block:find("\nfunction [%w_]+:" .. m .. "%(") then
                    error(group[1] .. ":" .. m .. " is not declared", 0)
                end
            end
        end
        local sample = z.object({}):strict()
        for _, m in ipairs({ "optional", "nullable", "default", "transform", "refine", "pipe", "limits", "is", "parse", "safeParse", "strict", "strip" }) do
            assertTrue(type(sample[m]) == "function")
        end
    end)
end
