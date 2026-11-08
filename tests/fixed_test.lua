return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local huge = math.huge
    local nan = 0 / 0

    local ffi
    if jit then
        local ok, lib = pcall(require, "ffi")
        if ok then ffi = lib end
    end

    local specs = {
        { "u8", 0, 255 }, { "u16", 0, 65535 }, { "u32", 0, 4294967295 },
        { "i8", -128, 127 }, { "i16", -32768, 32767 }, { "i32", -2147483648, 2147483647 },
    }

    local function firstIssue(schema, input)
        local ok, value, err = schema:safeParse(input)
        assertFalse(ok)
        assertEq(value, nil)
        assertTrue(z.isError(err))
        return err.issues[1], err
    end

    for _, spec in ipairs(specs) do
        local name, lo, hi = spec[1], spec[2], spec[3]

        test(name .. " accepts the whole range and nothing outside it", function()
            local S = z[name]()
            assertTrue(S:is(lo)); assertTrue(S:is(hi)); assertTrue(S:is(math.floor((lo + hi) / 2)))
            assertTrue(S:is(0)); assertTrue(S:is(1))
            assertFalse(S:is(lo - 1)); assertFalse(S:is(hi + 1))
            assertFalse(S:is(lo - 1000)); assertFalse(S:is(hi + 1000))
            assertFalse(S:is(-huge)); assertFalse(S:is(huge)); assertFalse(S:is(2 ^ 63))
        end)

        test(name .. " rejects non-integers and other types", function()
            local S = z[name]()
            assertFalse(S:is(2.5)); assertFalse(S:is(nan)); assertFalse(S:is(1e300))
            assertFalse(S:is("1")); assertFalse(S:is(nil)); assertFalse(S:is(true)); assertFalse(S:is({}))
            assertFalse(S:is(print))
        end)

        test(name .. " accepts 3.0 unless { strict = true }", function()
            assertTrue(z[name]():is(3.0))
            assertTrue(z[name]():is(hi + 0.0))
            local strict = z[name]({ strict = true })
            assertTrue(strict:is(3))
            if math.type then
                assertFalse(strict:is(3.0))
            else
                assertTrue(strict:is(3.0))
            end
            assertFalse(strict:is(hi + 1)); assertFalse(strict:is(2.5))
        end)

        test(name .. " reports invalid_type, then too_small or too_big with the type bounds", function()
            local S = z[name]()
            assertDeepEq(firstIssue(S, "x"), { path = {}, code = "invalid_type", expected = name, got = "string" })
            assertDeepEq(firstIssue(S, 2.5), { path = {}, code = "invalid_type", expected = name, got = "float" })
            local big = firstIssue(S, hi + 1)
            assertDeepEq(big, { path = {}, code = "too_big", expected = hi, got = hi + 1, type = "integer" })
            local small = firstIssue(S, lo - 1)
            assertDeepEq(small, { path = {}, code = "too_small", expected = lo, got = lo - 1, type = "integer" })
        end)

        test(name .. " user min and max narrow the type bounds, never widen them", function()
            local narrowed = z[name]():min(lo + 5):max(hi - 5)
            assertTrue(narrowed:is(lo + 5)); assertTrue(narrowed:is(hi - 5))
            assertFalse(narrowed:is(lo + 4)); assertFalse(narrowed:is(hi - 4))
            assertEq(firstIssue(narrowed, hi - 4).expected, hi - 5)
            assertEq(firstIssue(narrowed, lo + 4).expected, lo + 5)
            local wide = z[name]():min(lo - 100):max(hi + 100)
            assertTrue(wide:is(lo)); assertTrue(wide:is(hi))
            assertFalse(wide:is(lo - 1)); assertFalse(wide:is(hi + 1))
            assertEq(firstIssue(wide, hi + 1).expected, hi)
            assertEq(firstIssue(wide, lo - 1).expected, lo)
            local both = z[name]():between(lo + 1, hi - 1)
            assertFalse(both:is(lo)); assertTrue(both:is(lo + 1)); assertFalse(both:is(hi))
        end)

        test(name .. " works as an optional field and in an array", function()
            local S = z.object({ n = z[name]():optional() })
            assertTrue(S:is({})); assertTrue(S:is({ n = hi })); assertFalse(S:is({ n = hi + 1 }))
            local A = z.array(z[name]())
            assertTrue(A:is({ lo, hi, 0 })); assertFalse(A:is({ lo, hi + 1 }))
            local ok, _, err = A:safeParse({ lo, hi + 1 })
            assertFalse(ok)
            assertDeepEq(err.issues[1].path, { 2 })
        end)

        test(name .. " coerce converts numeric strings and keeps the bounds", function()
            local C = z.coerce[name]()
            local ok, v = C:safeParse(tostring(hi))
            assertTrue(ok); assertEq(v, hi)
            ok, v = C:safeParse("3.0")
            assertTrue(ok); assertEq(v, 3)
            ok, v = C:safeParse(5)
            assertTrue(ok); assertEq(v, 5)
            assertEq(firstIssue(C, tostring(hi + 1)).code, "too_big")
            assertDeepEq(firstIssue(C, "abc"), { path = {}, code = "invalid_type", expected = name, got = "string" })
            assertEq(firstIssue(C, "1.5").code, "invalid_type")
            assertFalse(C:is("")); assertFalse(C:is(" 1"))
        end)
    end

    test("fixed-size integers are generated by codegen and agree with the closures", function()
        for _, spec in ipairs(specs) do
            local S = z[spec[1]]():max(spec[3] - 1)
            if z.config().codegen then
                assertTrue(z._isGenerated(S._test))
            end
            assertTrue(S:is(spec[3] - 1)); assertFalse(S:is(spec[3]))
        end
    end)

    test("fixed-size integers reject options that are not a table", function()
        assertThrows(function() z.u8(true) end)
        assertThrows(function() z.i32("strict") end)
        assertThrows(function() z.coerce.u16(1) end)
    end)

    test("fixed-size integers refuse cdata int64 values", function()
        if not ffi then return end
        local one = ffi.new("int64_t", 1)
        for _, spec in ipairs(specs) do
            assertFalse(z[spec[1]]():is(one))
            assertFalse(z[spec[1]]({ strict = true }):is(one))
            local issue = firstIssue(z[spec[1]](), one)
            assertEq(issue.code, "invalid_type"); assertEq(issue.got, "cdata")
        end
        assertFalse(z.object({ a = z.u8() }):is({ a = one }))
    end)

    test("fixed-size integers are immutable nodes with kind names", function()
        assertEq(tostring(z.u8()), "zigo.u8")
        assertEq(z.i32().kind, "i32")
        assertThrows(function() z.u8().min = 1 end)
        assertTrue(z.isNode(z.u32()))
    end)
end
