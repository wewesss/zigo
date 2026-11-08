return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertThrows = env.assertThrows

    local function bothModes(fn)
        local previous = z.config().codegen
        for _, flag in ipairs({ true, false }) do
            z.config({ codegen = flag })
            local ok, err = pcall(fn, flag)
            if not ok then
                z.config({ codegen = previous })
                error(err, 0)
            end
        end
        z.config({ codegen = previous })
    end

    local function withConfig(opts, fn)
        local before = z.config()
        z.config(opts)
        local ok, err = pcall(fn)
        z.config({
            maxDepth = before.maxDepth, maxKeys = before.maxKeys,
            maxErrors = before.maxErrors, abortEarly = before.abortEarly,
        })
        if not ok then error(err, 0) end
    end

    local function codesOf(err)
        local codes = {}
        for i = 1, #err.issues do codes[i] = err.issues[i].code end
        return codes
    end

    local function firstCode(schema, v)
        local ok, _, err = schema:safeParse(v)
        assertFalse(ok)
        return err.issues[1].code, err
    end

    local function list(n, make)
        local t = {}
        for i = 1, n do t[i] = make(i) end
        return t
    end

    test("limits: z.config reports and validates the defaults", function()
        local c = z.config()
        assertEq(c.maxDepth, 64)
        assertEq(c.maxKeys, 10000)
        assertEq(c.maxErrors, 100)
        assertEq(c.abortEarly, false)
        assertThrows(function() z.config({ maxDepth = 0 }) end)
        assertThrows(function() z.config({ maxKeys = -1 }) end)
        assertThrows(function() z.config({ maxErrors = 1.5 }) end)
        assertThrows(function() z.config({ maxKeys = "10" }) end)
        assertThrows(function() z.config({ abortEarly = 1 }) end)
        assertThrows(function() z.config({ maxKey = 10 }) end)
        assertEq(z.config().maxKeys, 10000)
        withConfig({ maxKeys = 7, abortEarly = true }, function()
            assertEq(z.config().maxKeys, 7)
            assertEq(z.config().abortEarly, true)
        end)
        assertEq(z.config().maxKeys, 10000)
        assertEq(z.config().abortEarly, false)
    end)

    test("limits: z.config applies to schemas compiled afterwards", function()
        local S = z.array(z.integer())
        assertTrue(S:is({ 1, 2, 3, 4 }))
        withConfig({ maxKeys = 3 }, function()
            local T = z.array(z.integer())
            assertFalse(T:is({ 1, 2, 3, 4 }))
            assertTrue(T:is({ 1, 2, 3 }))
        end)
        assertTrue(S:is({ 1, 2, 3, 4 }))
    end)

    test("limits: limits() validates, merges and never mutates the source", function()
        local S = z.array(z.integer())
        assertThrows(function() S:limits("x") end)
        assertThrows(function() S:limits({ maxKeys = 0 }) end)
        assertThrows(function() S:limits({ nope = 1 }) end)
        local A = S:limits({ maxKeys = 2 })
        local B = A:limits({ maxErrors = 5 })
        assertTrue(A ~= S and B ~= A)
        assertTrue(S:is({ 1, 2, 3 }))
        assertFalse(A:is({ 1, 2, 3 }))
        assertFalse(B:is({ 1, 2, 3 }))
        assertEq(B._limits.maxKeys, 2)
        assertEq(B._limits.cap, 5)
        assertEq(S._limits.cap, 100)
        assertEq(S.pure, A.pure)
        assertEq(z.object({ a = z.string() }):limits({ maxDepth = 3 }).pure, true)
    end)

    test("limits: maxKeys on arrays, exactly at the limit", function()
        bothModes(function()
            local A = z.array(z.integer())
            assertTrue(A:is(list(10000, function(i) return i end)))
            local code, err = firstCode(A, list(10001, function(i) return i end))
            assertEq(code, "too_many_keys")
            assertEq(err.issues[1].expected, 10000)
            assertEq(err.issues[1].got, 10001)
            assertEq(#err.issues, 1)
            local B = A:limits({ maxKeys = 3 })
            assertTrue(B:is({ 1, 2, 3 }))
            assertFalse(B:is({ 1, 2, 3, 4 }))
            assertEq(firstCode(B, { 1, 2, 3, 4 }), "too_many_keys")
        end)
    end)

    test("limits: a declared max or len keeps its own issue below maxKeys", function()
        bothModes(function()
            local A = z.array(z.integer()):max(2)
            assertEq(firstCode(A, { 1, 2, 3 }), "too_big")
            local L = z.array(z.integer()):len(2):limits({ maxKeys = 5 })
            assertEq(firstCode(L, { 1, 2, 3 }), "too_big")
            assertFalse(L:is({ 1, 2, 3 }))
        end)
    end)

    test("limits: maxKeys on tuples and rest", function()
        bothModes(function()
            local T = z.tuple({ z.integer() }):rest(z.integer()):limits({ maxKeys = 3 })
            assertTrue(T:is({ 1, 2, 3 }))
            assertFalse(T:is({ 1, 2, 3, 4 }))
            assertEq(firstCode(T, { 1, 2, 3, 4 }), "too_many_keys")
            local F = z.tuple({ z.integer(), z.integer(), z.integer() }):limits({ maxKeys = 2 })
            assertFalse(F:is({ 1, 2, 3 }))
            assertEq(firstCode(F, { 1, 2, 3 }), "too_many_keys")
        end)
    end)

    test("limits: maxKeys on records", function()
        bothModes(function()
            local R = z.record(z.string(), z.integer())
            local ok = {}
            for i = 1, 10000 do ok["k" .. i] = i end
            assertTrue(R:is(ok))
            ok.extra = 1
            assertFalse(R:is(ok))
            local code, err = firstCode(R, ok)
            assertEq(code, "too_many_keys")
            assertEq(#err.issues, 1)
            local S = R:limits({ maxKeys = 2 })
            assertTrue(S:is({ a = 1, b = 2 }))
            assertFalse(S:is({ a = 1, b = 2, c = 3 }))
        end)
    end)

    test("limits: maxKeys on strict objects, never on passthrough objects", function()
        bothModes(function()
            local shape = { a = z.integer():optional() }
            local strict = z.object(shape):strict():limits({ maxKeys = 3 })
            local loose = z.object(shape):limits({ maxKeys = 3 })
            local many = { a = 1 }
            for i = 1, 20 do many["k" .. i] = i end
            assertEq(firstCode(strict, many), "too_many_keys")
            assertTrue(loose:is(many))
            local ok, out = loose:safeParse(many)
            assertTrue(ok)
            assertEq(out, many)
            local plain = z.object(shape):strict()
            assertEq(firstCode(plain, many), "unrecognized_key")
        end)
    end)

    test("limits: maxKeys on impure schemas", function()
        local function upper(s) return s:upper() end
        local A = z.array(z.string():transform(upper)):limits({ maxKeys = 2 })
        assertEq(A.pure, false)
        assertTrue(A:is({ "a", "b" }))
        assertFalse(A:is({ "a", "b", "c" }))
        assertEq(firstCode(A, { "a", "b", "c" }), "too_many_keys")
        local R = z.record(z.string(), z.string():transform(upper)):limits({ maxKeys = 1 })
        assertTrue(R:is({ a = "x" }))
        assertFalse(R:is({ a = "x", b = "y" }))
        assertEq(firstCode(R, { a = "x", b = "y" }), "too_many_keys")
        local S = z.object({ a = z.string():default("d") }):strict():limits({ maxKeys = 1 })
        assertTrue(S:is({ a = "x" }))
        assertEq(firstCode(S, { a = "x", b = 1 }), "too_many_keys")
    end)

    test("limits: maxDepth counts container levels and is checked in every mode", function()
        bothModes(function()
            local function nest(levels)
                local schema, valid, invalid = z.string(), "x", 1
                for _ = 1, levels do
                    schema = z.object({ a = schema })
                    valid = { a = valid }
                    invalid = { a = invalid }
                end
                return schema, valid, invalid
            end
            local S, valid = nest(3)
            local limited = S:limits({ maxDepth = 3 })
            assertTrue(limited:is(valid))
            assertTrue(limited:safeParse(valid))
            local T, deeper = nest(4)
            local tight = T:limits({ maxDepth = 3 })
            assertFalse(tight:is(deeper))
            local code, err = firstCode(tight, deeper)
            assertEq(code, "too_deep")
            assertEq(err.issues[1].expected, 3)
            assertEq(#err.issues[1].path, 3)
            assertTrue(T:limits({ maxDepth = 4 }):is(deeper))
        end)
    end)

    test("limits: a schema within maxDepth pays no depth check", function()
        local S = z.object({ a = z.array(z.object({ b = z.string() })) })
        assertEq(S._limits.tracked, false)
        assertEq(S:limits({ maxDepth = 3 })._limits.tracked, true)
        assertEq(S:limits({ maxDepth = 4 })._limits.tracked, false)
        local L = z.lazy(function() return S end)
        assertEq(L._limits.tracked, true)
        assertEq(z.object({ x = L })._limits.tracked, true)
        assertEq(L:limits({ maxDepth = math.huge })._limits.tracked, false)
    end)

    test("limits: maxDepth on impure schemas", function()
        local function upper(s) return s:upper() end
        local deep = z.object({ a = z.object({ b = z.object({ c = z.string():transform(upper) }) }) })
        assertEq(deep.pure, false)
        local tight = deep:limits({ maxDepth = 2 })
        assertFalse(tight:is({ a = { b = { c = "x" } } }))
        assertEq(firstCode(tight, { a = { b = { c = "x" } } }), "too_deep")
        assertTrue(deep:limits({ maxDepth = 3 }):is({ a = { b = { c = "x" } } }))
        assertTrue(deep:is({ a = { b = { c = "x" } } }))
    end)

    test("limits: an inner limits() on a nested schema keeps its own values", function()
        bothModes(function()
            local inner = z.array(z.integer()):limits({ maxKeys = 2 })
            local outer = z.object({ a = inner, b = z.array(z.integer()) })
            assertFalse(outer:is({ a = { 1, 2, 3 }, b = {} }))
            assertTrue(outer:is({ a = { 1, 2 }, b = { 1, 2, 3, 4, 5 } }))
            local tight = outer:limits({ maxKeys = 4 })
            assertTrue(tight:is({ a = { 1, 2 }, b = { 1, 2, 3, 4 } }))
            assertFalse(tight:is({ a = { 1, 2 }, b = { 1, 2, 3, 4, 5 } }))
            assertFalse(tight:is({ a = { 1, 2, 3 }, b = {} }))
        end)
    end)

    test("limits: maxErrors caps the issues, in order, for pure and impure schemas", function()
        bothModes(function()
            local items = list(500, function() return 0 end)
            local A = z.array(z.string())
            local ok, _, err = A:safeParse(items)
            assertFalse(ok)
            assertEq(#err.issues, 100)
            assertEq(err.issues[1].path[1], 1)
            assertEq(err.issues[100].path[1], 100)
            local B = A:limits({ maxErrors = 3 })
            local _, _, few = B:safeParse(items)
            assertEq(#few.issues, 3)
            assertEq(few.issues[3].path[1], 3)
            local I = z.array(z.string():transform(string.upper)):limits({ maxErrors = 4 })
            local _, _, impure = I:safeParse(items)
            assertEq(#impure.issues, 4)
            local ok2, perr = pcall(function() return B:parse(items) end)
            assertFalse(ok2)
            assertEq(#perr.issues, 3)
        end)
    end)

    test("limits: maxErrors caps unknown keys, record entries and tuple elements", function()
        bothModes(function()
            local strict = z.object({ a = z.integer() }):strict():limits({ maxErrors = 5 })
            local extra = { a = 1 }
            for i = 1, 300 do extra["k" .. i] = i end
            local _, _, err = strict:safeParse(extra)
            assertEq(#err.issues, 5)
            local R = z.record(z.string(), z.string()):limits({ maxErrors = 2 })
            local _, _, rerr = R:safeParse({ a = 1, b = 2, c = 3, d = 4 })
            assertEq(#rerr.issues, 2)
            local T = z.tuple({ z.string(), z.string(), z.string() }):limits({ maxErrors = 2 })
            local _, _, terr = T:safeParse({ 1, 2, 3 })
            assertEq(#terr.issues, 2)
        end)
    end)

    test("limits: abortEarly stops at the first issue", function()
        bothModes(function()
            local S = z.object({ a = z.string(), b = z.integer(), c = z.boolean() })
            local ok, _, err = S:safeParse({ a = 1, b = "x", c = 3 })
            assertFalse(ok)
            assertEq(#err.issues, 3)
            local Abort = S:limits({ abortEarly = true })
            local _, _, one = Abort:safeParse({ a = 1, b = "x", c = 3 })
            assertEq(#one.issues, 1)
            assertEq(one.issues[1].path[1], "a")
            withConfig({ abortEarly = true }, function()
                local G = z.object({ a = z.string(), b = z.integer() })
                local _, _, g = G:safeParse({ a = 1, b = "x" })
                assertEq(#g.issues, 1)
            end)
            local forced = S:limits({ abortEarly = false, maxErrors = 2 })
            local _, _, two = forced:safeParse({ a = 1, b = "x", c = 3 })
            assertEq(#two.issues, 2)
        end)
    end)

    test("limits: abortEarly on impure schemas never calls later fields", function()
        local calls = 0
        local S = z.object({
            a = z.string(),
            b = z.integer():refine(function() calls = calls + 1 return false end),
        }):limits({ abortEarly = true })
        assertEq(S.pure, false)
        local _, _, err = S:safeParse({ a = 1, b = 2 })
        assertEq(#err.issues, 1)
        assertEq(calls, 0)
        local _, _, both = S:limits({ abortEarly = false }):safeParse({ a = 1, b = 2 })
        assertEq(#both.issues, 2)
    end)

    test("limits: abortEarly keeps union issues down to a single one", function()
        bothModes(function()
            local U = z.union(z.string(), z.integer())
            local _, _, full = U:safeParse(true)
            assertEq(#full.issues, 1)
            assertEq(#full.issues[1].unionErrors, 2)
            local _, _, short = U:limits({ abortEarly = true }):safeParse(true)
            assertEq(#short.issues, 1)
            assertEq(short.issues[1].code, "invalid_union")
            assertEq(short.issues[1].unionErrors, nil)
            local I = z.union(z.string():transform(string.upper), z.integer()):limits({ abortEarly = true })
            local _, _, impure = I:safeParse(true)
            assertEq(#impure.issues, 1)
            assertEq(impure.issues[1].unionErrors, nil)
            assertTrue(I:is("a") and I:is(3))
        end)
    end)

    test("limits: refine and transform issues respect maxErrors", function()
        local S = z.array(z.string():refine(function() return false end)):limits({ maxErrors = 3 })
        local _, _, err = S:safeParse({ "a", "b", "c", "d", "e" })
        assertEq(#err.issues, 3)
        assertEq(codesOf(err)[1], "custom")
    end)

    test("limits: new issue codes have messages", function()
        local _, err = firstCode(z.array(z.integer()):limits({ maxKeys = 1 }), { 1, 2 })
        assertEq(err:format(), "<root>: Expected at most 1 keys")
        local S = z.object({ a = z.object({}) }):limits({ maxDepth = 1 })
        local _, deep = firstCode(S, { a = {} })
        assertEq(deep:format(), "a: Nesting deeper than 1 levels")
    end)

    test("limits: valid results are unchanged by the limits", function()
        bothModes(function()
            local S = z.object({
                tags = z.array(z.string()):max(3),
                meta = z.record(z.string(), z.integer()),
                pair = z.tuple({ z.string(), z.integer() }),
            }):strict()
            local v = { tags = { "a" }, meta = { x = 1 }, pair = { "p", 2 } }
            local ok, out = S:safeParse(v)
            assertTrue(ok)
            assertEq(out, v)
            assertTrue(S:limits({ maxKeys = 3, maxDepth = 3, abortEarly = true }):is(v))
        end)
    end)
end
