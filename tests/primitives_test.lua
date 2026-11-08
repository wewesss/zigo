return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    test("string accepts strings only", function()
        local s = z.string()
        assertTrue(s:is("")); assertTrue(s:is("abc"))
        assertFalse(s:is(1)); assertFalse(s:is(nil)); assertFalse(s:is({})); assertFalse(s:is(true))
    end)

    test("string min/max/len/between count bytes at the limits", function()
        assertFalse(z.string():min(3):is("ab"))
        assertTrue(z.string():min(3):is("abc"))
        assertTrue(z.string():max(3):is("abc"))
        assertFalse(z.string():max(3):is("abcd"))
        assertTrue(z.string():len(2):is("ab"))
        assertFalse(z.string():len(2):is("abc"))
        assertFalse(z.string():len(2):is("a"))
        local b = z.string():between(2, 4)
        assertFalse(b:is("a")); assertTrue(b:is("ab")); assertTrue(b:is("abcd")); assertFalse(b:is("abcde"))
    end)

    test("string len(0) accepts only the empty string", function()
        assertTrue(z.string():len(0):is(""))
        assertFalse(z.string():len(0):is("a"))
    end)

    test("number accepts numbers only, no coercion", function()
        local n = z.number()
        assertTrue(n:is(0)); assertTrue(n:is(-1.5)); assertTrue(n:is(1e300))
        assertFalse(n:is("12")); assertFalse(n:is(nil)); assertFalse(n:is(true)); assertFalse(n:is({}))
    end)

    test("number min/max/between are inclusive", function()
        local n = z.number():between(1, 3)
        assertFalse(n:is(0.99)); assertTrue(n:is(1)); assertTrue(n:is(3)); assertFalse(n:is(3.01))
        assertTrue(z.number():min(5):is(5)); assertFalse(z.number():min(5):is(4.9))
        assertTrue(z.number():max(5):is(5)); assertFalse(z.number():max(5):is(5.1))
    end)

    test("integer accepts integral numbers, rejects fractions and strings", function()
        local i = z.integer()
        assertTrue(i:is(0)); assertTrue(i:is(-7)); assertTrue(i:is(2 ^ 31))
        assertFalse(i:is(1.5)); assertFalse(i:is("12")); assertFalse(i:is(nil)); assertFalse(i:is({}))
    end)

    test("integer between", function()
        local i = z.integer():between(0, 150)
        assertTrue(i:is(0)); assertTrue(i:is(150)); assertFalse(i:is(-1)); assertFalse(i:is(151))
        assertFalse(i:is(1.5))
    end)

    test("integer accepts 3.0 by default", function()
        assertTrue(z.integer():is(3.0))
    end)

    test("integer { strict = true } refuses 3.0 where math.type exists", function()
        local strict = z.integer({ strict = true })
        assertTrue(strict:is(3))
        if math.type then
            assertFalse(strict:is(3.0))
        else
            assertTrue(strict:is(3.0))
        end
        assertFalse(strict:is(1.5))
    end)

    test("integer rejects a non-table options argument", function()
        assertThrows(function() z.integer(true) end)
    end)

    test("boolean", function()
        local b = z.boolean()
        assertTrue(b:is(true)); assertTrue(b:is(false))
        assertFalse(b:is(0)); assertFalse(b:is("true")); assertFalse(b:is(nil))
    end)

    test("literal matches by equality", function()
        assertTrue(z.literal("a"):is("a")); assertFalse(z.literal("a"):is("b"))
        assertTrue(z.literal(1):is(1)); assertFalse(z.literal(1):is("1"))
        assertTrue(z.literal(false):is(false)); assertFalse(z.literal(false):is(nil))
    end)

    test("literal rejects NaN, nil and tables at construction", function()
        assertThrows(function() z.literal(0 / 0) end)
        assertThrows(function() z.literal(nil) end)
        assertThrows(function() z.literal({}) end)
    end)

    test("enum", function()
        local e = z.enum({ "admin", "user", "guest" })
        assertTrue(e:is("admin")); assertTrue(e:is("guest"))
        assertFalse(e:is("root")); assertFalse(e:is(nil)); assertFalse(e:is({})); assertFalse(e:is(0 / 0))
        assertTrue(z.enum({ 1, 2, true }):is(true))
    end)

    test("enum rejects empty or invalid lists", function()
        assertThrows(function() z.enum({}) end)
        assertThrows(function() z.enum("a") end)
        assertThrows(function() z.enum({ {} }) end)
    end)

    test("enum copies its values", function()
        local values = { "a", "b" }
        local e = z.enum(values)
        values[1] = "x"
        assertTrue(e:is("a")); assertFalse(e:is("x"))
    end)

    test("any and unknown accept every value including nil", function()
        for _, s in ipairs({ z.any(), z.unknown() }) do
            assertTrue(s:is(nil)); assertTrue(s:is(1)); assertTrue(s:is({})); assertTrue(s:is("x"))
            assertTrue(s:is(print))
        end
    end)

    test("never rejects everything", function()
        local n = z.never()
        assertFalse(n:is(1)); assertFalse(n:is({})); assertFalse(n:is(nil)); assertFalse(n:is(false))
    end)

    test("optional accepts nil for every kind", function()
        assertTrue(z.string():optional():is(nil))
        assertTrue(z.integer():optional():is(nil))
        assertTrue(z.never():optional():is(nil))
        assertTrue(z.string():optional():is("a"))
        assertFalse(z.string():optional():is(1))
        assertFalse(z.string():min(3):optional():is("a"))
    end)

    test("modifiers compose in any order", function()
        local a = z.string():min(2):max(4):optional()
        local b = z.string():optional():max(4):min(2)
        for _, v in ipairs({ "a", "ab", "abcd", "abcde" }) do
            assertEq(a:is(v), b:is(v))
        end
        assertEq(a:is(nil), b:is(nil))
    end)

    test("modifier arguments are validated", function()
        assertThrows(function() z.string():min("3") end)
        assertThrows(function() z.string():min(-1) end)
        assertThrows(function() z.string():len(1.5) end)
        assertThrows(function() z.number():min(0 / 0) end)
        assertThrows(function() z.number():between(5, 1) end)
    end)

    test("number kinds have no len modifier", function()
        assertThrows(function() return z.number():len(1) end)
    end)

    test("_check reports invalid_type with expected and got", function()
        local ok, v, err = z.string():safeParse(5)
        assertFalse(ok); assertEq(v, nil)
        assertDeepEq(err.issues, { { path = {}, code = "invalid_type", expected = "string", got = "number" } })
    end)

    test("_check reports size issues with expected bound and got value", function()
        local _, _, err = z.string():len(5):safeParse("a")
        assertDeepEq(err.issues, { { path = {}, code = "too_small", expected = 5, got = 1, type = "string", exact = true } })
        local _, _, err2 = z.number():max(3):safeParse(4)
        assertDeepEq(err2.issues, { { path = {}, code = "too_big", expected = 3, got = 4, type = "number" } })
    end)

    test("_check agrees with _test on a primitive corpus", function()
        local schemas = {
            z.string(), z.string():min(2):max(3), z.number():between(0, 10), z.integer(),
            z.integer({ strict = true }), z.boolean(), z.literal(1), z.enum({ "a", 2 }),
            z.any(), z.never(), z.string():optional(),
        }
        local values = { "", "ab", "abcd", 0, 1, 1.5, 3.0, 11, -1, true, false, {}, "a", 2, 0 / 0, math.huge, -math.huge }
        for _, s in ipairs(schemas) do
            for _, v in ipairs(values) do
                local ok = s._test(v)
                assertEq(s._check(v, {}, 0, nil) == nil, ok)
            end
            assertEq(s._check(nil, {}, 0, nil) == nil, s._test(nil))
        end
    end)
end
