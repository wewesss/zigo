return function(env)
    local test, z = env.test, env.z
    local assertTrue, assertEq = env.assertTrue, env.assertEq

    local SEED = 20261108
    local IMPURE_SEED = 20261109
    local IMPURE_SCHEMAS = 2500
    local SCHEMAS = 4000
    local INPUTS = 8
    local MAX_DEPTH = 3

    local huge = math.huge
    local nan = 0 / 0
    local unpack = table.unpack or unpack

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
        for k in next, t do
            local tk = type(k)
            if tk == "string" or tk == "number" or tk == "boolean" then keys[#keys + 1] = k end
        end
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

    local function leafSpec(kind)
        local spec = { kind = kind }
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
        return spec
    end

    local recordKeyKinds = { "string", "string", "integer", "number", "enum", "boolean", "any", "literal" }
    local discriminantKeys = { "kind", "type", "t", "\0d", "]]" }
    local discriminantValues = { "a", "b", "c", "", 1, 2, 2.5, true, false }

    local genSpec
    genSpec = function(depth)
        local roll = rand(100)
        local spec
        if depth < MAX_DEPTH and roll <= 16 then
            spec = { kind = "object", fields = {}, strict = chance(35), meta = chance(15) }
            local pool = {}
            for i = 1, #keyPool do pool[i] = keyPool[i] end
            for _ = 1, rand(6) - 1 do
                local idx = rand(#pool)
                spec.fields[#spec.fields + 1] = { key = table.remove(pool, idx), spec = genSpec(depth + 1) }
            end
        elseif depth < MAX_DEPTH and roll <= 28 then
            spec = { kind = "array", item = genSpec(depth + 1), meta = chance(20), mods = genMods("array", true) }
        elseif depth < MAX_DEPTH and roll <= 34 then
            spec = { kind = "tuple", items = {}, meta = chance(15) }
            for i = 1, rand(4) - 1 do spec.items[i] = genSpec(depth + 1) end
            if chance(40) then spec.rest = genSpec(depth + 1) end
        elseif depth < MAX_DEPTH and roll <= 40 then
            local key = leafSpec(pick(recordKeyKinds))
            key.optional = false
            spec = { kind = "record", key = key, value = genSpec(depth + 1) }
        elseif depth < MAX_DEPTH and roll <= 46 then
            spec = { kind = "union", variants = {} }
            for i = 1, rand(3) + 1 do spec.variants[i] = genSpec(depth + 1) end
        elseif depth < MAX_DEPTH and roll <= 52 then
            spec = { kind = "dunion", key = pick(discriminantKeys), variants = {} }
            local values = {}
            for i = 1, #discriminantValues do values[i] = discriminantValues[i] end
            for i = 1, rand(3) do
                local variant = {
                    kind = "object", fields = {}, strict = chance(25), meta = chance(15),
                    variant = true, optional = false,
                }
                variant.fields[1] = {
                    key = spec.key,
                    spec = { kind = "literal", value = table.remove(values, rand(#values)), plain = true, optional = false },
                }
                local pool = {}
                for j = 1, #keyPool do
                    if keyPool[j] ~= spec.key then pool[#pool + 1] = keyPool[j] end
                end
                for _ = 1, rand(3) - 1 do
                    local idx = rand(#pool)
                    variant.fields[#variant.fields + 1] = { key = table.remove(pool, idx), spec = genSpec(depth + 2) }
                end
                spec.variants[i] = variant
            end
        else
            spec = leafSpec(pick(leafKinds))
        end
        if spec.optional == nil then spec.optional = chance(22) end
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
        if spec.strip then parts[#parts + 1] = "strip" end
        for _, step in ipairs(spec.chain or {}) do parts[#parts + 1] = step.op .. ":" .. step.def end
        if spec.default then
            parts[#parts + 1] = "default@" .. spec.default.at .. "=" .. show(spec.default.value)
        end
        if spec.optional then parts[#parts + 1] = "optional" end
        local out = table.concat(parts, " ")
        if spec.kind == "array" then out = out .. " of (" .. describe(spec.item) .. ")" end
        if spec.kind == "tuple" then
            local items = {}
            for i, item in ipairs(spec.items) do items[i] = describe(item) end
            out = out .. " (" .. table.concat(items, "; ") .. ")"
            if spec.rest then out = out .. " rest (" .. describe(spec.rest) .. ")" end
        end
        if spec.kind == "record" then
            out = out .. " (" .. describe(spec.key) .. " => " .. describe(spec.value) .. ")"
        end
        if spec.kind == "union" or spec.kind == "dunion" then
            local variants = {}
            for i, variant in ipairs(spec.variants) do variants[i] = describe(variant) end
            out = out .. (spec.key and (" on " .. show(spec.key)) or "") .. " <" .. table.concat(variants, " | ") .. ">"
        end
        if spec.kind == "object" then
            local fields = {}
            for i, f in ipairs(spec.fields) do fields[i] = show(f.key) .. ": " .. describe(f.spec) end
            out = out .. " {" .. table.concat(fields, "; ") .. "}"
        end
        return out
    end

    local transformDefs = {
        box = function(v) return { v } end,
        const = function() return 42 end,
        drop = function() return nil end,
        noNumbers = function(v, ctx)
            if type(v) == "number" then ctx:addIssue({ message = "no numbers" }) end
            return v
        end,
    }
    local transformNames = { "box", "const", "drop", "noNumbers" }

    local refineDefs = {
        notFalse = function(v) return v ~= false end,
        truthy = function(v) return v end,
        notNumber = function(v) return type(v) ~= "number" end,
        reporter = function(v, ctx)
            if type(v) == "string" then ctx:addIssue({ message = "no strings" }) end
            return true
        end,
    }
    local refineNames = { "notFalse", "truthy", "notNumber", "reporter" }

    local defaultValues = {
        5, "d", false, {}, function() return { made = true } end, function() return 7 end,
    }

    local function applyImpure(n, spec)
        local chain = spec.chain or {}
        local default = spec.default
        for i = 0, #chain do
            if default and default.at == i then n = n:default(default.value) end
            local step = chain[i + 1]
            if step then
                if step.op == "transform" then
                    n = n:transform(transformDefs[step.def])
                else
                    n = n:refine(refineDefs[step.def], { message = "refined" })
                end
            end
        end
        return n
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
            if spec.strip then n = n:strip() end
        elseif kind == "tuple" then
            local items = {}
            for i, item in ipairs(spec.items) do items[i] = build(item) end
            n = z.tuple(items, spec.meta and { meta = true } or nil)
            if spec.rest then n = n:rest(build(spec.rest)) end
        elseif kind == "record" then
            n = z.record(build(spec.key), build(spec.value))
        elseif kind == "union" or kind == "dunion" then
            local variants = {}
            for i, variant in ipairs(spec.variants) do variants[i] = build(variant) end
            if kind == "union" then
                n = z.union(unpack(variants))
            else
                n = z.discriminatedUnion(spec.key, unpack(variants))
            end
        end
        for _, m in ipairs(spec.mods or {}) do n = n[m[1]](n, m[2], m[3]) end
        n = applyImpure(n, spec)
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
        if (spec.optional or spec.default) and chance(25) then return nil end
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
        elseif kind == "tuple" then
            local t = {}
            local count = #spec.items
            local n = count
            if chance(8) then n = rand(count + 1) - 1 end
            for i = 1, n do
                local x = genValid(spec.items[i])
                if x == nil then break end
                t[i] = x
            end
            if spec.rest then
                if chance(70) then
                    for _ = 1, rand(3) - 1 do
                        local x = genValid(spec.rest)
                        if x ~= nil then t[#t + 1] = x end
                    end
                end
            elseif chance(8) then
                local x = junk()
                if x ~= nil then t[#t + 1] = x end
            end
            if chance(4) then t.extra = junk() end
            return t
        elseif kind == "record" then
            local t = {}
            for _ = 1, rand(4) - 1 do
                local k = genValid(spec.key)
                if k ~= nil and k == k then
                    local x = genValid(spec.value)
                    if x ~= nil then t[k] = x end
                end
            end
            if chance(6) then
                local k = junk()
                if k ~= nil and k == k then t[k] = junk() end
            end
            return t
        elseif kind == "union" then
            if chance(10) then return junk() end
            return genValid(pick(spec.variants))
        elseif kind == "dunion" then
            if chance(8) then return junk() end
            local t = genValid(pick(spec.variants))
            if type(t) == "table" and chance(8) then t[spec.key] = junk() end
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

    local function decorate(spec)
        if spec.kind == "object" then
            for _, f in ipairs(spec.fields) do
                if not f.spec.plain then decorate(f.spec) end
            end
        elseif spec.kind == "array" then
            decorate(spec.item)
        elseif spec.kind == "tuple" then
            for _, item in ipairs(spec.items) do decorate(item) end
            if spec.rest then decorate(spec.rest) end
        elseif spec.kind == "record" then
            decorate(spec.value)
        elseif spec.kind == "union" or spec.kind == "dunion" then
            for _, variant in ipairs(spec.variants) do decorate(variant) end
        end
        if chance(30) then
            local steps = {}
            for _ = 1, rand(3) - 1 do
                if chance(50) then
                    steps[#steps + 1] = { op = "transform", def = pick(transformNames) }
                else
                    steps[#steps + 1] = { op = "refine", def = pick(refineNames) }
                end
            end
            if #steps > 0 then spec.chain = steps end
            if chance(50) and not spec.variant then
                spec.default = { at = rand(#steps + 1) - 1, value = pick(defaultValues) }
                if chance(70) then spec.optional = false end
            end
            if spec.kind == "object" and chance(40) then spec.strip = true end
        end
    end

    local isPure

    local function allPure(list)
        for _, child in ipairs(list) do
            if not isPure(child) then return false end
        end
        return true
    end

    local function childrenPure(spec)
        local kind = spec.kind
        if kind == "object" then
            for _, f in ipairs(spec.fields) do
                if not isPure(f.spec) then return false end
            end
        elseif kind == "array" then
            return isPure(spec.item)
        elseif kind == "tuple" then
            return allPure(spec.items) and (spec.rest == nil or isPure(spec.rest))
        elseif kind == "record" then
            return isPure(spec.value)
        elseif kind == "union" or kind == "dunion" then
            return allPure(spec.variants)
        end
        return true
    end

    isPure = function(spec)
        if spec.chain or spec.default or spec.strip then return false end
        return childrenPure(spec)
    end

    local function needsStructure(spec)
        if spec.kind == "object" and spec.strip then return true end
        return not childrenPure(spec)
    end

    local newKinds = { tuple = true, record = true, union = true, dunion = true }

    local function independent(spec)
        if newKinds[spec.kind] then return true end
        if spec.kind == "object" then
            for _, f in ipairs(spec.fields) do
                if independent(f.spec) then return true end
            end
        elseif spec.kind == "array" then
            return independent(spec.item)
        end
        return false
    end

    local function baseOnly(spec)
        local copy = {}
        for k, v in pairs(spec) do copy[k] = v end
        copy.chain, copy.default, copy.optional, copy.strip = nil, nil, nil, nil
        return copy
    end

    local function same(a, b)
        if a == b then return true end
        if type(a) == "number" and type(b) == "number" then return a ~= a and b ~= b end
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        for k, x in next, a do
            if not same(x, rawget(b, k)) then return false end
        end
        for k in next, b do
            if rawget(a, k) == nil then return false end
        end
        return true
    end

    local function rawLength(t)
        if rawlen then return rawlen(t) end
        return #t
    end

    local pureSchemas = setmetatable({}, { __mode = "k" })
    local baseSchemas = setmetatable({}, { __mode = "k" })

    local function cached(cache, spec, make)
        local schema = cache[spec]
        if not schema then
            schema = build(make(spec))
            cache[spec] = schema
        end
        return schema
    end

    local oracle

    local function oracleObject(spec, v)
        if type(v) ~= "table" then return false end
        local strict = spec.strict and not spec.strip
        local out, known = {}, {}
        if not spec.strip and not strict then
            for k, x in next, v do out[k] = x end
        end
        for _, f in ipairs(spec.fields) do
            known[f.key] = true
            local x
            if spec.meta then x = v[f.key] else x = rawget(v, f.key) end
            local ok, y = oracle(f.spec, x)
            if not ok then return false end
            out[f.key] = y
        end
        if strict then
            for k in next, v do
                if not known[k] then return false end
            end
        end
        return true, out
    end

    local function oracleArray(spec, v)
        if type(v) ~= "table" then return false end
        local n
        if spec.meta then
            n = #v
            for i = 1, n do
                if v[i] == nil then return false end
            end
        else
            n = rawLength(v)
            local count = 0
            for k in next, v do
                count = count + 1
                if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
            end
            if count ~= n then return false end
        end
        local min, max, len
        for _, m in ipairs(spec.mods) do
            if m[1] == "min" then min = m[2]
            elseif m[1] == "max" then max = m[2]
            elseif m[1] == "len" then len = m[2]
            else min, max = m[2], m[3] end
        end
        if (min and n < min) or (max and n > max) or (len and n ~= len) then return false end
        local out = {}
        for i = 1, n do
            local x
            if spec.meta then x = v[i] else x = rawget(v, i) end
            local ok, y = oracle(spec.item, x)
            if not ok then return false end
            out[i] = y
        end
        return true, out
    end

    local function sequenceLength(v, meta)
        local n
        if meta then
            n = #v
            for i = 1, n do
                if v[i] == nil then return nil end
            end
            return n
        end
        n = rawLength(v)
        local count = 0
        for k in next, v do
            count = count + 1
            if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return nil end
        end
        if count ~= n then return nil end
        return n
    end

    local function oracleTuple(spec, v)
        if type(v) ~= "table" then return false end
        local n = sequenceLength(v, spec.meta)
        if not n then return false end
        local count = #spec.items
        if n > count and not spec.rest then return false end
        local out = {}
        for i = 1, n > count and n or count do
            local itemSpec = spec.items[i] or spec.rest
            local x
            if spec.meta then x = v[i] else x = rawget(v, i) end
            local ok, y = oracle(itemSpec, x)
            if not ok then return false end
            out[i] = y
        end
        return true, out
    end

    local function oracleRecord(spec, v)
        if type(v) ~= "table" then return false end
        local out = {}
        for k, x in next, v do
            local tk = type(k)
            if tk ~= "string" and tk ~= "number" and tk ~= "boolean" then return false end
            if not oracle(spec.key, k) then return false end
            local ok, y = oracle(spec.value, x)
            if not ok then return false end
            out[k] = y
        end
        return true, out
    end

    local function oracleUnion(spec, v)
        for _, variant in ipairs(spec.variants) do
            local ok, out = oracle(variant, v)
            if ok then return true, out end
        end
        return false
    end

    local function oracleDunion(spec, v)
        if type(v) ~= "table" then return false end
        local viaIndex = false
        for _, variant in ipairs(spec.variants) do
            if variant.meta then viaIndex = true end
        end
        local x
        if viaIndex then x = v[spec.key] else x = rawget(v, spec.key) end
        for _, variant in ipairs(spec.variants) do
            if variant.fields[1].spec.value == x then return oracle(variant, v) end
        end
        return false
    end

    local structuredOracles = {
        object = oracleObject, array = oracleArray, tuple = oracleTuple, record = oracleRecord,
        union = oracleUnion, dunion = oracleDunion,
    }

    local function oracleBase(spec, v)
        local structured = structuredOracles[spec.kind]
        if structured then
            if needsStructure(spec) then return structured(spec, v) end
            if independent(spec) then return structured(spec, v) and true or false, v end
        end
        return cached(baseSchemas, spec, baseOnly):is(v), v
    end

    oracle = function(spec, v)
        if isPure(spec) and not independent(spec) then
            return cached(pureSchemas, spec, function(x) return x end):is(v), v
        end
        local chain = spec.chain or {}
        local nilKind, nilAt
        if spec.optional then
            nilKind, nilAt = "optional", #chain
        elseif spec.default then
            nilKind, nilAt = "default", spec.default.at
        end
        local x, first
        if v == nil and nilKind then
            first = nilAt + 1
            if nilKind == "default" then
                local value = spec.default.value
                if type(value) == "function" then x = value() else x = value end
            end
        else
            local ok
            ok, x = oracleBase(spec, v)
            if not ok then return false end
            first = 1
        end
        for i = first, #chain do
            local step = chain[i]
            local ctx = { failed = false, addIssue = function(self) self.failed = true end }
            if step.op == "transform" then
                x = transformDefs[step.def](x, ctx)
                if ctx.failed then return false end
            else
                local pass = refineDefs[step.def](x, ctx)
                if ctx.failed or not pass then return false end
            end
        end
        return true, x
    end

    local function disagreement(schema, data, ok, out, err, expectOk, expectOut)
        if ok ~= expectOk then
            return ("verdict %s, oracle %s"):format(tostring(ok), tostring(expectOk))
        end
        if ok and not same(out, expectOut) then
            return "output differs: " .. show(out) .. " vs oracle " .. show(expectOut)
        end
        if not ok and (out ~= nil or not z.isError(err) or #err.issues < 1) then
            return "failure without a proper error object"
        end
        if schema:is(data) ~= ok then return "is() disagrees with safeParse" end
        if schema._test(data) ~= ok then return "_test disagrees with safeParse" end
        if (schema._check(data, {}, 0, nil) == nil) ~= ok then return "_check disagrees with safeParse" end
        if (pcall(schema.parse, schema, data)) ~= ok then return "parse disagrees with safeParse" end
        if not ok then
            local _, _, again = schema:safeParse(data)
            if again:format() ~= err:format() then return "issues are not deterministic" end
        end
        return nil
    end

    test("fuzz: impure schemas follow the oracle and is() == safeParse ok", function()
        reseed(IMPURE_SEED)
        local cases, accepted, rejected, impure = 0, 0, 0, 0
        for s = 1, IMPURE_SCHEMAS do
            local spec = genSpec(0)
            decorate(spec)
            local schema = build(spec)
            local pure = isPure(spec)
            if not pure then impure = impure + 1 end
            if schema.pure ~= pure then
                error(("schema #%d purity mismatch: %s\nschema: %s"):format(s, tostring(schema.pure), describe(spec)), 0)
            end
            for j = 1, INPUTS do
                local data = genInput(spec)
                local expectOk, expectOut = oracle(spec, data)
                local ran, ok, out, err = pcall(schema.safeParse, schema, data)
                local problem
                if ran then
                    problem = disagreement(schema, data, ok, out, err, expectOk, expectOut)
                else
                    problem = "safeParse raised: " .. tostring(ok)
                end
                if problem then
                    error(("%s\nschema #%d input #%d\nschema: %s\ndata: %s"):format(
                        problem, s, j, describe(spec), show(data)), 0)
                end
                cases = cases + 1
                if ok then accepted = accepted + 1 else rejected = rejected + 1 end
            end
        end
        print(("fuzz impure: %d cases, %d accepted, %d rejected, %d impure schemas"):format(
            cases, accepted, rejected, impure))
        assertEq(cases, IMPURE_SCHEMAS * INPUTS)
        assertTrue(impure >= IMPURE_SCHEMAS / 5)
        assertTrue(accepted >= IMPURE_SCHEMAS / 2)
        assertTrue(rejected >= IMPURE_SCHEMAS / 2)
    end)
end
