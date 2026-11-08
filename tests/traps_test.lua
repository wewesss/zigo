return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local nan = 0 / 0
    local inf = math.huge

    test("trap NaN: number() rejects NaN (decision: NaN is never a valid number)", function()
        assertFalse(z.number():is(nan))
        assertFalse(z.number():min(0):is(nan))
        assertFalse(z.number():optional():is(nan))
        local _, _, err = z.number():safeParse(nan)
        assertDeepEq(err.issues, { { path = {}, code = "invalid_type", expected = "number", got = "nan" } })
    end)

    test("trap NaN: integer() rejects NaN", function()
        assertFalse(z.integer():is(nan))
        assertFalse(z.integer({ strict = true }):is(nan))
    end)

    test("trap NaN: enum and literal never match NaN", function()
        assertFalse(z.enum({ 1, 2 }):is(nan))
        assertFalse(z.literal(1):is(nan))
        local _, _, err = z.literal(1):safeParse(nan)
        assertEq(err.issues[1].got, "nan")
    end)

    test("trap NaN: NaN as a field value is rejected inside objects and arrays", function()
        assertFalse(z.object({ x = z.number() }):is({ x = nan }))
        assertFalse(z.array(z.number()):is({ nan }))
    end)

    test("trap inf: number() accepts +-inf (decision), min/max can bound them", function()
        assertTrue(z.number():is(inf)); assertTrue(z.number():is(-inf))
        assertFalse(z.number():max(10):is(inf))
        assertFalse(z.number():min(-10):is(-inf))
        assertTrue(z.number():between(-inf, inf):is(5))
    end)

    test("trap inf: integer() rejects +-inf, even in strict mode", function()
        assertFalse(z.integer():is(inf)); assertFalse(z.integer():is(-inf))
        assertFalse(z.integer({ strict = true }):is(inf))
        local _, _, err = z.integer():safeParse(inf)
        assertEq(err.issues[1].got, "inf")
        local _, _, err2 = z.integer():safeParse(-inf)
        assertEq(err2.issues[1].got, "-inf")
    end)

    test("trap -0: number() and integer() accept -0 and it satisfies min(0)", function()
        local negZero = -0.0
        assertTrue(z.number():is(negZero)); assertTrue(z.integer():is(negZero))
        assertTrue(z.number():min(0):is(negZero)); assertTrue(z.integer():between(0, 1):is(negZero))
    end)

    test("trap 3.0: integer() accepts integral floats on every runtime", function()
        assertTrue(z.integer():is(3.0)); assertTrue(z.integer():is(-3.0)); assertTrue(z.integer():is(1e15))
        assertFalse(z.integer():is(3.5))
    end)

    test("trap 3.0: strict integer verdict follows math.type on 5.3+", function()
        local strict = z.integer({ strict = true })
        assertTrue(strict:is(3))
        if math.type then
            assertFalse(strict:is(3.0))
            local _, _, err = strict:safeParse(3.0)
            assertDeepEq(err.issues, { { path = {}, code = "invalid_type", expected = "integer", got = "float" } })
        end
    end)

    test("trap 2^53: integer() accepts 2^53 (larger values are int64's job, P4)", function()
        assertTrue(z.integer():is(2 ^ 53))
        assertTrue(z.integer():is(9007199254740992))
    end)

    test("trap no coercion: numeric strings are not numbers or integers", function()
        assertFalse(z.integer():is("12")); assertFalse(z.number():is("1.5")); assertFalse(z.boolean():is("true"))
        assertFalse(z.string():is(12))
    end)

    test("trap cdata: LuaJIT cdata numbers are not Lua numbers", function()
        local okFfi, ffi = pcall(require, "ffi")
        if not okFfi then return end
        local big = ffi.new("int64_t", 1)
        assertFalse(z.number():is(big))
        assertFalse(z.integer():is(big))
        assertFalse(z.string():is(big))
    end)

    test("trap holes: arrays with holes are rejected whatever #t says", function()
        local A = z.array(z.any())
        assertFalse(A:is({ 1, nil, 3 }))
        assertFalse(A:is({ nil, 2 }))
        assertFalse(A:is({ [1] = 1, [3] = 3 }))
        assertFalse(A:is({ [2] = 1 }))
        assertFalse(A:is({ 1, 2, nil, 4 }))
    end)

    test("trap holes: arrays with extra non-sequence keys are rejected", function()
        local A = z.array(z.any())
        assertFalse(A:is({ 1, 2, a = 3 }))
        assertFalse(A:is({ [0] = 1 }))
        assertFalse(A:is({ [1.5] = 1 }))
        assertFalse(A:is({ a = 1 }))
        assertFalse(A:is({ 1, [-1] = 1 }))
    end)

    test("trap holes: a hole at any size from 3 to 100 is rejected", function()
        local A = z.array(z.any())
        for n = 1, 100 do
            local t = {}
            for i = 1, n do t[i] = i end
            assertTrue(A:is(t))
            t[n + 2] = 1
            assertFalse(A:is(t))
            t[n + 2] = nil
            if n > 2 then
                t[math.floor(n / 2)] = nil
                assertFalse(A:is(t))
            end
        end
    end)

    test("trap {}: both array() and object() accept the empty table", function()
        assertTrue(z.array(z.number()):is({}))
        assertTrue(z.object({}):is({}))
        assertTrue(z.object({}):strict():is({}))
        assertTrue(z.object({ a = z.number():optional() }):is({}))
        assertFalse(z.array(z.number()):min(1):is({}))
    end)

    test("trap {}: an array table passes an empty passthrough object but not a strict one", function()
        assertTrue(z.object({}):is({ 1, 2 }))
        assertFalse(z.object({}):strict():is({ 1, 2 }))
    end)

    test("trap metatable: object ignores __index by default", function()
        local proxy = setmetatable({}, { __index = function() return "bob" end })
        assertFalse(z.object({ name = z.string() }):is(proxy))
    end)

    test("trap metatable: object { meta = true } uses normal access", function()
        local proxy = setmetatable({}, { __index = function() return "bob" end })
        assertTrue(z.object({ name = z.string() }, { meta = true }):is(proxy))
    end)

    test("trap metatable: array reads raw contents, not __index", function()
        local proxy = setmetatable({}, { __index = function(_, i) if i <= 3 then return i end end })
        assertTrue(z.array(z.integer()):is(proxy))
        assertFalse(z.array(z.integer()):min(1):is(proxy))
    end)

    test("trap metatable: array { meta = true } uses __index and __len where honoured", function()
        local proxy = setmetatable({}, {
            __index = function(_, i) if i >= 1 and i <= 3 then return i end end,
            __len = function() return 3 end,
        })
        if #proxy == 3 then
            assertTrue(z.array(z.integer(), { meta = true }):len(3):is(proxy))
            assertFalse(z.array(z.string(), { meta = true }):is(proxy))
        end
    end)

    test("trap metatable: raw access survives hostile __index and __newindex", function()
        local calls = 0
        local hostile = setmetatable({ name = "bob" }, {
            __index = function() calls = calls + 1; error("boom") end,
            __newindex = function() error("boom") end,
        })
        assertTrue(z.object({ name = z.string() }):is(hostile))
        assertEq(calls, 0)
        local ok = z.object({ name = z.string(), other = z.string():optional() }):safeParse(hostile)
        assertTrue(ok)
        assertEq(calls, 0)
    end)

    test("trap cycles: a cyclic value terminates against a finite schema", function()
        local a = {}
        a.self = a
        local S = z.object({ self = z.object({ self = z.object({}) }) })
        assertTrue(S:is(a))
        local T = z.object({ self = z.object({ self = z.number() }) })
        local ok, _, err = T:safeParse(a)
        assertFalse(ok)
        assertEq(#err.issues, 1)
        assertDeepEq(err.issues[1].path, { "self", "self" })
        local list = {}
        list[1] = list
        assertFalse(z.array(z.number()):is(list))
        assertTrue(z.array(z.array(z.any())):is(list))
    end)

    test("trap bytes: string length counts bytes, not characters", function()
        assertTrue(z.string():len(2):is("\195\169"))
        assertFalse(z.string():len(1):is("\195\169"))
    end)

    test("trap hostile keys: odd key names are plain data", function()
        local keys = { "]] os.exit() --", "\0", "a\nb", "'\"", string.rep("k", 100000) }
        local shape, value = {}, {}
        for i = 1, #keys do
            shape[keys[i]] = z.number()
            value[keys[i]] = i
        end
        local S = z.object(shape):strict()
        assertTrue(S:is(value))
        value[keys[2]] = "x"
        local ok, _, err = S:safeParse(value)
        assertFalse(ok)
        assertEq(err.issues[1].path[1], "\0")
        assertTrue(z.string():is(string.rep("x", 1000000)))
    end)

    test("trap nil key access: validating a missing optional never indexes nil", function()
        assertTrue(z.object({ a = z.object({ b = z.number() }):optional() }):is({}))
    end)
end
