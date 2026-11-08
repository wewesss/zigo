return function(env)
    local test, z = env.test, env.z
    local assertTrue, assertEq = env.assertTrue, env.assertEq

    local SEED = 20261108
    local SCHEMAS = 4000
    local INPUTS = 8
    local MAX_DEPTH = 3

    local huge = math.huge
    local nan = 0 / 0

    local state = SEED
    local function reseed(s) state = s end
    local function nextInt()
        state = (state * 16807) % 2147483647
        return state
    end
    local function rand(n) return nextInt() % n + 1 end
    local function chance(percent) return nextInt() % 100 < percent end
    local function pick(list) return list[rand(#list)] end

    local function sortedKeys(t)
        local keys = {}
        for k in next, t do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            if ta == "boolean" then return (not a) and b end
            return a < b
        end)
        return keys
    end

    local function show(v, depth)
        depth = depth or 0
        if type(v) == "string" then return ("%q"):format(v) end
        if type(v) ~= "table" then
            local t = type(v)
            if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
            return "<" .. t .. ">"
        end
        if depth > 5 then return "{...}" end
        local parts = {}
        local keys = sortedKeys(v)
        for i = 1, #keys do
            parts[i] = "[" .. show(keys[i], depth + 1) .. "]=" .. show(rawget(v, keys[i]), depth + 1)
        end
        local suffix = getmetatable(v) ~= nil and "+mt" or ""
        return "{" .. table.concat(parts, ",") .. "}" .. suffix
    end

    local keyPool = { "a", "b", "c", "id", "name", "x y", "]]", "\0k", "k\"q", "\195\169", "__index", "1", "" }
    local numPool = { -10, -1.5, -1, 0, 0.5, 1, 2, 3, 7, 10, 100, 2 ^ 53 }
    local intPool = { 0, 1, 2, 3, 5, 8 }
    local stringPool = { "", "a", "abc", "abcdef", "xyz", "a b", "\0", "]]" }

    local function pickBounds(pool, integerOnly)
        local lo, hi = pick(pool), pick(pool)
        if lo > hi then lo, hi = hi, lo end
        if not integerOnly and chance(6) then
            if chance(50) then lo = -huge else hi = huge end
        end
        return lo, hi
    end

    local function genMods(kind, integerOnly)
        local pool = integerOnly and intPool or numPool
        local mods = {}
        local count = rand(4) - 1
        for _ = 1, count do
            local which = pick(kind == "string" and { "min", "max", "len", "between" }
                or kind == "array" and { "min", "max", "len", "between" }
                or { "min", "max", "between" })
            if which == "between" then
                local lo, hi = pickBounds(pool, integerOnly)
                mods[#mods + 1] = { "between", lo, hi }
            else
                mods[#mods + 1] = { which, pick(pool) }
            end
        end
        return mods
    end

    local leafKinds = {
        "string", "string", "string", "number", "number", "integer", "integer", "integer",
        "boolean", "boolean", "literal", "literal", "enum", "enum", "any", "unknown", "never",
    }

    local genSpec
    genSpec = function(depth)
        local roll = rand(100)
        local spec
        if depth < MAX_DEPTH and roll <= 20 then
            spec = { kind = "object", fields = {}, strict = chance(35), meta = chance(15) }
            local pool = {}
            for i = 1, #keyPool do pool[i] = keyPool[i] end
            for _ = 1, rand(6) - 1 do
                local idx = rand(#pool)
                spec.fields[#spec.fields + 1] = { key = table.remove(pool, idx), spec = genSpec(depth + 1) }
            end
        elseif depth < MAX_DEPTH and roll <= 36 then
            spec = { kind = "array", item = genSpec(depth + 1), meta = chance(20), mods = genMods("array", true) }
        else
            local kind = pick(leafKinds)
            spec = { kind = kind }
            if kind == "string" then
                spec.mods = genMods("string", true)
            elseif kind == "number" then
                spec.mods = genMods("number", false)
            elseif kind == "integer" then
                spec.strict = chance(25)
                spec.mods = genMods("integer", false)
            elseif kind == "literal" then
                local t = rand(3)
                if t == 1 then spec.value = pick(stringPool)
                elseif t == 2 then spec.value = pick(numPool)
                else spec.value = chance(50) end
            elseif kind == "enum" then
                spec.values = {}
                for i = 1, rand(4) do
                    local t = rand(4)
                    if t <= 2 then spec.values[i] = pick(stringPool)
                    elseif t == 3 then spec.values[i] = pick(numPool)
                    else spec.values[i] = chance(50) end
                end
            end
        end
        spec.optional = chance(22)
        return spec
    end

    local function describe(spec)
        local parts = { spec.kind }
        if spec.strict then parts[#parts + 1] = "strict" end
        if spec.meta then parts[#parts + 1] = "meta" end
        for _, m in ipairs(spec.mods or {}) do
            parts[#parts + 1] = m[1] .. "(" .. tostring(m[2]) .. (m[3] ~= nil and ("," .. tostring(m[3])) or "") .. ")"
        end
        if spec.value ~= nil then parts[#parts + 1] = "=" .. show(spec.value) end
        if spec.values then parts[#parts + 1] = "in " .. show(spec.values) end
        if spec.optional then parts[#parts + 1] = "optional" end
        local out = table.concat(parts, " ")
        if spec.kind == "array" then out = out .. " of (" .. describe(spec.item) .. ")" end
        if spec.kind == "object" then
            local fields = {}
            for i, f in ipairs(spec.fields) do fields[i] = show(f.key) .. ": " .. describe(f.spec) end
            out = out .. " {" .. table.concat(fields, "; ") .. "}"
        end
        return out
    end

    local function build(spec)
        local kind, n = spec.kind, nil
        if kind == "string" then n = z.string()
        elseif kind == "number" then n = z.number()
        elseif kind == "integer" then n = z.integer(spec.strict and { strict = true } or nil)
        elseif kind == "boolean" then n = z.boolean()
        elseif kind == "literal" then n = z.literal(spec.value)
        elseif kind == "enum" then n = z.enum(spec.values)
        elseif kind == "any" then n = z.any()
        elseif kind == "unknown" then n = z.unknown()
        elseif kind == "never" then n = z.never()
        elseif kind == "array" then n = z.array(build(spec.item), spec.meta and { meta = true } or nil)
        elseif kind == "object" then
            local shape = {}
            for _, f in ipairs(spec.fields) do shape[f.key] = build(f.spec) end
            n = z.object(shape, spec.meta and { meta = true } or nil)
            if spec.strict then n = n:strict() end
        end
        for _, m in ipairs(spec.mods or {}) do n = n[m[1]](n, m[2], m[3]) end
        if spec.optional then n = n:optional() end
        return n
    end

    local junkMakers = {
        function() return nil end, function() return true end, function() return false end,
        function() return 0 end, function() return -0.0 end, function() return 1 end,
        function() return -1 end, function() return 3.0 end, function() return 2.5 end,
        function() return 2 ^ 53 end, function() return 2 ^ 63 end, function() return huge end,
        function() return -huge end, function() return nan end, function() return "" end,
        function() return "a" end, function() return "abc" end, function() return "abcdef" end,
        function() return print end, function() return io.stdout end,
        function() return coroutine.create(function() end) end, function() return {} end,
        function() return { 1, 2, 3 } end, function() return { a = 1 } end,
        function() return { 1, nil, 3 } end, function() return { { a = "a" } } end,
    }
    local function junk() return pick(junkMakers)() end

    local function between(lo, hi)
        if lo ~= lo or hi ~= hi or lo == -huge or hi == huge then return 0 end
        return lo + (hi - lo) * (rand(1000) - 1) / 999
    end

    local genValid
    genValid = function(spec)
        if spec.optional and chance(25) then return nil end
        local kind = spec.kind
        if kind == "string" then
            local lo, hi, len = 0, nil, nil
            for _, m in ipairs(spec.mods) do
                if m[1] == "min" then lo = m[2]
                elseif m[1] == "max" then hi = m[2]
                elseif m[1] == "len" then len = m[2]
                else lo, hi = m[2], m[3] end
            end
            local n
            if len and chance(70) then n = len + (chance(70) and 0 or (chance(50) and -1 or 1))
            else n = lo - 1 + rand(math.max(1, (hi or lo + 4) - lo + 3)) - 1 end
            if n < 0 then n = 0 end
            local chars = {}
            for i = 1, n do chars[i] = string.char(96 + rand(5)) end
            return table.concat(chars)
        elseif kind == "number" or kind == "integer" then
            if chance(8) then return pick({ nan, huge, -huge, -0.0, 2.5, 3.0, 2 ^ 63 }) end
            local lo, hi = -10, 10
            for _, m in ipairs(spec.mods) do
                if m[1] == "min" then lo = m[2]
                elseif m[1] == "max" then hi = m[2]
                else lo, hi = m[2], m[3] end
            end
            local x
            local t = rand(4)
            if t == 1 then x = lo elseif t == 2 then x = hi
            elseif t == 3 then x = between(lo, hi)
            else x = pick({ lo - 1, hi + 1, (lo ~= lo or lo == -huge) and 0 or math.floor(between(lo, hi)) }) end
            if x ~= x or x == huge or x == -huge then return x end
            if kind == "integer" and chance(85) then
                x = math.floor(x)
                if chance(30) then x = x + 0.0 end
            end
            return x
        elseif kind == "boolean" then
            return chance(50)
        elseif kind == "literal" then
            if chance(80) then return spec.value end
            return junk()
        elseif kind == "enum" then
            if chance(80) then return pick(spec.values) end
            return junk()
        elseif kind == "any" or kind == "unknown" or kind == "never" then
            return junk()
        elseif kind == "array" then
            local lo, hi, len = 0, nil, nil
            for _, m in ipairs(spec.mods) do
                if m[1] == "min" then lo = m[2]
                elseif m[1] == "max" then hi = m[2]
                elseif m[1] == "len" then len = m[2]
                else lo, hi = m[2], m[3] end
            end
            local n
            if len and chance(70) then n = len + (chance(70) and 0 or (chance(50) and -1 or 1))
            else n = lo - 1 + rand(math.max(1, (hi or lo + 3) - lo + 3)) - 1 end
            if n < 0 then n = 0 end
            local t = {}
            for i = 1, n do t[i] = genValid(spec.item) end
            if chance(8) then t.extra = junk() end
            return t
        elseif kind == "object" then
            local t = {}
            for _, f in ipairs(spec.fields) do
                local x = genValid(f.spec)
                if x ~= nil then t[f.key] = x end
            end
            if chance(25) then t[chance(50) and "extra" or 1] = junk() end
            return t
        end
    end

    local function proxyOf(v)
        local partial = {}
        local keys = sortedKeys(v)
        for i = 1, #keys do
            if i % 2 == 1 then partial[keys[i]] = v[keys[i]] end
        end
        return setmetatable(partial, { __index = v, __len = function() return #v end })
    end

    local function mutate(v)
        if type(v) ~= "table" or getmetatable(v) ~= nil then return junk() end
        local keys = sortedKeys(v)
        local r = rand(10)
        if #keys > 0 and r <= 5 then
            local k = keys[rand(#keys)]
            v[k] = mutate(v[k])
            return v
        elseif r == 6 then
            v.zz = junk()
            return v
        elseif r == 7 then
            v[100] = 1
            return v
        elseif r == 8 and #keys > 0 then
            v[keys[rand(#keys)]] = nil
            return v
        elseif r == 9 then
            return proxyOf(v)
        end
        return junk()
    end

    local function genInput(spec)
        local roll = rand(100)
        if roll <= 40 then return genValid(spec) end
        if roll <= 85 then
            local v = genValid(spec)
            for _ = 1, rand(2) do v = mutate(v) end
            return v
        end
        return junk()
    end

    local function compileBoth(spec)
        local previous = z.config().codegen
        z.config({ codegen = true })
        local generated = build(spec)
        local gTest = generated._test
        z.config({ codegen = false })
        local reference = build(spec)
        local cTest, cCheck = reference._test, reference._check
        z.config({ codegen = previous })
        return gTest, cTest, cCheck
    end

    local function verdicts(gTest, cTest, cCheck, data)
        local okG, g = pcall(gTest, data)
        local okC, c = pcall(cTest, data)
        local okK, issues = pcall(cCheck, data, {}, 0, nil)
        return okG, g, okC, c, okK, issues == nil
    end

    test("fuzz: the generators are deterministic for a fixed seed", function()
        local function sample()
            reseed(SEED)
            local out = {}
            for i = 1, 60 do
                local spec = genSpec(0)
                out[i] = describe(spec) .. " <- " .. show(genInput(spec))
            end
            return table.concat(out, "\n")
        end
        assertEq(sample(), sample())
    end)

    test("fuzz: codegen _test == closures _test == (_check found no issue)", function()
        reseed(SEED)
        local accepted, rejected, cases = 0, 0, 0
        for s = 1, SCHEMAS do
            local spec = genSpec(0)
            local gTest, cTest, cCheck = compileBoth(spec)
            if not z._isGenerated(gTest) then
                error(("schema #%d fell back to closures: %s"):format(s, describe(spec)), 0)
            end
            for j = 1, INPUTS do
                local data = genInput(spec)
                local okG, g, okC, c, okK, k = verdicts(gTest, cTest, cCheck, data)
                cases = cases + 1
                if okG ~= okC or okC ~= okK or (okG and (g ~= c or c ~= k)) then
                    error(("mismatch on schema #%d input #%d\nschema: %s\ndata: %s\ncodegen=%s(%s) closures=%s(%s) check-clean=%s(%s)")
                        :format(s, j, describe(spec), show(data), tostring(g), tostring(okG),
                            tostring(c), tostring(okC), tostring(k), tostring(okK)), 0)
                end
                if okG then
                    if g then accepted = accepted + 1 else rejected = rejected + 1 end
                end
            end
        end
        print(("fuzz: %d cases, %d accepted, %d rejected"):format(cases, accepted, rejected))
        assertEq(cases, SCHEMAS * INPUTS)
        assertTrue(accepted >= SCHEMAS)
        assertTrue(rejected >= SCHEMAS)
    end)
end
