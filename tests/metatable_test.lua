return function(env)
    local test, z = env.test, env.z
    local assertTrue, assertFalse, assertEq = env.assertTrue, env.assertFalse, env.assertEq

    local SEED = 20261112
    local SCHEMAS = 3000
    local INPUTS = 6
    local MAX_DEPTH = 3

    local state = SEED
    local function nextInt()
        state = (state * 16807) % 2147483647
        return state
    end
    local function rand(n) return nextInt() % n + 1 end
    local function chance(percent) return nextInt() % 100 < percent end
    local function pick(list) return list[rand(#list)] end

    local function withCodegen(flag, fn)
        local previous = z.config().codegen
        z.config({ codegen = flag })
        local ok, err = pcall(fn)
        z.config({ codegen = previous })
        if not ok then error(err, 0) end
    end

    local names = { "a", "b", "c", "kind" }
    local enumValues = { "a", "b", 1, true }

    local genSpec
    local function leafSpec()
        local r = rand(9)
        if r == 1 then return { k = "string", min = chance(30) and 1 or nil } end
        if r == 2 then return { k = "number" } end
        if r == 3 then return { k = "integer" } end
        if r == 4 then return { k = "boolean" } end
        if r == 5 then return { k = "literal", v = pick({ "a", "b", 1, true }) } end
        if r == 6 then return { k = "enum" } end
        if r == 7 then return { k = "any" } end
        if r == 8 then return { k = "string" } end
        return { k = "integer" }
    end

    local function objectSpec(depth, forced)
        local spec = { k = "object", fields = {}, order = {}, strict = chance(35), meta = chance(30) }
        local count = rand(3)
        for _ = 1, count do
            local name = pick(names)
            if spec.fields[name] == nil and name ~= forced then
                spec.fields[name] = genSpec(depth + 1)
                spec.order[#spec.order + 1] = name
            end
        end
        if forced then
            spec.fields[forced.key] = { k = "literal", v = forced.value }
            spec.order[#spec.order + 1] = forced.key
        end
        return spec
    end

    genSpec = function(depth)
        local spec
        if depth >= MAX_DEPTH then
            spec = leafSpec()
        else
            local r = rand(12)
            if r <= 4 then
                spec = leafSpec()
            elseif r <= 6 then
                spec = objectSpec(depth)
            elseif r == 7 then
                spec = { k = "array", item = genSpec(depth + 1), meta = chance(30) }
                if chance(20) then spec.min = rand(2) end
                if chance(20) then spec.max = rand(3) end
            elseif r == 8 then
                spec = { k = "tuple", items = {}, meta = chance(30) }
                for i = 1, rand(3) do spec.items[i] = genSpec(depth + 1) end
                if chance(40) then spec.rest = genSpec(depth + 1) end
            elseif r == 9 then
                spec = { k = "record", key = pick({ { k = "string" }, { k = "number" }, { k = "enum" } }),
                    value = genSpec(depth + 1) }
            elseif r == 10 or r == 11 then
                spec = { k = "dunion", variants = {}, meta = chance(30) }
                local values = { "a", "b", "c" }
                for i = 1, rand(3) do
                    local v = objectSpec(depth, { key = "kind", value = values[i] })
                    v.meta = spec.meta
                    spec.variants[i] = v
                end
            else
                spec = { k = "union", variants = {} }
                for i = 1, rand(3) do spec.variants[i] = genSpec(depth + 1) end
            end
        end
        if chance(15) then spec.optional = true end
        return spec
    end

    local function build(spec)
        local k = spec.k
        local node
        if k == "string" then
            node = z.string()
            if spec.min then node = node:min(spec.min) end
        elseif k == "number" then
            node = z.number()
        elseif k == "integer" then
            node = z.integer()
        elseif k == "boolean" then
            node = z.boolean()
        elseif k == "literal" then
            node = z.literal(spec.v)
        elseif k == "enum" then
            node = z.enum(enumValues)
        elseif k == "any" then
            node = z.any()
        elseif k == "object" then
            local shape = {}
            for name, child in pairs(spec.fields) do shape[name] = build(child) end
            node = z.object(shape, spec.meta and { meta = true } or nil)
            if spec.strict then node = node:strict() end
        elseif k == "array" then
            node = z.array(build(spec.item), spec.meta and { meta = true } or nil)
            if spec.min then node = node:min(spec.min) end
            if spec.max then node = node:max(spec.max) end
        elseif k == "tuple" then
            local items = {}
            for i = 1, #spec.items do items[i] = build(spec.items[i]) end
            node = z.tuple(items, spec.meta and { meta = true } or nil)
            if spec.rest then node = node:rest(build(spec.rest)) end
        elseif k == "record" then
            node = z.record(build(spec.key), build(spec.value))
        elseif k == "dunion" then
            local variants = {}
            for i = 1, #spec.variants do variants[i] = build(spec.variants[i]) end
            node = z.discriminatedUnion("kind", table.unpack and table.unpack(variants) or unpack(variants))
        else
            local variants = {}
            for i = 1, #spec.variants do variants[i] = build(spec.variants[i]) end
            node = z.union(table.unpack and table.unpack(variants) or unpack(variants))
        end
        if spec.optional then node = node:optional() end
        return node
    end

    local function junk()
        return pick({ "x", 5, 1.5, true, false, {}, { 1 }, { a = 1 }, "a", 0 })
    end

    local genValid
    genValid = function(spec)
        local k = spec.k
        if spec.optional and chance(15) then return nil end
        if k == "string" then return spec.min and "ab" or pick({ "", "a", "ab" }) end
        if k == "number" then return pick({ 0, 1, 2.5, -3 }) end
        if k == "integer" then return pick({ 0, 1, 7, -3 }) end
        if k == "boolean" then return chance(50) end
        if k == "literal" then return spec.v end
        if k == "enum" then return pick(enumValues) end
        if k == "any" then return junk() end
        if k == "object" then
            local t = {}
            for _, name in ipairs(spec.order) do t[name] = genValid(spec.fields[name]) end
            if not spec.strict and chance(30) then t.extra = junk() end
            return t
        end
        if k == "array" then
            local n = rand(4) - 1
            if spec.min and n < spec.min then n = spec.min end
            if spec.max and n > spec.max then n = spec.max end
            local t = {}
            for i = 1, n do t[i] = genValid(spec.item) end
            return t
        end
        if k == "tuple" then
            local t = {}
            for i = 1, #spec.items do t[i] = genValid(spec.items[i]) end
            if spec.rest then
                for i = #spec.items + 1, #spec.items + rand(3) - 1 do t[i] = genValid(spec.rest) end
            end
            return t
        end
        if k == "record" then
            local t = {}
            for i = 1, rand(3) do
                local key
                if spec.key.k == "string" then key = "k" .. i
                elseif spec.key.k == "number" then key = i
                else key = pick(enumValues) end
                t[key] = genValid(spec.value)
            end
            return t
        end
        if k == "dunion" or k == "union" then
            if chance(10) then return junk() end
            return genValid(pick(spec.variants))
        end
    end

    local function mutate(v, depth)
        if type(v) ~= "table" or getmetatable(v) ~= nil or depth > 3 then return junk() end
        local keys = {}
        for key in next, v do keys[#keys + 1] = key end
        table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
        local r = rand(8)
        if #keys > 0 and r <= 3 then
            local key = pick(keys)
            v[key] = mutate(v[key], depth + 1)
        elseif #keys > 0 and r == 4 then
            v[pick(keys)] = nil
        elseif r == 5 then
            v.zz = junk()
        elseif r == 6 then
            v[#v + 2] = junk()
        elseif r == 7 and #keys > 0 then
            v[pick(keys)] = nil
            v[100] = 1
        end
        return v
    end

    local decorate
    decorate = function(v)
        if type(v) ~= "table" or getmetatable(v) ~= nil then return v end
        local keys = {}
        for key in next, v do keys[#keys + 1] = key end
        table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
        local children = {}
        for i = 1, #keys do children[keys[i]] = decorate(v[keys[i]]) end
        local len = 0
        while children[len + 1] ~= nil do len = len + 1 end
        local r = rand(7)
        if r == 1 then
            return setmetatable({}, { __index = children })
        elseif r == 2 then
            local own = {}
            for i = 1, #keys do
                if i % 2 == 1 then own[keys[i]] = children[keys[i]] end
            end
            return setmetatable(own, { __index = children, __len = function() return len end })
        elseif r == 3 then
            return setmetatable(children, {})
        elseif r == 4 then
            local own = {}
            for i = 1, #keys do
                if keys[i] ~= "a" and keys[i] ~= "kind" then own[keys[i]] = children[keys[i]] end
            end
            return setmetatable(own, { __index = function(_, key) return children[key] end })
        elseif r == 5 then
            local lying = len + rand(3) - 1
            return setmetatable(children, { __len = function() return lying end })
        elseif r == 6 then
            return setmetatable(children, { __index = function() return nil end })
        end
        return children
    end

    test("metatables: generated code agrees with closures on metatabled inputs", function()
        state = SEED
        local accepted, rejected, viaProxy = 0, 0, 0
        for s = 1, SCHEMAS do
            local spec = genSpec(0)
            local generated, reference
            withCodegen(true, function() generated = build(spec)._test end)
            withCodegen(false, function() reference = build(spec)._test end)
            assertTrue(z._isGenerated(generated))
            assertFalse(z._isGenerated(reference))
            for i = 1, INPUTS do
                local v = genValid(spec)
                if chance(35) then v = mutate(v, 0) end
                if chance(75) then v = decorate(v) end
                if type(v) == "table" and getmetatable(v) ~= nil then viaProxy = viaProxy + 1 end
                local want = reference(v)
                local got = generated(v)
                if got ~= want then
                    error(("schema #%d input #%d: generated %s, closures %s"):format(s, i, tostring(got), tostring(want)))
                end
                if want then accepted = accepted + 1 else rejected = rejected + 1 end
            end
        end
        print(("metatable fuzz: %d cases, %d accepted, %d rejected, %d metatabled")
            :format(SCHEMAS * INPUTS, accepted, rejected, viaProxy))
        assertTrue(accepted > 1000)
        assertTrue(rejected > 1000)
        assertTrue(viaProxy > 5000)
    end)

    test("metatables: a missing field supplied by __index, __len and nested rows", function()
        local function schemas(flag)
            local out
            withCodegen(flag, function()
                out = {
                    row = z.object({ id = z.integer(), name = z.string() }),
                    rowMeta = z.object({ id = z.integer(), name = z.string() }, { meta = true }),
                    rows = z.array(z.object({ id = z.integer(), name = z.string() })),
                    rowsMeta = z.array(z.object({ id = z.integer(), name = z.string() }), { meta = true }),
                    pair = z.tuple({ z.integer(), z.string() }),
                    event = z.discriminatedUnion("kind",
                        z.object({ kind = z.literal("a"), n = z.integer() }),
                        z.object({ kind = z.literal("b"), s = z.string() })),
                    bag = z.record(z.string(), z.object({ id = z.integer(), name = z.string() })),
                }
                for _, node in pairs(out) do local _ = node._test end
            end)
            return out
        end
        local gen, ref = schemas(true), schemas(false)
        local inherited = setmetatable({}, { __index = { id = 1, name = "n" } })
        local supplied = setmetatable({ id = 1 }, { __index = function(_, k) if k == "name" then return "n" end end })
        local rows = setmetatable({ { id = 1, name = "a" }, supplied }, { __len = function() return 2 end })
        local lying = setmetatable({ { id = 1, name = "a" } }, { __len = function() return 5 end })
        local pair = setmetatable({ 1, "x" }, { __index = { 3 }, __len = function() return 9 end })
        local event = setmetatable({}, { __index = { kind = "a", n = 3 } })
        local eventOwn = setmetatable({ kind = "b", s = "x" }, { __index = { s = 1 } })
        local bag = setmetatable({ k = supplied, j = { id = 2, name = "m" } }, { __index = { z = 1 } })
        local plainMeta = setmetatable({ id = 1, name = "a" }, {})
        local inputs = { inherited, supplied, rows, lying, pair, event, eventOwn, bag, plainMeta, {}, 5 }
        local verdicts = 0
        for name, schema in pairs(gen) do
            for i = 1, #inputs do
                assertEq(schema._test(inputs[i]), ref[name]._test(inputs[i]))
                verdicts = verdicts + 1
            end
        end
        assertTrue(verdicts > 0)
        assertTrue(gen.row._test(plainMeta))
        assertFalse(gen.row._test(inherited))
        assertFalse(gen.row._test(supplied))
        assertTrue(gen.rowMeta._test(inherited))
        assertTrue(gen.rowMeta._test(supplied))
        assertFalse(gen.event._test(event))
        assertTrue(gen.event._test(eventOwn))
        assertFalse(gen.rows._test(rows))
        assertTrue(gen.pair._test(pair))
    end)
end
