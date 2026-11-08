return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local function accepts(schema, input, expected)
        local ok, value = schema:safeParse(input)
        assertTrue(ok)
        assertEq(value, expected)
    end

    local function rejects(schema, input)
        local ok, value, err = schema:safeParse(input)
        assertFalse(ok)
        assertEq(value, nil)
        assertTrue(z.isError(err))
        assertFalse(schema:is(input))
        return err
    end

    test("coerce.number: numbers pass through and numeric strings convert", function()
        local S = z.coerce.number()
        accepts(S, 5, 5)
        accepts(S, -1.5, -1.5)
        accepts(S, "12", 12)
        accepts(S, "-3.25", -3.25)
        accepts(S, "1e3", 1000)
        accepts(S, "0x10", 16)
    end)

    test("coerce.number: spaces, empty strings and other types are refused", function()
        local S = z.coerce.number()
        for _, bad in ipairs({ " 1", "1 ", "1 2", "", " ", "abc", "1,5", "nan", "inf", "\t1", "1\n", "1\0" }) do
            rejects(S, bad)
        end
        rejects(S, true); rejects(S, {}); rejects(S, nil); rejects(S, print)
        rejects(S, 0 / 0)
    end)

    test("coerce.number: the error is an invalid_type on the number type", function()
        local err = rejects(z.coerce.number(), "abc")
        assertDeepEq(err.issues, { { path = {}, code = "invalid_type", expected = "number", got = "string" } })
    end)

    test("coerce.number: bounds apply after the conversion", function()
        local S = z.coerce.number():min(10)
        accepts(S, "12", 12)
        local err = rejects(S, "5")
        assertEq(err.issues[1].code, "too_small")
        assertEq(err.issues[1].got, 5)
    end)

    test("coerce.integer: integer strings convert and the ADR 0001 rules apply", function()
        local S = z.coerce.integer()
        accepts(S, "10", 10)
        accepts(S, 7, 7)
        accepts(S, "3.0", 3)
        accepts(S, "1e2", 100)
        local err = rejects(S, "3.5")
        assertDeepEq(err.issues, { { path = {}, code = "invalid_type", expected = "integer", got = "float" } })
        rejects(S, " 3"); rejects(S, "x"); rejects(S, 2.5); rejects(S, true)
    end)

    test("coerce.integer: bounds and the strict option", function()
        local S = z.coerce.integer():between(1, 5)
        accepts(S, "3", 3)
        rejects(S, "9"); rejects(S, "0")
        assertThrows(function() return z.coerce.integer("x") end)
        if math.type then
            rejects(z.coerce.integer({ strict = true }), "3.0")
            accepts(z.coerce.integer({ strict = true }), "3", 3)
        end
    end)

    test("coerce.boolean: only true, false, 1, 0 and their string forms", function()
        local S = z.coerce.boolean()
        accepts(S, true, true)
        accepts(S, false, false)
        accepts(S, "true", true)
        accepts(S, "false", false)
        accepts(S, "1", true)
        accepts(S, "0", false)
        accepts(S, 1, true)
        accepts(S, 0, false)
    end)

    test("coerce.boolean: everything else is refused, including truthy values", function()
        local S = z.coerce.boolean()
        for _, bad in ipairs({ "", "yes", "no", "TRUE", "False", "2", 2, -1, 0.5, " true", "true ", "nil" }) do
            rejects(S, bad)
        end
        rejects(S, {}); rejects(S, nil); rejects(S, print)
        local err = rejects(S, "yes")
        assertEq(err.issues[1].expected, "boolean")
    end)

    test("coerce.string: strings pass, numbers and booleans convert", function()
        local S = z.coerce.string()
        accepts(S, "abc", "abc")
        accepts(S, "", "")
        accepts(S, 12, "12")
        accepts(S, 1.5, "1.5")
        accepts(S, -7, "-7")
        accepts(S, true, "true")
        accepts(S, false, "false")
    end)

    test("coerce.string: other types and non finite numbers are refused", function()
        local S = z.coerce.string()
        rejects(S, {}); rejects(S, nil); rejects(S, print)
        rejects(S, 0 / 0); rejects(S, math.huge); rejects(S, -math.huge)
        local err = rejects(S, {})
        assertEq(err.issues[1].expected, "string")
        assertEq(err.issues[1].got, "table")
    end)

    test("coerce.string: length bounds apply after the conversion", function()
        local S = z.coerce.string():len(2)
        accepts(S, 12, "12")
        rejects(S, 1)
        rejects(S, 123)
    end)

    test("coerce: an absent value is refused unless optional or defaulted", function()
        rejects(z.coerce.number(), nil)
        accepts(z.coerce.number():optional(), nil, nil)
        accepts(z.coerce.number():default(7), nil, 7)
        accepts(z.coerce.boolean():default(false), nil, false)
    end)

    test("coerce: composes with transform and pipe", function()
        local S = z.coerce.number():transform(function(v) return v * 2 end)
        accepts(S, "4", 8)
        local P = z.coerce.string():pipe(z.string():min(3))
        accepts(P, 123, "123")
        rejects(P, 12)
    end)

    test("coerce: works inside objects and arrays", function()
        local S = z.object({
            port = z.coerce.integer():between(1, 65535),
            debug = z.coerce.boolean():default(false),
            tags = z.array(z.coerce.string()),
        })
        local out = S:parse({ port = "8080", tags = { 1, "b", true } })
        assertDeepEq(out, { port = 8080, debug = false, tags = { "1", "b", "true" } })
        local _, _, err = S:safeParse({ port = "x", debug = "maybe", tags = { {} } })
        assertEq(err:format(), table.concat({
            "debug: Expected boolean, got string",
            "port: Expected integer, got string",
            "tags[1]: Expected string, got table",
        }, "\n"))
    end)

    test("coerce: nodes are immutable and leave plain schemas untouched", function()
        local plain = z.number()
        local coerced = z.coerce.number()
        assertTrue(plain.pure)
        assertFalse(plain:is("1"))
        assertTrue(coerced:safeParse("1"))
        assertEq(plain.d.coerce, nil)
        local derived = coerced:max(3)
        assertTrue(derived ~= coerced)
        assertTrue(coerced:safeParse("100"))
        assertFalse(derived:is("100"))
    end)

    test("strip: unknown keys are removed from a copy", function()
        local S = z.object({ a = z.string(), b = z.number() }):strip()
        local input = { a = "x", b = 1, extra = true, [1] = "n" }
        local out = S:parse(input)
        assertDeepEq(out, { a = "x", b = 1 })
        assertTrue(out ~= input)
        assertEq(input.extra, true)
    end)

    test("strip: validation still applies", function()
        local S = z.object({ a = z.string() }):strip()
        assertTrue(S:is({ a = "x", extra = 1 }))
        local _, _, err = S:safeParse({ a = 1, extra = 1 })
        assertDeepEq(err.issues, { { path = { "a" }, code = "invalid_type", expected = "string", got = "number" } })
    end)

    test("strip: optional fields that are absent stay absent", function()
        local S = z.object({ a = z.string(), b = z.number():optional() }):strip()
        local out = S:parse({ a = "x", other = 1 })
        assertDeepEq(out, { a = "x" })
        assertEq(next(out, "a"), nil)
    end)

    test("strip and strict: the last call wins", function()
        local O = z.object({ a = z.string() })
        local stripped = O:strict():strip()
        assertDeepEq(stripped:parse({ a = "x", z = 1 }), { a = "x" })
        local strict = O:strip():strict()
        assertFalse(strict:is({ a = "x", z = 1 }))
        assertTrue(strict:is({ a = "x" }))
        assertDeepEq(O:strict():strip():strict():strip():parse({ a = "x", z = 1 }), { a = "x" })
    end)

    test("strip: a derived strip leaves the source untouched", function()
        local O = z.object({ a = z.string() })
        local S = O:strip()
        assertTrue(S ~= O)
        assertTrue(O.pure)
        local input = { a = "x", z = 1 }
        assertTrue(rawequal(O:parse(input), input))
        assertFalse(rawequal(S:parse(input), input))
    end)

    test("strip: applies to its own level only", function()
        local S = z.object({ inner = z.object({ a = z.string() }), b = z.number() }):strip()
        local out = S:parse({ inner = { a = "x", z = 1 }, b = 1, extra = 1 })
        assertDeepEq(out, { inner = { a = "x", z = 1 }, b = 1 })
        local T = z.object({ inner = z.object({ a = z.string() }):strip() })
        assertDeepEq(T:parse({ inner = { a = "x", z = 1 }, extra = 1 }), { inner = { a = "x" }, extra = 1 })
    end)

    test("strip: composes with default inside arrays", function()
        local Item = z.object({ id = z.integer(), tag = z.string():default("none") }):strip()
        local out = z.array(Item):parse({ { id = 1, junk = true }, { id = 2, tag = "t" } })
        assertDeepEq(out, { { id = 1, tag = "none" }, { id = 2, tag = "t" } })
    end)

    test("strip: hostile and exotic keys are dropped without error", function()
        local S = z.object({ a = z.string() }):strip()
        local input = { a = "x", ["]] os.exit() --"] = 1, ["\0"] = 2, [print] = 3, [true] = 4 }
        assertDeepEq(S:parse(input), { a = "x" })
    end)
end
