return function(env)
    local test, z = env.test, env.z
    local assertTrue, assertFalse, assertEq = env.assertTrue, env.assertFalse, env.assertEq
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local ffi
    if jit then
        local ok, lib = pcall(require, "ffi")
        if ok and type(lib) == "table" and lib.istype then ffi = lib end
    end
    local loader = loadstring or load

    local function withCodegen(flag, fn)
        local previous = z.config().codegen
        z.config({ codegen = flag })
        local ok, err = pcall(fn)
        z.config({ codegen = previous })
        if not ok then error(err, 0) end
    end

    local function compiled(flag, build)
        local fn
        withCodegen(flag, function() fn = build()._test end)
        return fn
    end

    local function sameVerdict(build, values)
        local generated = compiled(true, build)
        local reference = compiled(false, build)
        assertTrue(z._isGenerated(generated))
        assertFalse(z._isGenerated(reference))
        for i = 1, values.n do
            assertEq(generated(values[i]), reference(values[i]))
        end
    end

    local function firstIssue(schema, input)
        local ok, value, err = schema:safeParse(input)
        assertFalse(ok)
        assertEq(value, nil)
        return err.issues[1]
    end

    local function native64(src)
        return assert(loader("return " .. src))()
    end

    test("cdata: construction is accepted on every runtime and rejects arguments that are not a C type", function()
        local S = z.cdata("struct never_defined *")
        assertTrue(z.isNode(S))
        assertEq(S.kind, "cdata")
        assertTrue(z.isNode(z.notNullPtr("struct never_defined *")))
        assertThrows(function() z.cdata() end)
        assertThrows(function() z.cdata("") end)
        assertThrows(function() z.cdata(5) end)
        assertThrows(function() z.cdata({}) end)
        assertThrows(function() z.notNullPtr(5) end)
        assertThrows(function() z.notNullPtr("") end)
        assertThrows(function() z.notNullPtr({}) end)
    end)

    test("notNullPtr: calling it without a C type raises a construction error on every runtime", function()
        local ok, err = pcall(function() return z.notNullPtr() end)
        assertFalse(ok)
        assertTrue(tostring(err):find("notNullPtr() expects a C pointer type", 1, true) ~= nil)
    end)

    test("cdata: the C type is not resolved at construction", function()
        local S = z.cdata("struct also_never_defined *")
        local N = z.notNullPtr("struct also_never_defined *")
        assertTrue(z.isNode(S)); assertTrue(z.isNode(N))
    end)

    test("literal: no cdata ever equals a literal, whatever the runtime", function()
        local values = { z.literal(1), z.literal(0), z.literal(true), z.literal("1") }
        for _, S in ipairs(values) do
            assertFalse(S:is(nil)); assertFalse(S:is({}))
        end
        assertTrue(z.literal(1):is(1)); assertTrue(z.literal(1):is(1.0))
        assertFalse(z.literal(1):is("1")); assertFalse(z.literal("1"):is(1))
        assertTrue(z.literal(true):is(true)); assertFalse(z.literal(true):is(1))
    end)

    if not ffi then
        test("cdata: outside LuaJIT every value is refused with invalid_type", function()
            local S = z.cdata("int64_t")
            local inputs = { nil, 0, 1, "1", true, {}, print, io.stdout }
            for i = 1, 8 do
                assertFalse(S:is(inputs[i]))
            end
            assertDeepEq(firstIssue(S, 1), { path = {}, code = "invalid_type", expected = "int64_t", got = "number" })
            assertFalse(z.notNullPtr("void *"):is(io.stdout))
            assertFalse(z.notNullPtr("void *"):is(1))
            assertEq(firstIssue(z.notNullPtr("void *"), 1).code, "invalid_type")
        end)

        test("cdata: outside LuaJIT an optional or nullable cdata still accepts nil or the sentinel", function()
            local sentinel = {}
            assertTrue(z.cdata("int *"):optional():is(nil))
            assertTrue(z.cdata("int *"):nullable(sentinel):is(sentinel))
            assertFalse(z.cdata("int *"):nullable(sentinel):is(nil))
            local S = z.object({ p = z.cdata("int *"):optional() })
            assertTrue(S:is({})); assertFalse(S:is({ p = 1 }))
        end)

        test("cdata: outside LuaJIT codegen and closures agree", function()
            local values = { n = 4, nil, 1, "x", {} }
            sameVerdict(function() return z.cdata("int *") end, values)
            sameVerdict(function() return z.cdata("int *"):optional() end, values)
            sameVerdict(function() return z.notNullPtr("void *") end, values)
            sameVerdict(function() return z.array(z.cdata("int *")) end, values)
        end)

        test("literal: a number literal keeps the plain comparison outside LuaJIT", function()
            assertTrue(z.literal(1):is(1))
            assertFalse(z.literal(1):is(2))
        end)
        return
    end

    ffi.cdef([[
        typedef struct zigo_cd_point { int x; int y; } zigo_cd_point;
        typedef struct zigo_cd_other { int a; } zigo_cd_other;
        typedef struct zigo_cd_eq { int a; } zigo_cd_eq;
    ]])
    ffi.metatype("zigo_cd_eq", { __eq = function() return true end })

    local function ptr(ctype) return ffi.new(ctype .. "[1]") end

    test("cdata: accepts values of the C type given as a string and refuses the rest", function()
        local S = z.cdata("int64_t")
        assertTrue(S:is(ffi.new("int64_t", 5))); assertTrue(S:is(native64("5LL")))
        assertFalse(S:is(5)); assertFalse(S:is(native64("5ULL"))); assertFalse(S:is(ffi.new("int32_t", 5)))
        assertFalse(S:is(nil)); assertFalse(S:is("5")); assertFalse(S:is({})); assertFalse(S:is(ffi.new("double", 5)))
        assertTrue(z.cdata("uint64_t"):is(native64("5ULL")))
        assertTrue(z.cdata("double"):is(ffi.new("double", 1.5)))
        assertFalse(z.cdata("double"):is(1.5))
    end)

    test("cdata: follows ffi.istype for structs, pointers and arrays", function()
        local point = ffi.new("zigo_cd_point")
        local pointPtr = ffi.new("zigo_cd_point[1]")
        local other = ffi.new("zigo_cd_other")
        assertTrue(z.cdata("zigo_cd_point"):is(point))
        assertTrue(z.cdata("struct zigo_cd_point"):is(point))
        assertFalse(z.cdata("zigo_cd_point"):is(other))
        assertTrue(z.cdata("zigo_cd_point *"):is(ffi.cast("zigo_cd_point *", pointPtr)))
        assertTrue(z.cdata("zigo_cd_point"):is(ffi.cast("zigo_cd_point *", pointPtr)))
        assertFalse(z.cdata("zigo_cd_point *"):is(point))
        assertFalse(z.cdata("zigo_cd_other *"):is(ffi.cast("zigo_cd_point *", pointPtr)))
        assertTrue(z.cdata("zigo_cd_point[1]"):is(pointPtr))
        assertTrue(z.cdata("void *"):is(ffi.cast("void *", 0)))
        assertFalse(z.cdata("void *"):is(ffi.cast("int *", 0)))
    end)

    test("cdata: accepts a ctype object instead of a string", function()
        local S = z.cdata(ffi.typeof("zigo_cd_point"))
        assertTrue(S:is(ffi.new("zigo_cd_point"))); assertFalse(S:is(ffi.new("zigo_cd_other")))
        local issue = firstIssue(S, 1)
        assertEq(issue.expected, tostring(ffi.typeof("zigo_cd_point")))
    end)

    test("cdata: the C type is resolved at the first call and cached", function()
        local S = z.cdata("zigo_cd_late_t")
        ffi.cdef("typedef struct zigo_cd_late_t { int a; } zigo_cd_late_t;")
        assertTrue(S:is(ffi.new("zigo_cd_late_t")))
        assertFalse(S:is(ffi.new("zigo_cd_point")))
        assertTrue(S:is(ffi.new("zigo_cd_late_t")))
    end)

    test("cdata: a C type that does not resolve raises at the first call", function()
        local S = z.cdata("zigo_cd_missing_t *")
        local ok, err = pcall(function() return S:is(1) end)
        assertFalse(ok)
        assertTrue(tostring(err):find("zigo_cd_missing_t", 1, true) ~= nil)
        ffi.cdef("typedef struct zigo_cd_missing_t { int a; } zigo_cd_missing_t;")
        assertTrue(S:is(ffi.new("zigo_cd_missing_t *")))
        assertFalse(S:is(1))
    end)

    test("cdata: the issue names the C type and the received type", function()
        local S = z.cdata("zigo_cd_point *")
        assertDeepEq(firstIssue(S, 1), { path = {}, code = "invalid_type", expected = "zigo_cd_point *", got = "number" })
        assertEq(firstIssue(S, ffi.new("int32_t", 1)).got, "cdata")
        assertEq(firstIssue(S, nil).got, "nil")
        local _, _, err = S:safeParse("x")
        assertEq(err:format(), "<root>: Expected zigo_cd_point *, got string")
    end)

    test("cdata: a struct whose __eq answers true for anything does not fool literal, null or nullable", function()
        local eq = ffi.new("zigo_cd_eq")
        assertTrue(eq == nil)
        assertTrue(z.cdata("zigo_cd_eq"):is(eq))
        assertFalse(z.cdata("zigo_cd_point"):is(eq))
        assertFalse(z.literal(1):is(eq)); assertFalse(z.literal("x"):is(eq)); assertFalse(z.literal(true):is(eq))
        assertFalse(z.literal(1):is(native64("1LL")))
        assertFalse(z.null({}):is(eq))
        local sentinel = {}
        assertFalse(z.string():nullable(sentinel):is(eq))
    end)

    test("literal: 1LL is not the literal 1, in closures and in codegen", function()
        local values = {
            n = 9, native64("1LL"), native64("1ULL"), native64("0LL"), ffi.new("int32_t", 1),
            ffi.new("double", 1), 1, 1.0, 0, "1",
        }
        for _, build in ipairs({
            function() return z.literal(1) end,
            function() return z.literal(0) end,
            function() return z.literal("1") end,
            function() return z.literal(true) end,
            function() return z.literal(1):optional() end,
            function() return z.object({ a = z.literal(1) }) end,
        }) do
            sameVerdict(build, values)
        end
        assertFalse(z.literal(1):is(native64("1LL")))
        assertFalse(z.literal(1):is(native64("1ULL")))
        assertFalse(z.literal(0):is(native64("0LL")))
        assertFalse(z.literal(1):is(ffi.new("double", 1)))
        assertTrue(z.literal(1):is(1)); assertTrue(z.literal(1):is(1.0))
        assertFalse(z.object({ a = z.literal(1) }):is({ a = native64("1LL") }))
        assertTrue(z.object({ a = z.literal(1) }):is({ a = 1 }))
        local issue = firstIssue(z.literal(1), native64("1LL"))
        assertEq(issue.code, "invalid_literal")
        assertEq(issue.got, "cdata")
    end)

    test("literal: enum and discriminatedUnion do not take a cdata for their number", function()
        assertFalse(z.enum({ 1, 2 }):is(native64("1LL")))
        local a = z.object({ k = z.literal(1) })
        local b = z.object({ k = z.literal(2) })
        local U = z.discriminatedUnion("k", a, b)
        assertTrue(U:is({ k = 1 }))
        assertFalse(U:is({ k = native64("1LL") }))
    end)

    test("notNullPtr: refuses a NULL pointer and accepts a non-NULL one", function()
        local arr = ffi.new("int[4]")
        for _, ct in ipairs({ "int *", "void *", "zigo_cd_point *", "const char *", "int **", "void (*)(int)" }) do
            local S = z.notNullPtr(ct)
            assertTrue(S:is(ffi.cast(ct, arr)))
            assertFalse(S:is(ffi.cast(ct, 0)))
        end
        assertFalse(z.notNullPtr("int *"):is(ffi.new("int *")))
    end)

    test("notNullPtr: refuses what is not a pointer", function()
        local S = z.notNullPtr("void *")
        assertFalse(S:is(nil)); assertFalse(S:is(0)); assertFalse(S:is("x")); assertFalse(S:is({}))
        assertFalse(S:is(native64("1LL"))); assertFalse(S:is(native64("1ULL")))
        assertFalse(S:is(ffi.new("double", 1))); assertFalse(S:is(ffi.new("zigo_cd_point")))
        assertFalse(S:is(ffi.new("zigo_cd_eq")))
        assertFalse(S:is(ffi.new("int[4]")))
    end)

    test("notNullPtr: with a C type it also needs the pointer to match that type", function()
        local S = z.notNullPtr("zigo_cd_point *")
        local pts = ffi.new("zigo_cd_point[2]")
        assertTrue(S:is(ffi.cast("zigo_cd_point *", pts)))
        assertFalse(S:is(ffi.cast("zigo_cd_point *", 0)))
        assertFalse(S:is(ffi.cast("zigo_cd_other *", pts)))
        assertFalse(S:is(ffi.cast("void *", pts)))
        assertFalse(S:is(ffi.new("zigo_cd_point")))
        assertFalse(S:is(nil)); assertFalse(S:is(1))
    end)

    test("notNullPtr: a C type that is not a pointer type raises at the first call", function()
        local S = z.notNullPtr("zigo_cd_point")
        local ok, err = pcall(function() return S:is(ffi.new("zigo_cd_point")) end)
        assertFalse(ok)
        assertTrue(tostring(err):find("pointer type", 1, true) ~= nil)
        assertFalse(pcall(function() return S:is(1) end))
    end)

    test("notNullPtr: optional accepts nil but still refuses a NULL pointer", function()
        local null = ffi.cast("zigo_cd_point *", 0)
        local good = ffi.cast("zigo_cd_point *", ffi.new("zigo_cd_point[1]"))
        for _, S in ipairs({ z.notNullPtr("zigo_cd_point *"):optional() }) do
            assertTrue(S:is(nil)); assertTrue(S:is(good))
            assertFalse(S:is(null)); assertFalse(S:is(1))
        end
        local O = z.object({ p = z.notNullPtr("zigo_cd_point *"):optional() })
        assertTrue(O:is({})); assertTrue(O:is({ p = good })); assertFalse(O:is({ p = null }))
        local N = z.object({ p = z.notNullPtr("zigo_cd_point *"):optional():nullable({}) })
        assertTrue(N:is({})); assertFalse(N:is({ p = null }))
        assertTrue(z.cdata("zigo_cd_point *"):optional():is(null))
        assertTrue(z.cdata("zigo_cd_point *"):optional():is(nil))
        assertFalse(z.cdata("zigo_cd_point *"):optional():is(1))
    end)

    test("notNullPtr: the issue says NULL for a NULL pointer", function()
        local S = z.notNullPtr("void *")
        assertDeepEq(firstIssue(S, ffi.cast("void *", 0)),
            { path = {}, code = "invalid_type", expected = "non-null void *", got = "NULL" })
        assertDeepEq(firstIssue(S, 1),
            { path = {}, code = "invalid_type", expected = "non-null void *", got = "number" })
        assertEq(firstIssue(S, native64("1LL")).got, "cdata")
        local T = z.notNullPtr("zigo_cd_point *")
        assertEq(firstIssue(T, ffi.cast("zigo_cd_point *", 0)).expected, "non-null zigo_cd_point *")
        assertEq(firstIssue(T, ffi.cast("zigo_cd_point *", 0)).got, "NULL")
    end)

    test("cdata and notNullPtr: work in objects, arrays, optional and nullable fields", function()
        local sentinel = {}
        local S = z.object({
            handle = z.notNullPtr("zigo_cd_point *"),
            id = z.cdata("int64_t"),
            next = z.cdata("zigo_cd_point *"):optional(),
            prev = z.cdata("zigo_cd_point *"):nullable(sentinel),
        })
        local pts = ffi.new("zigo_cd_point[2]")
        local good = ffi.cast("zigo_cd_point *", pts)
        assertTrue(S:is({ handle = good, id = native64("1LL"), prev = sentinel }))
        assertTrue(S:is({ handle = good, id = native64("1LL"), prev = good, next = good }))
        assertFalse(S:is({ handle = ffi.cast("zigo_cd_point *", 0), id = native64("1LL"), prev = sentinel }))
        assertFalse(S:is({ handle = good, id = 1, prev = sentinel }))
        assertFalse(S:is({ handle = good, id = native64("1LL") }))
        local A = z.array(z.notNullPtr("zigo_cd_point *"))
        assertTrue(A:is({ good, good })); assertFalse(A:is({ good, ffi.cast("zigo_cd_point *", 0) }))
    end)

    test("cdata and notNullPtr: codegen and closures agree", function()
        local arr = ffi.new("zigo_cd_point[2]")
        local values = {
            n = 14, nil, 1, "x", {}, native64("1LL"), native64("1ULL"), ffi.new("zigo_cd_point"),
            ffi.cast("zigo_cd_point *", arr), ffi.cast("zigo_cd_point *", 0), ffi.cast("void *", 0),
            ffi.cast("void *", arr), ffi.cast("int *", arr), ffi.new("double", 1), ffi.new("zigo_cd_eq"),
        }
        for _, build in ipairs({
            function() return z.cdata("int64_t") end,
            function() return z.cdata("zigo_cd_point *") end,
            function() return z.cdata("zigo_cd_point") end,
            function() return z.cdata("zigo_cd_point *"):optional() end,
            function() return z.notNullPtr("void *") end,
            function() return z.notNullPtr("zigo_cd_point *") end,
            function() return z.notNullPtr("zigo_cd_point *"):optional() end,
            function() return z.array(z.notNullPtr("zigo_cd_point *")) end,
            function() return z.union(z.cdata("int64_t"), z.notNullPtr("void *")) end,
            function() return z.object({ p = z.cdata("zigo_cd_point *"):optional() }) end,
        }) do
            sameVerdict(build, values)
        end
    end)

    test("cdata and notNullPtr: do not allocate for a valid value", function()
        local pts = ffi.new("zigo_cd_point[2]")
        local good = ffi.cast("zigo_cd_point *", pts)
        local S = z.object({ a = z.cdata("zigo_cd_point *"), b = z.notNullPtr("zigo_cd_point *") })
        local v = { a = good, b = good }
        local t = S._test
        assertTrue(t(v))
        local best = math.huge
        for _ = 1, 5 do
            for _ = 1, 5000 do t(v) end
            collectgarbage("collect")
            collectgarbage("stop")
            local before = collectgarbage("count")
            for _ = 1, 20000 do t(v) end
            local after = collectgarbage("count")
            collectgarbage("restart")
            local per = (after - before) * 1024 / 20000
            if per < best then best = per end
            if best < 0.5 then break end
        end
        assertTrue(best < 0.5)
    end)

    test("cdata: a boolean cdata is not a Lua boolean, generated or not", function()
        local values = { n = 6, ffi.new("bool", true), ffi.new("bool", false), true, false, 1, "true" }
        sameVerdict(function() return z.boolean() end, values)
        sameVerdict(function() return z.object({ a = z.boolean(), b = z.boolean():optional() }) end, {
            n = 3,
            { a = ffi.new("bool", true) }, { a = true, b = ffi.new("bool", false) }, { a = false, b = true },
        })
        for _, flag in ipairs({ true, false }) do
            withCodegen(flag, function()
                local S = z.boolean()
                assertFalse(S:is(ffi.new("bool", true)))
                assertFalse(S:is(ffi.new("bool", false)))
                assertTrue(S:is(true)); assertTrue(S:is(false))
            end)
        end
    end)
end
