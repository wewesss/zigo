return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local User = z.object({
        name = z.string():min(3),
        age = z.integer():between(0, 150):optional(),
        role = z.enum({ "admin", "user" }),
    })

    test("object accepts a valid table and keeps unknown keys (passthrough default)", function()
        local input = { name = "bob", role = "user", extra = 1 }
        local ok, value = User:safeParse(input)
        assertTrue(ok)
        assertEq(rawequal(value, input), true)
        assertEq(value.extra, 1)
    end)

    test("object optional field may be missing", function()
        assertTrue(User:is({ name = "bob", role = "user" }))
        assertTrue(User:is({ name = "bob", role = "user", age = 3 }))
        assertFalse(User:is({ name = "bob", role = "user", age = 200 }))
    end)

    test("object required field missing is reported with got nil", function()
        local _, _, err = User:safeParse({ name = "bob" })
        assertDeepEq(err.issues, { { path = { "role" }, code = "invalid_enum", expected = { "admin", "user" }, got = "nil" } })
    end)

    test("object rejects non-tables", function()
        assertFalse(User:is(nil)); assertFalse(User:is("x")); assertFalse(User:is(1))
        local _, _, err = User:safeParse("x")
        assertDeepEq(err.issues, { { path = {}, code = "invalid_type", expected = "object", got = "string" } })
    end)

    test("object :strict() rejects unknown keys", function()
        local S = User:strict()
        assertTrue(S:is({ name = "bob", role = "user" }))
        assertFalse(S:is({ name = "bob", role = "user", extra = 1 }))
        assertFalse(S:is({ name = "bob", role = "user", [1] = 1 }))
        local _, _, err = S:safeParse({ name = "bob", role = "user", extra = 1 })
        assertDeepEq(err.issues, { { path = { "extra" }, code = "unrecognized_key" } })
    end)

    test("object :strict() reports non-primitive unknown keys once per key type", function()
        local S = z.object({}):strict()
        local input = {}
        input[{}] = 1; input[{}] = 2; input[print] = 3
        local _, _, err = S:safeParse(input)
        assertDeepEq(err.issues, {
            { path = {}, code = "unrecognized_key", got = "function" },
            { path = {}, code = "unrecognized_key", got = "table" },
        })
    end)

    test("object keys are sorted at construction", function()
        local o = z.object({ b = z.number(), a = z.number(), c = z.number() })
        assertDeepEq(o.d.keys, { "a", "b", "c" })
    end)

    test("object validates its arguments", function()
        assertThrows(function() z.object(1) end)
        assertThrows(function() z.object({ a = 1 }) end)
        assertThrows(function() z.object({ [1] = z.string() }) end)
    end)

    test("nested object paths", function()
        local S = z.object({ address = z.object({ city = z.string():min(1), zip = z.string():len(5) }) })
        local _, _, err = S:safeParse({ address = { city = "x", zip = "1" } })
        assertDeepEq(err.issues, {
            { path = { "address", "zip" }, code = "too_small", expected = 5, got = 1, type = "string", exact = true },
        })
    end)

    test("object optional at object level", function()
        local S = z.object({ inner = z.object({ a = z.number() }):optional() })
        assertTrue(S:is({}))
        assertTrue(S:is({ inner = { a = 1 } }))
        assertFalse(S:is({ inner = {} }))
    end)

    test("array accepts sequences and checks items", function()
        local A = z.array(z.integer())
        assertTrue(A:is({})); assertTrue(A:is({ 1, 2, 3 }))
        assertFalse(A:is({ 1, "2" })); assertFalse(A:is(nil)); assertFalse(A:is("x"))
    end)

    test("array min/max/len/between count items", function()
        local item = z.number()
        assertFalse(z.array(item):min(2):is({ 1 })); assertTrue(z.array(item):min(2):is({ 1, 2 }))
        assertTrue(z.array(item):max(2):is({ 1, 2 })); assertFalse(z.array(item):max(2):is({ 1, 2, 3 }))
        assertTrue(z.array(item):len(2):is({ 1, 2 })); assertFalse(z.array(item):len(2):is({ 1 }))
        assertTrue(z.array(item):between(1, 2):is({ 1 })); assertFalse(z.array(item):between(1, 2):is({}))
    end)

    test("array item error paths use the index", function()
        local A = z.object({ tags = z.array(z.string():max(2)) })
        local _, _, err = A:safeParse({ tags = { "a", "abc", "b", "xyz" } })
        assertDeepEq(err.issues, {
            { path = { "tags", 2 }, code = "too_big", expected = 2, got = 3, type = "string" },
            { path = { "tags", 4 }, code = "too_big", expected = 2, got = 3, type = "string" },
        })
    end)

    test("array size issue precedes item issues", function()
        local _, _, err = z.array(z.number()):min(5):safeParse({ "a" })
        assertEq(err.issues[1].code, "too_small")
        assertEq(err.issues[2].path[1], 1)
    end)

    test("array of objects nests paths", function()
        local A = z.array(z.object({ id = z.integer() }))
        local _, _, err = A:safeParse({ { id = 1 }, { id = "x" } })
        assertDeepEq(err.issues, { { path = { 2, "id" }, code = "invalid_type", expected = "integer", got = "string" } })
    end)

    test("array of optional items cannot hold nil (holes are rejected)", function()
        assertFalse(z.array(z.number():optional()):is({ 1, nil, 3 }))
    end)

    test("array reports invalid_array for non-sequences", function()
        local _, _, err = z.array(z.number()):safeParse({ 1, 2, a = 3 })
        assertDeepEq(err.issues, { { path = {}, code = "invalid_array", expected = "sequence", got = "table" } })
    end)

    test("array rejects non-schema argument", function()
        assertThrows(function() z.array("x") end)
    end)

    test("flags: purity and maxDepth are computed at construction", function()
        assertEq(z.string().maxDepth, 1)
        assertEq(z.string().pure, true)
        local S = z.object({ a = z.array(z.object({ b = z.number() })) })
        assertEq(S.maxDepth, 4)
        assertEq(S.pure, true)
        assertEq(z.string():optional().isOptional, true)
        assertEq(z.string().isOptional, false)
    end)

    test("_check agrees with _test on an object/array corpus", function()
        local S = z.object({
            a = z.array(z.integer()):max(2),
            b = z.object({ c = z.string() }):optional(),
        }):strict()
        local values = {
            {}, { a = {} }, { a = { 1, 2 } }, { a = { 1, 2, 3 } }, { a = { "x" } },
            { a = {}, b = {} }, { a = {}, b = { c = "x" } }, { a = {}, z = 1 }, "x", 1,
            { a = { 1, nil, 3 } }, { a = { [2] = 1 } },
        }
        for _, v in ipairs(values) do
            assertEq(S._check(v, {}, 0, nil) == nil, S._test(v))
        end
    end)
end
