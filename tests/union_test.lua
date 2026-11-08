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

    local unpack = table.unpack or unpack
    local function upper(v) return v:upper() end

    local function shapes()
        return z.discriminatedUnion("kind",
            z.object({ kind = z.literal("circle"), r = z.number():min(0) }),
            z.object({ kind = z.literal("rect"), w = z.number(), h = z.number() }),
            z.object({ kind = z.literal("dot") }))
    end

    test("union: the first variant that passes wins", function()
        local U = z.union(z.string():transform(function() return "first" end), z.string())
        assertEq(U:parse("a"), "first")
        local V = z.union(z.string(), z.string():transform(function() return "second" end))
        assertEq(V:parse("a"), "a")
    end)

    test("union: pure variants are tried in order and the schema stays pure", function()
        local U = z.union(z.string(), z.integer(), z.literal(true))
        assertTrue(U.pure)
        assertTrue(U:is("a")); assertTrue(U:is(3)); assertTrue(U:is(true))
        assertFalse(U:is(false)); assertFalse(U:is(2.5)); assertFalse(U:is(nil)); assertFalse(U:is({}))
        local ok, value = U:safeParse("x")
        assertTrue(ok); assertEq(value, "x")
    end)

    test("union: a failure is one invalid_union issue carrying each variant's issues", function()
        local U = z.union(z.string(), z.integer())
        local ok, value, err = U:safeParse(true)
        assertFalse(ok); assertEq(value, nil)
        assertDeepEq(err.issues, { {
            path = {},
            code = "invalid_union",
            unionErrors = {
                { { path = {}, code = "invalid_type", expected = "string", got = "boolean" } },
                { { path = {}, code = "invalid_type", expected = "integer", got = "boolean" } },
            },
        } })
    end)

    test("union: issues of the variants keep the full path", function()
        local S = z.object({ u = z.union(z.string(), z.object({ a = z.integer() })) })
        local _, _, err = S:safeParse({ u = { a = "x" } })
        assertDeepEq(err.issues, { {
            path = { "u" },
            code = "invalid_union",
            unionErrors = {
                { { path = { "u" }, code = "invalid_type", expected = "string", got = "table" } },
                { { path = { "u", "a" }, code = "invalid_type", expected = "integer", got = "string" } },
            },
        } })
    end)

    test("union: the error message and flatten work", function()
        local _, _, err = z.union(z.string(), z.integer()):safeParse(true)
        assertEq(err:format(), "<root>: Input matches none of the union variants")
        assertEq(err:flatten().formErrors[1], "Input matches none of the union variants")
    end)

    test("union: an optional variant lets nil through, nothing else does", function()
        local U = z.union(z.string(), z.integer():optional())
        assertTrue(U:is(nil)); assertTrue(U:is("a")); assertTrue(U:is(1))
        assertFalse(U:is(true))
        assertTrue(z.object({ u = U }):is({}))
    end)

    test("union: optional() on the union itself", function()
        local U = z.union(z.string(), z.integer()):optional()
        assertTrue(U:is(nil)); assertTrue(U:is("a"))
        assertFalse(U:is(true))
    end)

    test("union: is() agrees with safeParse and parse", function()
        local U = z.union(z.string():min(2), z.array(z.integer()))
        local inputs = { "ab", "a", { 1, 2 }, { "x" }, 3, nil, true }
        for i = 1, 7 do
            local ok = U:safeParse(inputs[i])
            assertEq(U:is(inputs[i]), ok)
            assertEq((pcall(U.parse, U, inputs[i])), ok)
        end
    end)

    test("union: codegen with one sub-function per variant matches closures", function()
        local values = { "", "a", "abc", 1, 2.5, -1, true, false, {}, { 1 }, { "a" }, { a = 1 }, nil, 0 / 0 }
        sameVerdict(function() return z.union(z.string(), z.integer()) end, values)
        sameVerdict(function() return z.union(z.string():min(2), z.integer():min(0), z.array(z.string())) end, values)
        sameVerdict(function() return z.union(z.object({ a = z.integer() }), z.literal(true)) end, values)
        sameVerdict(function() return z.union(z.never(), z.any()) end, values)
        sameVerdict(function() return z.union(z.never(), z.never()) end, values)
        sameVerdict(function() return z.union(z.string(), z.integer()):optional() end, values)
        sameVerdict(function() return z.array(z.union(z.string(), z.integer())) end, values)
        sameVerdict(function() return z.object({ u = z.union(z.string(), z.integer()) }) end, values)
    end)

    test("union: more variants than inline constants", function()
        withConfig(true, function()
            local variants = {}
            for i = 1, 70 do variants[i] = z.literal(i) end
            local U = z.union(unpack(variants))
            assertTrue(z._isGenerated(U._test))
            assertTrue(U:is(1)); assertTrue(U:is(70))
            assertFalse(U:is(71)); assertFalse(U:is("1"))
        end)
    end)

    test("union: impure variants run in one pass and give their output", function()
        local U = z.union(z.integer(), z.string():transform(upper))
        assertFalse(U.pure)
        assertEq(U:parse(5), 5)
        assertEq(U:parse("ab"), "AB")
        assertTrue(U:is("ab")); assertFalse(U:is(true))
        local ok, value, err = U:safeParse(true)
        assertFalse(ok); assertEq(value, nil)
        assertEq(err.issues[1].code, "invalid_union")
        assertEq(#err.issues[1].unionErrors, 2)
    end)

    test("union: issues of a rejected variant do not leak when a later variant passes", function()
        local noisy = z.number():transform(function(v, ctx)
            ctx:addIssue({ message = "noisy" })
            return v
        end)
        local U = z.union(noisy, z.number())
        local ok, value, err = U:safeParse(4)
        assertTrue(ok); assertEq(value, 4); assertEq(err, nil)
        local W = z.object({ a = U, b = z.string() })
        local _, _, werr = W:safeParse({ a = 4, b = 1 })
        assertDeepEq(werr.issues, { { path = { "b" }, code = "invalid_type", expected = "string", got = "number" } })
    end)

    test("union: custom issues of every failed variant are reported", function()
        local U = z.union(
            z.string():refine(function() return false end, { message = "never" }),
            z.number():transform(function(v, ctx) ctx:addIssue({ message = "bad number" }) return v end))
        local _, _, err = U:safeParse(1)
        assertDeepEq(err.issues, { {
            path = {},
            code = "invalid_union",
            unionErrors = {
                { { path = {}, code = "invalid_type", expected = "string", got = "number" } },
                { { path = {}, code = "custom", message = "bad number" } },
            },
        } })
    end)

    test("union: the default of a variant applies to nil", function()
        local U = z.union(z.string():default("d"), z.integer())
        assertEq(U:parse(nil), "d")
        assertEq(U:parse(3), 3)
    end)

    test("union: modifiers on the union itself make it impure", function()
        local U = z.union(z.string(), z.integer()):transform(function(v) return { v } end)
        assertFalse(U.pure)
        assertDeepEq(U:parse("a"), { "a" })
        assertFalse(U:is(true))
    end)

    test("union: nodes are immutable and track purity and depth", function()
        local base = z.union(z.string(), z.array(z.integer()))
        local opt = base:optional()
        assertFalse(base.isOptional); assertTrue(opt.isOptional)
        assertEq(base.maxDepth, 3)
        assertTrue(base.pure)
        assertFalse(z.union(z.string(), z.string():default("x")).pure)
        assertFalse(z.array(z.union(z.string(), z.string():transform(upper))).pure)
        assertThrows(function() base.d = {} end)
    end)

    test("union: construction errors", function()
        assertThrows(function() z.union() end)
        assertThrows(function() z.union(1) end)
        assertThrows(function() z.union(z.string(), {}) end)
        assertThrows(function() z.union(z.string(), nil) end)
    end)

    test("discriminatedUnion: dispatches on the discriminant", function()
        local S = shapes()
        assertTrue(S.pure)
        assertTrue(S:is({ kind = "circle", r = 2 }))
        assertTrue(S:is({ kind = "rect", w = 1, h = 2 }))
        assertTrue(S:is({ kind = "dot", extra = 1 }))
        assertFalse(S:is({ kind = "circle", r = -1 }))
        assertFalse(S:is({ kind = "rect", w = 1 }))
    end)

    test("discriminatedUnion: a missing or unknown discriminant is invalid_union_discriminator", function()
        local S = shapes()
        local expected = { "circle", "rect", "dot" }
        local _, _, e1 = S:safeParse({ kind = "hexagon" })
        assertDeepEq(e1.issues, { { path = { "kind" }, code = "invalid_union_discriminator", expected = expected, got = "hexagon" } })
        local _, _, e2 = S:safeParse({ r = 1 })
        assertDeepEq(e2.issues, { { path = { "kind" }, code = "invalid_union_discriminator", expected = expected, got = "nil" } })
        local _, _, e3 = S:safeParse({ kind = 3 })
        assertDeepEq(e3.issues, { { path = { "kind" }, code = "invalid_union_discriminator", expected = expected, got = 3 } })
        local _, _, e4 = S:safeParse({ kind = {} })
        assertEq(e4.issues[1].got, "table")
        assertEq(e1:format(), 'kind: Expected discriminator one of: "circle", "rect", "dot", got "hexagon"')
    end)

    test("discriminatedUnion: the issue path is the key below the union's own path", function()
        local S = z.object({ shape = shapes(), list = z.array(shapes()) })
        local _, _, err = S:safeParse({ shape = { kind = "x" }, list = { { kind = "dot" }, { kind = "y" } } })
        assertDeepEq({ err.issues[1].path, err.issues[2].path }, { { "list", 2, "kind" }, { "shape", "kind" } })
    end)

    test("discriminatedUnion: non-tables are invalid_type", function()
        local S = shapes()
        local _, _, err = S:safeParse("circle")
        assertDeepEq(err.issues, { { path = {}, code = "invalid_type", expected = "object", got = "string" } })
        assertFalse(S:is(nil)); assertFalse(S:is(1)); assertFalse(S:is(true))
    end)

    test("discriminatedUnion: no sequential fallback when the discriminant is unknown", function()
        local calls = 0
        local B = z.object({ kind = z.literal("b"), v = z.integer() }):transform(function(x)
            calls = calls + 1
            return x
        end)
        local S = z.discriminatedUnion("kind", z.object({ kind = z.literal("a"), v = z.integer() }), B)
        assertFalse(S:is({ kind = "zzz", v = 1 }))
        assertEq(calls, 0)
        assertTrue(S:is({ kind = "b", v = 1 }))
        assertEq(calls, 1)
        assertTrue(S:is({ kind = "a", v = 1 }))
        assertEq(calls, 1)
    end)

    test("discriminatedUnion: a failing variant reports its own issues", function()
        local S = shapes()
        local _, _, err = S:safeParse({ kind = "rect", w = "x" })
        assertDeepEq(err.issues, {
            { path = { "h" }, code = "invalid_type", expected = "number", got = "nil" },
            { path = { "w" }, code = "invalid_type", expected = "number", got = "string" },
        })
    end)

    test("discriminatedUnion: number and boolean discriminants", function()
        local S = z.discriminatedUnion("t",
            z.object({ t = z.literal(1), a = z.string() }),
            z.object({ t = z.literal(2.5), b = z.string() }),
            z.object({ t = z.literal(true), c = z.string() }),
            z.object({ t = z.literal(false), d = z.string() }))
        assertTrue(S:is({ t = 1, a = "x" }))
        assertTrue(S:is({ t = 1.0, a = "x" }))
        assertTrue(S:is({ t = 2.5, b = "x" }))
        assertTrue(S:is({ t = true, c = "x" }))
        assertTrue(S:is({ t = false, d = "x" }))
        assertFalse(S:is({ t = "1", a = "x" }))
        assertFalse(S:is({ t = 0 / 0, a = "x" }))
        assertFalse(S:is({ t = 1, b = "x" }))
        local _, _, err = S:safeParse({ t = 7 })
        assertDeepEq(err.issues[1].expected, { 1, 2.5, true, false })
    end)

    test("discriminatedUnion: codegen dispatches through a hash and matches closures", function()
        local values = {
            { kind = "circle", r = 1 }, { kind = "circle", r = -1 }, { kind = "rect", w = 1, h = 1 },
            { kind = "rect" }, { kind = "dot" }, { kind = "dot", z = 1 }, { kind = "nope" }, { r = 1 },
            {}, "x", 1, true, nil, { kind = {} }, { kind = 1 }, setmetatable({ kind = "dot" }, {}),
            setmetatable({}, { __index = { kind = "dot" } }),
        }
        sameVerdict(shapes, values)
        sameVerdict(function() return shapes():optional() end, values)
        sameVerdict(function() return z.array(shapes()) end, { { values[1] }, { values[2] }, {}, { values[7] } })
        sameVerdict(function() return z.object({ s = shapes(), n = z.integer() }) end,
            { { s = values[1], n = 1 }, { s = values[7], n = 1 }, { s = values[1] }, { n = 1 } })
    end)

    test("discriminatedUnion: a table with a metatable is read raw unless a variant is meta", function()
        local viaIndex = setmetatable({}, { __index = { kind = "dot" } })
        assertFalse(shapes():is(viaIndex))
        local S = z.discriminatedUnion("kind",
            z.object({ kind = z.literal("dot") }, { meta = true }),
            z.object({ kind = z.literal("other") }))
        assertTrue(S:is(viaIndex))
        assertFalse(S:is(setmetatable({}, { __index = { kind = "none" } })))
    end)

    test("discriminatedUnion: strict, strip and transform variants", function()
        local S = z.discriminatedUnion("k",
            z.object({ k = z.literal("s"), a = z.integer() }):strict(),
            z.object({ k = z.literal("p"), a = z.integer() }):strip(),
            z.object({ k = z.literal("t"), a = z.integer() }):transform(function(v) return v.a end))
        assertFalse(S.pure)
        assertFalse(S:is({ k = "s", a = 1, extra = 1 }))
        assertTrue(S:is({ k = "s", a = 1 }))
        assertDeepEq(S:parse({ k = "p", a = 1, extra = 1 }), { k = "p", a = 1 })
        assertEq(S:parse({ k = "t", a = 7 }), 7)
        local _, _, err = S:safeParse({ k = "q" })
        assertEq(err.issues[1].code, "invalid_union_discriminator")
        local _, _, err2 = S:safeParse({ k = "s", a = 1, extra = 1 })
        assertDeepEq(err2.issues, { { path = { "extra" }, code = "unrecognized_key" } })
    end)

    test("discriminatedUnion: impure schemas answer is() like safeParse", function()
        local S = z.discriminatedUnion("k",
            z.object({ k = z.literal("a"), n = z.string():default("d") }),
            z.object({ k = z.literal("b"), n = z.integer():transform(function(v) return v + 1 end) }))
        assertEq(S:parse({ k = "a" }).n, "d")
        assertEq(S:parse({ k = "b", n = 1 }).n, 2)
        assertTrue(S:is({ k = "a" })); assertFalse(S:is({ k = "b" })); assertFalse(S:is({ k = "c" }))
        assertFalse(S:is(1))
    end)

    test("discriminatedUnion: hostile keys and values never reach the code as code", function()
        local nasty = { "]] os.exit() --", "]==] os.exit() --[==[", "\0", "a\"b", "a\nb", "\\", "x\\\"; os.exit() --", "" }
        local realExit, called = os.exit, false
        os.exit = function() called = true end
        local ok, err = pcall(function()
            withConfig(true, function()
                for i = 1, #nasty do
                    local s = nasty[i]
                    local S = z.discriminatedUnion(s,
                        z.object({ [s] = z.literal(s), a = z.integer() }),
                        z.object({ [s] = z.literal("other"), b = z.integer() }))
                    assertTrue(z._isGenerated(S._test))
                    assertTrue(S:is({ [s] = s, a = 1 }))
                    assertTrue(S:is({ [s] = "other", b = 1 }))
                    assertFalse(S:is({ [s] = s, b = 1 }))
                    assertFalse(S:is({ [s] = s .. "x", a = 1 }))
                    assertDeepEq(select(3, S:safeParse({})).issues[1].path, { s })
                end
            end)
        end)
        os.exit = realExit
        if not ok then error(err, 0) end
        assertFalse(called)
    end)

    test("discriminatedUnion: more variants than inline constants", function()
        withConfig(true, function()
            local variants = {}
            for i = 1, 60 do
                variants[i] = z.object({ kind = z.literal("k" .. i), x = z.integer():min(i) })
            end
            local S = z.discriminatedUnion("kind", unpack(variants))
            assertTrue(z._isGenerated(S._test))
            assertTrue(S:is({ kind = "k60", x = 60 }))
            assertFalse(S:is({ kind = "k60", x = 59 }))
            assertTrue(S:is({ kind = "k1", x = 1 }))
            assertFalse(S:is({ kind = "k61", x = 1 }))
        end)
    end)

    test("discriminatedUnion: construction fails unless every variant is an object with a literal discriminant", function()
        local function obj(fields) return z.object(fields) end
        assertThrows(function() z.discriminatedUnion("k") end)
        assertThrows(function() z.discriminatedUnion(1, obj({ k = z.literal("a") })) end)
        assertThrows(function() z.discriminatedUnion("k", z.string()) end)
        assertThrows(function() z.discriminatedUnion("k", {}) end)
        assertThrows(function() z.discriminatedUnion("k", z.array(z.string())) end)
        assertThrows(function() z.discriminatedUnion("k", obj({ other = z.literal("a") })) end)
        assertThrows(function() z.discriminatedUnion("k", obj({ k = z.string() })) end)
        assertThrows(function() z.discriminatedUnion("k", obj({ k = z.enum({ "a", "b" }) })) end)
        assertThrows(function() z.discriminatedUnion("k", obj({ k = z.literal("a"):optional() })) end)
        assertThrows(function() z.discriminatedUnion("k", obj({ k = z.literal("a"):default("a") })) end)
        assertThrows(function() z.discriminatedUnion("k", obj({ k = z.literal("a"):transform(function(v) return v end) })) end)
        assertThrows(function() z.discriminatedUnion("k", obj({ k = z.literal("a") }):optional()) end)
        assertThrows(function() z.discriminatedUnion("k", obj({ k = z.literal("a") }):default({})) end)
        assertThrows(function()
            z.discriminatedUnion("k", obj({ k = z.literal("a") }), obj({ k = z.literal("a"), x = z.string() }))
        end)
        assertThrows(function() z.discriminatedUnion("k", obj({ k = z.literal("a") }), z.string()) end)
        assertTrue(z.discriminatedUnion("k", obj({ k = z.literal("a") })):is({ k = "a" }))
    end)

    test("discriminatedUnion: nodes are immutable and track purity and depth", function()
        local S = shapes()
        local opt = S:optional()
        assertFalse(S.isOptional); assertTrue(opt.isOptional)
        assertTrue(opt:is(nil)); assertFalse(S:is(nil))
        assertEq(S.maxDepth, 3)
        assertFalse(z.discriminatedUnion("k", z.object({ k = z.literal("a") }):strip()).pure)
    end)
end
