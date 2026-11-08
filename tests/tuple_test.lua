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

    test("tuple: a fixed-length array of typed positions", function()
        local T = z.tuple({ z.string(), z.integer(), z.boolean() })
        assertTrue(T.pure)
        assertTrue(T:is({ "a", 1, true }))
        assertFalse(T:is({ 1, "a", true }))
        assertFalse(T:is({ "a", 1, "x" }))
        assertFalse(T:is({ "a", 1 }))
        assertFalse(T:is({}))
        assertFalse(T:is("a")); assertFalse(T:is(nil)); assertFalse(T:is(1))
        local ok, value = T:safeParse({ "a", 1, true })
        assertTrue(ok); assertDeepEq(value, { "a", 1, true })
    end)

    test("tuple: extra elements are refused", function()
        local T = z.tuple({ z.string(), z.integer() })
        assertFalse(T:is({ "a", 1, 2 }))
        local _, _, err = T:safeParse({ "a", 1, 2, 3 })
        assertDeepEq(err.issues, { { path = {}, code = "too_big", expected = 2, got = 4, type = "array" } })
        assertEq(err:format(), "<root>: Expected length of at most 2, got 4")
    end)

    test("tuple: rest() accepts a typed tail", function()
        local T = z.tuple({ z.string() }):rest(z.integer())
        assertTrue(T.pure)
        assertTrue(T:is({ "a" }))
        assertTrue(T:is({ "a", 1, 2, 3 }))
        assertFalse(T:is({ "a", 1, "x" }))
        assertFalse(T:is({ 1 }))
        local _, _, err = T:safeParse({ "a", 1, "x", true })
        assertDeepEq(err.issues, {
            { path = { 3 }, code = "invalid_type", expected = "integer", got = "string" },
            { path = { 4 }, code = "invalid_type", expected = "integer", got = "boolean" },
        })
    end)

    test("tuple: rest() is immutable and the last call wins", function()
        local base = z.tuple({ z.string() })
        local withRest = base:rest(z.integer())
        assertFalse(base:is({ "a", 1 }))
        assertTrue(withRest:is({ "a", 1 }))
        assertFalse(withRest:rest(z.string()):is({ "a", 1 }))
        assertTrue(withRest:rest(z.string()):is({ "a", "b" }))
        assertThrows(function() base:rest(1) end)
        assertThrows(function() base:rest() end)
        assertThrows(function() base:transform(upper):rest(z.integer()) end)
    end)

    test("tuple: a missing element is reported at its position", function()
        local T = z.tuple({ z.string(), z.integer() })
        local _, _, err = T:safeParse({ "a" })
        assertDeepEq(err.issues, { { path = { 2 }, code = "invalid_type", expected = "integer", got = "nil" } })
    end)

    test("tuple: trailing optional elements may be missing", function()
        local T = z.tuple({ z.string(), z.integer():optional() })
        assertTrue(T:is({ "a" }))
        assertTrue(T:is({ "a", 1 }))
        assertFalse(T:is({ "a", "x" }))
        assertFalse(T:is({}))
    end)

    test("tuple: holes and stray keys are refused", function()
        local T = z.tuple({ z.any(), z.any(), z.any() })
        assertTrue(T:is({ 1, 2, 3 }))
        assertFalse(T:is({ 1, nil, 3 }))
        assertFalse(T:is({ 1, 2, 3, x = 1 }))
        assertFalse(T:is({ 1, 2, [5] = 5 }))
        local _, _, err = T:safeParse({ 1, 2, 3, x = 1 })
        assertDeepEq(err.issues, { { path = {}, code = "invalid_array", expected = "sequence", got = "table" } })
        local R = z.tuple({ z.any() }):rest(z.any())
        assertFalse(R:is({ 1, nil, 3 }))
        assertFalse(R:is({ 1, x = 1 }))
    end)

    test("tuple: an empty tuple only accepts the empty table", function()
        local T = z.tuple({})
        assertTrue(T:is({}))
        assertFalse(T:is({ 1 }))
        assertTrue(z.tuple({}):rest(z.integer()):is({ 1, 2 }))
    end)

    test("tuple: errors inside nested positions carry the full path", function()
        local S = z.object({ p = z.tuple({ z.string(), z.object({ a = z.integer() }) }) })
        local _, _, err = S:safeParse({ p = { "a", { a = "x" } } })
        assertDeepEq(err.issues, { { path = { "p", 2, "a" }, code = "invalid_type", expected = "integer", got = "string" } })
        local _, _, err2 = z.tuple({ z.string() }):safeParse("x")
        assertDeepEq(err2.issues, { { path = {}, code = "invalid_type", expected = "tuple", got = "string" } })
    end)

    test("tuple: raw access versus { meta = true }", function()
        local backing = { "a", 2 }
        local proxy = setmetatable({}, { __index = backing, __len = function() return #backing end })
        assertFalse(z.tuple({ z.string(), z.integer() }):is(proxy))
        assertTrue(z.tuple({ z.string(), z.integer() }, { meta = true }):is(proxy))
        assertFalse(z.tuple({ z.string(), z.integer() }, { meta = true }):is(setmetatable({}, { __index = { "a" }, __len = function() return 2 end })))
        assertTrue(z.tuple({ z.string() }, { meta = true }):rest(z.integer()):is(setmetatable({ "a" }, { __index = {} })))
    end)

    test("tuple: codegen unrolls the positions and matches closures", function()
        local values = {
            {}, { "a" }, { "a", 1 }, { "a", 1, true }, { "a", 1, true, false }, { 1, "a" }, { "a", "b" },
            { "a", 1, 2 }, { "a", 1, nil, 3 }, { "a", 1, x = 1 }, { nil, 1 }, { [2] = 1 }, "x", 1, true, nil,
            setmetatable({ "a", 1 }, {}), { "a", 1.5 }, { "", 0 }, { {}, {} },
        }
        local function shape() return z.tuple({ z.string(), z.integer() }) end
        sameVerdict(shape, values)
        sameVerdict(function() return shape():rest(z.boolean()) end, values)
        sameVerdict(function() return shape():rest(z.any()) end, values)
        sameVerdict(function() return z.tuple({ z.string(), z.integer():optional() }) end, values)
        sameVerdict(function() return z.tuple({ z.any(), z.any() }) end, values)
        sameVerdict(function() return z.tuple({}) end, values)
        sameVerdict(function() return z.tuple({}):rest(z.string()) end, values)
        sameVerdict(function() return z.tuple({ z.never() }) end, values)
        sameVerdict(function() return shape():optional() end, values)
        sameVerdict(function() return z.tuple({ z.string(), z.integer() }, { meta = true }) end, values)
        sameVerdict(function() return z.tuple({ z.string() }, { meta = true }):rest(z.integer()) end, values)
        sameVerdict(function() return z.array(shape()) end, { { values[3] }, { values[6] }, {}, { values[3], values[4] } })
        sameVerdict(function() return z.object({ t = shape() }) end, { { t = values[3] }, { t = values[6] }, {} })
    end)

    test("tuple: impure items give a new table with their output", function()
        local T = z.tuple({ z.string():transform(upper), z.integer():default(7) })
        assertFalse(T.pure)
        assertDeepEq(T:parse({ "ab", 3 }), { "AB", 3 })
        assertDeepEq(T:parse({ "ab" }), { "AB", 7 })
        assertFalse(T:is({ 1, 3 }))
        assertFalse(T:is({ "ab", 3, 4 }))
        local input = { "ab", 3 }
        assertTrue(T:parse(input) ~= input)
    end)

    test("tuple: an impure rest transforms the tail", function()
        local T = z.tuple({ z.string() }):rest(z.coerce.number())
        assertFalse(T.pure)
        assertDeepEq(T:parse({ "a", "1", 2, "3.5" }), { "a", 1, 2, 3.5 })
        local _, _, err = T:safeParse({ "a", "1", "x" })
        assertDeepEq(err.issues, { { path = { 3 }, code = "invalid_type", expected = "number", got = "string" } })
    end)

    test("tuple: modifiers on the tuple itself", function()
        local T = z.tuple({ z.integer(), z.integer() }):transform(function(v) return v[1] + v[2] end)
        assertFalse(T.pure)
        assertEq(T:parse({ 1, 2 }), 3)
        assertFalse(T:is({ 1, 2, 3 }))
        assertFalse(T:is({ 1, "x" }))
        local D = z.tuple({ z.integer() }):default({ 0 })
        assertDeepEq(D:parse(nil), { 0 })
        assertTrue(z.tuple({ z.integer() }):optional():is(nil))
        local R = z.tuple({ z.integer() }):refine(function(v) return v[1] > 0 end, { message = "positive" })
        assertTrue(R:is({ 1 })); assertFalse(R:is({ 0 }))
    end)

    test("tuple: impure issues are reported in position order", function()
        local T = z.tuple({ z.string():transform(upper), z.integer() }):rest(z.boolean())
        local _, _, err = T:safeParse({ 1, "x", 2 })
        assertDeepEq(err.issues, {
            { path = { 1 }, code = "invalid_type", expected = "string", got = "number" },
            { path = { 2 }, code = "invalid_type", expected = "integer", got = "string" },
            { path = { 3 }, code = "invalid_type", expected = "boolean", got = "number" },
        })
        local _, _, again = T:safeParse({ 1, "x", 2 })
        assertEq(again:format(), err:format())
    end)

    test("tuple: nodes track purity and depth", function()
        assertEq(z.tuple({ z.string(), z.array(z.string()) }).maxDepth, 3)
        assertEq(z.tuple({ z.string() }):rest(z.array(z.array(z.string()))).maxDepth, 4)
        assertTrue(z.tuple({ z.string() }):rest(z.integer()).pure)
        assertFalse(z.tuple({ z.string() }):rest(z.integer():default(1)).pure)
        assertFalse(z.tuple({ z.string():default("x") }).pure)
        assertThrows(function() z.tuple({ z.string() }).d = {} end)
    end)

    test("tuple: construction errors", function()
        assertThrows(function() z.tuple() end)
        assertThrows(function() z.tuple("a") end)
        assertThrows(function() z.tuple({ z.string(), 1 }) end)
        assertThrows(function() z.tuple({ a = z.string() }) end)
        assertThrows(function() z.tuple({ z.string(), a = z.string() }) end)
        assertThrows(function() z.tuple({ [1] = z.string(), [3] = z.string() }) end)
    end)
end
