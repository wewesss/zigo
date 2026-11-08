return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local function withConfig(flag, fn)
        local previous = z.config().codegen
        z.config({ codegen = flag })
        local ok, err = pcall(fn)
        z.config({ codegen = previous })
        if not ok then error(err, 0) end
    end

    local function compiled(flag, build)
        local fn
        withConfig(flag, function() fn = build()._test end)
        return fn
    end

    local function sameVerdict(build, values)
        local generated = compiled(true, build)
        local reference = compiled(false, build)
        assertTrue(z._isGenerated(generated))
        assertFalse(z._isGenerated(reference))
        for i = 1, #values do
            assertEq(generated(values[i]), reference(values[i]))
        end
    end

    local function upper(v) return v:upper() end

    test("record: every key and every value is checked", function()
        local R = z.record(z.string():min(2), z.integer())
        assertTrue(R.pure)
        assertTrue(R:is({}))
        assertTrue(R:is({ ab = 1, cd = 2 }))
        assertFalse(R:is({ a = 1 }))
        assertFalse(R:is({ ab = "x" }))
        assertFalse(R:is({ ab = 1, [1] = 2 }))
        assertFalse(R:is("x")); assertFalse(R:is(nil)); assertFalse(R:is(1))
        local ok, value = R:safeParse({ ab = 1 })
        assertTrue(ok); assertDeepEq(value, { ab = 1 })
    end)

    test("record: numeric and boolean keys", function()
        assertTrue(z.record(z.integer(), z.string()):is({ "a", "b" }))
        assertTrue(z.record(z.integer(), z.string()):is({ [10] = "a", [-3] = "b" }))
        assertFalse(z.record(z.integer(), z.string()):is({ [1.5] = "a" }))
        assertFalse(z.record(z.integer(), z.string()):is({ a = "a" }))
        assertTrue(z.record(z.boolean(), z.integer()):is({ [true] = 1, [false] = 2 }))
        assertTrue(z.record(z.enum({ "a", "b" }), z.any()):is({ a = 1 }))
        assertFalse(z.record(z.enum({ "a", "b" }), z.any()):is({ c = 1 }))
    end)

    test("record: issues come sorted: numbers, then strings, then booleans", function()
        local R = z.record(z.string(), z.string())
        local input = { b = 1, a = 2, [3] = "x", [1] = "y", [true] = "z", [false] = "w" }
        local _, _, err = R:safeParse(input)
        local paths = {}
        for i, issue in ipairs(err.issues) do paths[i] = tostring(issue.path[1]) .. ":" .. issue.code end
        assertDeepEq(paths, {
            "1:invalid_type", "3:invalid_type", "a:invalid_type", "b:invalid_type",
            "false:invalid_type", "true:invalid_type",
        })
        assertDeepEq(err.issues[1], { path = { 1 }, code = "invalid_type", expected = "string", got = "number" })
        assertDeepEq(err.issues[3], { path = { "a" }, code = "invalid_type", expected = "string", got = "number" })
    end)

    test("record: key and value issues share the key's path", function()
        local R = z.record(z.string():min(3), z.integer())
        local _, _, err = R:safeParse({ ab = "x" })
        assertDeepEq(err.issues, {
            { path = { "ab" }, code = "too_small", expected = 3, got = 2, type = "string" },
            { path = { "ab" }, code = "invalid_type", expected = "integer", got = "string" },
        })
    end)

    test("record: the order of issues does not depend on insertion order", function()
        local R = z.record(z.string(), z.integer())
        local keys = { "k1", "k2", "k3", "k4", "k5", "k6", "k7", "k8", "k9", "k10", "k11", "k12" }
        local function render(order)
            local t = {}
            for i = 1, #order do t[order[i]] = "bad" end
            return select(3, R:safeParse(t)):format()
        end
        local forward = render(keys)
        local reversed = {}
        for i = 1, #keys do reversed[i] = keys[#keys + 1 - i] end
        assertEq(render(reversed), forward)
        for _ = 1, 20 do assertEq(render(keys), forward) end
    end)

    test("record: keys that are not strings, numbers or booleans are refused", function()
        local R = z.record(z.any(), z.any())
        assertTrue(R:is({ a = 1, [2] = 2, [true] = 3 }))
        assertFalse(R:is({ [print] = 1 }))
        assertFalse(R:is({ [{}] = 1 }))
        local input = {}
        input[{}] = 1; input[{}] = 2; input[print] = 3; input.ok = 4
        local _, _, err = R:safeParse(input)
        assertDeepEq(err.issues, {
            { path = {}, code = "unrecognized_key", got = "function" },
            { path = {}, code = "unrecognized_key", got = "table" },
        })
    end)

    test("record: non-tables are invalid_type", function()
        local _, _, err = z.record(z.string(), z.string()):safeParse("x")
        assertDeepEq(err.issues, { { path = {}, code = "invalid_type", expected = "record", got = "string" } })
    end)

    test("record: values nested in objects and arrays report the full path", function()
        local S = z.object({ r = z.record(z.string(), z.array(z.integer())) })
        local _, _, err = S:safeParse({ r = { a = { 1, "x" } } })
        assertDeepEq(err.issues, { { path = { "r", "a", 2 }, code = "invalid_type", expected = "integer", got = "string" } })
    end)

    test("record: codegen iterates with next and matches closures", function()
        local values = {
            {}, { a = 1 }, { a = "x" }, { ab = 1, cd = 2 }, { [1] = 1 }, { 1, 2, 3 }, { [true] = 1 }, { a = 1, [2] = 1 },
            { [print] = 1 }, { x = nil }, "x", 1, true, nil, setmetatable({ a = 1 }, {}), { a = 1.5 },
            { a = {} }, { a = { 1 } },
        }
        sameVerdict(function() return z.record(z.string(), z.integer()) end, values)
        sameVerdict(function() return z.record(z.string():min(2), z.any()) end, values)
        sameVerdict(function() return z.record(z.integer(), z.integer()) end, values)
        sameVerdict(function() return z.record(z.boolean(), z.integer()) end, values)
        sameVerdict(function() return z.record(z.any(), z.any()) end, values)
        sameVerdict(function() return z.record(z.unknown(), z.never()) end, values)
        sameVerdict(function() return z.record(z.never(), z.any()) end, values)
        sameVerdict(function() return z.record(z.string(), z.integer()):optional() end, values)
        sameVerdict(function() return z.record(z.string(), z.integer()) end, values)
        sameVerdict(function() return z.record(z.string(), z.array(z.integer())) end, values)
        sameVerdict(function() return z.record(z.string(), z.object({ a = z.integer() })) end, values)
        sameVerdict(function() return z.record(z.string(), z.record(z.string(), z.integer())) end, values)
        sameVerdict(function() return z.array(z.record(z.string(), z.integer())) end, { { values[2] }, { values[3] }, {} })
        sameVerdict(function() return z.object({ r = z.record(z.string(), z.integer()) }) end,
            { { r = values[2] }, { r = values[3] }, {} })
    end)

    test("record: a table with a metatable is still walked raw", function()
        local R = z.record(z.string(), z.integer())
        assertTrue(R:is(setmetatable({ a = 1 }, { __index = { b = "x" } })))
        assertFalse(R:is(setmetatable({ a = "x" }, { __index = { b = 1 } })))
    end)

    test("record: impure values give a new table with their output", function()
        local R = z.record(z.string(), z.string():transform(upper))
        assertFalse(R.pure)
        local input = { a = "x", b = "y" }
        local out = R:parse(input)
        assertDeepEq(out, { a = "X", b = "Y" })
        assertTrue(out ~= input)
        assertFalse(R:is({ a = 1 }))
        assertTrue(R:is({}))
        local _, _, err = R:safeParse({ b = 2, a = 1 })
        assertDeepEq(err.issues, {
            { path = { "a" }, code = "invalid_type", expected = "string", got = "number" },
            { path = { "b" }, code = "invalid_type", expected = "string", got = "number" },
        })
    end)

    test("record: coerce and default in values", function()
        local R = z.record(z.string(), z.coerce.number())
        assertDeepEq(R:parse({ a = "1", b = 2.5, c = "3" }), { a = 1, b = 2.5, c = 3 })
        assertFalse(R:is({ a = "x" }))
        local D = z.record(z.string(), z.string():default("d"))
        assertDeepEq(D:parse({ a = "x" }), { a = "x" })
    end)

    test("record: key issues of an impure record use the key schema", function()
        local R = z.record(z.string():min(2), z.integer():transform(function(v) return v + 1 end))
        assertDeepEq(R:parse({ ab = 1 }), { ab = 2 })
        local _, _, err = R:safeParse({ a = 1 })
        assertDeepEq(err.issues, { { path = { "a" }, code = "too_small", expected = 2, got = 1, type = "string" } })
        assertFalse(R:is({ a = 1 }))
        assertFalse(R:is({ [print] = 1 }))
    end)

    test("record: modifiers on the record itself", function()
        local R = z.record(z.string(), z.integer()):transform(function(v)
            local n = 0
            for _ in pairs(v) do n = n + 1 end
            return n
        end)
        assertFalse(R.pure)
        assertEq(R:parse({ a = 1, b = 2 }), 2)
        assertFalse(R:is({ a = "x" }))
        assertDeepEq(z.record(z.string(), z.integer()):default({}):parse(nil), {})
        assertTrue(z.record(z.string(), z.integer()):optional():is(nil))
        local P = z.record(z.string(), z.integer()):refine(function(v) return next(v) ~= nil end, { message = "empty" })
        assertTrue(P:is({ a = 1 })); assertFalse(P:is({}))
    end)

    test("record: nodes are immutable and track purity and depth", function()
        local R = z.record(z.string(), z.array(z.integer()))
        assertEq(R.maxDepth, 3)
        assertTrue(R.pure)
        assertFalse(R.isOptional); assertTrue(R:optional().isOptional)
        assertFalse(z.record(z.string(), z.integer():default(1)).pure)
        assertFalse(z.array(z.record(z.string(), z.string():transform(upper))).pure)
        assertThrows(function() R.d = {} end)
    end)

    test("record: construction errors", function()
        assertThrows(function() z.record() end)
        assertThrows(function() z.record(z.string()) end)
        assertThrows(function() z.record(1, z.string()) end)
        assertThrows(function() z.record(z.string(), {}) end)
        assertThrows(function() z.record(z.string():transform(upper), z.string()) end)
        assertThrows(function() z.record(z.coerce.number(), z.string()) end)
        assertThrows(function() z.record(z.string():default("a"), z.string()) end)
    end)
end
