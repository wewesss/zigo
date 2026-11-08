return function(env)
    local test, z = env.test, env.z
    local assertTrue, assertFalse, assertEq = env.assertTrue, env.assertFalse, env.assertEq
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local nan = 0 / 0

    local ffi
    if jit then
        local ok, lib = pcall(require, "ffi")
        if ok then ffi = lib end
    end

    local function newSentinel(name)
        return setmetatable({}, { __tostring = function() return name end })
    end

    local NULL = newSentinel("NULL")
    local OTHER = newSentinel("OTHER")

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

    test("null: without a sentinel and without z.config, null() and nullable() refuse to build", function()
        assertEq(z.config().null, nil)
        assertThrows(function() z.null() end)
        assertThrows(function() z.string():nullable() end)
        assertThrows(function() z.string():nullable(nil) end)
    end)

    test("null: z.null(s) accepts exactly the sentinel, compared with rawequal", function()
        local S = z.null(NULL)
        assertTrue(S:is(NULL))
        assertFalse(S:is(nil)); assertFalse(S:is(OTHER)); assertFalse(S:is({}))
        assertFalse(S:is(false)); assertFalse(S:is(0)); assertFalse(S:is("")); assertFalse(S:is("NULL"))
        local eq = function() return true end
        local a = setmetatable({}, { __eq = eq })
        local b = setmetatable({}, { __eq = eq })
        assertTrue(a == b)
        assertTrue(z.null(a):is(a))
        assertFalse(z.null(a):is(b))
    end)

    test("null: the sentinel can be any non-nil, non-NaN value", function()
        assertTrue(z.null("NULL"):is("NULL")); assertFalse(z.null("NULL"):is("null"))
        assertTrue(z.null(false):is(false)); assertFalse(z.null(false):is(nil))
        assertTrue(z.null(0):is(0)); assertFalse(z.null(0):is(1))
        assertTrue(z.null(io.stdin):is(io.stdin)); assertFalse(z.null(io.stdin):is(io.stderr))
        assertThrows(function() z.null(nan) end)
        assertThrows(function() z.string():nullable(nan) end)
        assertThrows(function() z.config({ null = nan }) end)
    end)

    test("null: z.null(s) reports an invalid_type issue that names the received type", function()
        local S = z.null(NULL)
        z.null(OTHER)
        assertDeepEq(firstIssue(S, "x"), { path = {}, code = "invalid_type", expected = "null", got = "string" })
        assertDeepEq(firstIssue(S, nil), { path = {}, code = "invalid_type", expected = "null", got = "nil" })
        assertEq(firstIssue(S, OTHER).got, "other null")
        assertEq(z.null(NULL).kind, "null")
    end)

    test("nullable: accepts the sentinel in addition to the base, and refuses nil", function()
        local S = z.string():nullable(NULL)
        assertTrue(S:is("a")); assertTrue(S:is(NULL))
        assertFalse(S:is(nil)); assertFalse(S:is(1)); assertFalse(S:is(OTHER)); assertFalse(S:is({}))
        assertTrue(S.isNullable); assertFalse(S.isOptional)
        assertFalse(z.string().isNullable)
    end)

    test("nullable: is distinct from optional, and both combine", function()
        local opt = z.string():optional()
        local nul = z.string():nullable(NULL)
        local both = z.string():optional():nullable(NULL)
        local bothReversed = z.string():nullable(NULL):optional()
        assertTrue(opt:is(nil)); assertFalse(opt:is(NULL))
        assertFalse(nul:is(nil)); assertTrue(nul:is(NULL))
        for _, S in ipairs({ both, bothReversed }) do
            assertTrue(S:is(nil)); assertTrue(S:is(NULL)); assertTrue(S:is("a"))
            assertFalse(S:is(1)); assertFalse(S:is(OTHER))
            assertTrue(S.isNullable); assertTrue(S.isOptional)
        end
    end)

    test("nullable: works on every schema kind and with the bounds of the base", function()
        local N = z.number():min(2):nullable(NULL)
        assertTrue(N:is(3)); assertTrue(N:is(NULL)); assertFalse(N:is(1))
        local A = z.array(z.integer()):len(2):nullable(NULL)
        assertTrue(A:is({ 1, 2 })); assertTrue(A:is(NULL)); assertFalse(A:is({ 1 })); assertFalse(A:is(OTHER))
        local O = z.object({ a = z.integer() }):strict():nullable(NULL)
        assertTrue(O:is({ a = 1 })); assertTrue(O:is(NULL)); assertFalse(O:is({ a = 1, b = 2 }))
        local T = z.tuple({ z.string(), z.integer() }):nullable(NULL)
        assertTrue(T:is({ "a", 1 })); assertTrue(T:is(NULL)); assertFalse(T:is({ "a" }))
        local R = z.record(z.string(), z.integer()):nullable(NULL)
        assertTrue(R:is({ a = 1 })); assertTrue(R:is(NULL)); assertFalse(R:is({ a = "x" }))
        local U = z.union(z.string(), z.integer()):nullable(NULL)
        assertTrue(U:is("a")); assertTrue(U:is(1)); assertTrue(U:is(NULL)); assertFalse(U:is(true))
        local L = z.lazy(function() return z.string() end):nullable(NULL)
        assertTrue(L:is("a")); assertTrue(L:is(NULL)); assertFalse(L:is(1))
        local E = z.enum({ "a", "b" }):nullable(NULL)
        assertTrue(E:is("a")); assertTrue(E:is(NULL)); assertFalse(E:is("c"))
        local I = z.int64():nullable(NULL)
        assertTrue(I:is(5)); assertTrue(I:is(NULL)); assertFalse(I:is("5"))
        local lit = z.literal("x"):nullable(NULL)
        assertTrue(lit:is("x")); assertTrue(lit:is(NULL)); assertFalse(lit:is("y"))
        local any = z.any():nullable(NULL)
        assertTrue(any:is(1)); assertTrue(any:is(NULL)); assertTrue(any:is(nil))
        assertFalse(z.never():nullable(NULL):is(nil)); assertTrue(z.never():nullable(NULL):is(NULL))
    end)

    test("nullable: nested fields and items accept the sentinel, a missing field does not", function()
        local S = z.object({
            name = z.string():nullable(NULL),
            tags = z.array(z.string():nullable(NULL)),
            note = z.string():optional():nullable(NULL),
        })
        assertTrue(S:is({ name = NULL, tags = {} }))
        assertTrue(S:is({ name = "a", tags = { "x", NULL }, note = NULL }))
        assertTrue(S:is({ name = "a", tags = {}, note = "n" }))
        assertFalse(S:is({ tags = {} }))
        assertFalse(S:is({ name = "a", tags = { nil, "x" } }))
        assertFalse(S:is({ name = OTHER, tags = {} }))
        assertFalse(S:is({ name = "a", tags = { OTHER } }))
    end)

    test("nullable: safeParse returns the sentinel as it is, not nil", function()
        local S = z.object({ a = z.string():nullable(NULL), b = z.integer():optional() })
        local ok, out = S:safeParse({ a = NULL })
        assertTrue(ok)
        assertTrue(rawequal(out.a, NULL))
        assertEq(out.b, nil)
        local N = z.number():nullable(NULL)
        local ok2, out2 = N:safeParse(NULL)
        assertTrue(ok2); assertTrue(rawequal(out2, NULL))
        assertTrue(rawequal(N:parse(NULL), NULL))
        local U = z.record(z.string(), z.string():nullable(NULL))
        local ok3, out3 = U:safeParse({ k = NULL })
        assertTrue(ok3); assertTrue(rawequal(out3.k, NULL))
    end)

    test("nullable: impure schemas return the sentinel and skip the steps before nullable()", function()
        local calls = 0
        local count = function(v) calls = calls + 1; return v end
        local before = z.string():nullable(NULL):transform(count)
        local ok, out = before:safeParse(NULL)
        assertTrue(ok); assertTrue(rawequal(out, NULL)); assertEq(calls, 1)
        local after = z.string():transform(count):nullable(NULL)
        calls = 0
        ok, out = after:safeParse(NULL)
        assertTrue(ok); assertTrue(rawequal(out, NULL)); assertEq(calls, 0)
        ok, out = after:safeParse("a")
        assertTrue(ok); assertEq(out, "a"); assertEq(calls, 1)
        local refined = z.string():nullable(NULL):refine(function(v) return v ~= "bad" end)
        assertTrue(refined:is(NULL)); assertTrue(refined:is("ok")); assertFalse(refined:is("bad"))
        assertFalse(refined:is(nil)); assertFalse(refined:is(OTHER))
        local defaulted = z.string():default("d"):nullable(NULL)
        ok, out = defaulted:safeParse(nil)
        assertTrue(ok); assertEq(out, "d")
        ok, out = defaulted:safeParse(NULL)
        assertTrue(ok); assertTrue(rawequal(out, NULL))
    end)

    test("nullable: an impure object keeps the sentinel field and strips unknown keys", function()
        local S = z.object({ a = z.string():nullable(NULL):transform(function(v) return v end) }):strip()
        local ok, out = S:safeParse({ a = NULL, extra = 1 })
        assertTrue(ok); assertTrue(rawequal(out.a, NULL)); assertEq(out.extra, nil)
        local N = z.object({ a = z.string():transform(function(v) return v end) }):nullable(NULL)
        ok, out = N:safeParse(NULL)
        assertTrue(ok); assertTrue(rawequal(out, NULL))
        assertFalse(N:is({ a = 1 }))
    end)

    test("nullable: the issues call the sentinel null, and nil stays nil", function()
        local issue = firstIssue(z.string(), NULL)
        assertDeepEq(issue, { path = {}, code = "invalid_type", expected = "string", got = "null" })
        local _, _, err = z.string():safeParse(NULL)
        assertEq(err:format(), "<root>: Expected string, got null")
        assertEq(firstIssue(z.string():nullable(NULL), 1).got, "number")
        assertEq(firstIssue(z.string():nullable(NULL), nil).got, "nil")
        assertEq(firstIssue(z.literal("a"), NULL).got, "null")
        assertEq(firstIssue(z.enum({ "a" }), NULL).got, "null")
        assertEq(firstIssue(z.number(), NULL).got, "null")
        local nested = firstIssue(z.object({ a = z.integer() }), { a = NULL })
        assertDeepEq(nested.path, { "a" })
        assertEq(nested.got, "null")
        assertEq(firstIssue(z.string(), {}).got, "table")
        assertEq(firstIssue(z.string(), "x" == "y").got, "boolean")
    end)

    test("nullable: _check reports the base issue for a value that is neither nil nor the sentinel", function()
        local S = z.integer():nullable(NULL)
        local issues = S._check("x", {}, 0, nil)
        assertEq(issues[1].code, "invalid_type")
        assertEq(S._check(NULL, {}, 0, nil), nil)
        assertEq(z.integer():optional():nullable(NULL)._check(nil, {}, 0, nil), nil)
    end)

    test("nullable: the sentinel set by nullable(s) overrides the earlier one", function()
        local S = z.string():nullable(NULL):nullable(OTHER)
        assertTrue(S:is(OTHER)); assertFalse(S:is(NULL))
    end)

    test("nullable: codegen and closures agree", function()
        local values = {
            n = 10, "a", NULL, OTHER, nil, 1, {}, { 1 }, { a = "x" }, { a = NULL },
        }
        local builds = {
            function() return z.string():nullable(NULL) end,
            function() return z.string():optional():nullable(NULL) end,
            function() return z.array(z.string():nullable(NULL)) end,
            function() return z.object({ a = z.string():nullable(NULL) }):nullable(NULL) end,
            function() return z.object({ a = z.string():nullable(NULL):optional() }) end,
            function() return z.union(z.string(), z.array(z.string())):nullable(NULL) end,
            function() return z.tuple({ z.string():nullable(NULL) }) end,
            function() return z.record(z.string(), z.string():nullable(NULL)) end,
            function() return z.null(NULL) end,
            function() return z.null(NULL):optional() end,
        }
        for _, build in ipairs(builds) do sameVerdict(build, values) end
    end)

    test("nullable: depth-tracked schemas honour the sentinel", function()
        local S = z.object({ a = z.object({ b = z.string():nullable(NULL) }):nullable(NULL) })
        assertTrue(S:is({ a = NULL })); assertTrue(S:is({ a = { b = NULL } }))
        assertFalse(S:is({ a = { b = OTHER } }))
        local limited = S:limits({ maxDepth = 2 })
        assertTrue(limited:is({ a = NULL })); assertTrue(limited:is({ a = { b = NULL } }))
    end)

    test("nullable: discriminatedUnion refuses a nullable variant or discriminant", function()
        local a = z.object({ kind = z.literal("a") })
        local b = z.object({ kind = z.literal("b") })
        assertTrue(z.discriminatedUnion("kind", a, b):is({ kind = "a" }))
        assertThrows(function() z.discriminatedUnion("kind", a:nullable(NULL), b) end)
        assertThrows(function()
            z.discriminatedUnion("kind", z.object({ kind = z.literal("a"):nullable(NULL) }), b)
        end)
        assertTrue(z.discriminatedUnion("kind", a, b):nullable(NULL):is(NULL))
    end)

    test("config: null sets the default sentinel that null() and nullable() use afterwards", function()
        local before = z.config()
        assertEq(before.null, nil)
        local DEFAULT = newSentinel("DEFAULT")
        local early = z.string()
        local ret = z.config({ null = DEFAULT })
        assertTrue(rawequal(ret.null, DEFAULT))
        assertTrue(rawequal(z.config().null, DEFAULT))
        local S = z.string():nullable()
        local N = z.null()
        assertTrue(S:is(DEFAULT)); assertTrue(N:is(DEFAULT))
        assertFalse(S:is(NULL)); assertFalse(N:is(NULL))
        assertTrue(early:nullable():is(DEFAULT))
        assertTrue(z.string():nullable(NULL):is(NULL))
        assertFalse(z.string():nullable(NULL):is(DEFAULT))
        assertTrue(z.null(NULL):is(NULL))
        local SECOND = newSentinel("SECOND")
        z.config({ null = SECOND })
        assertTrue(S:is(DEFAULT)); assertFalse(S:is(SECOND))
        assertTrue(z.string():nullable():is(SECOND))
        assertEq(firstIssue(z.string(), SECOND).got, "null")
        assertEq(firstIssue(z.string(), DEFAULT).got, "null")
        z.config({ null = DEFAULT })
    end)

    test("config: null leaves the other options alone and rejects a bad sentinel", function()
        local before = z.config()
        z.config({ null = before.null })
        local after = z.config()
        assertEq(after.maxDepth, before.maxDepth)
        assertEq(after.maxKeys, before.maxKeys)
        assertEq(after.codegen, before.codegen)
        assertThrows(function() z.config({ null = nan }) end)
        assertTrue(rawequal(z.config().null, before.null))
        assertThrows(function() z.string():limits({ null = NULL }) end)
    end)

    test("nullable: works with a userdata sentinel and a cdata sentinel", function()
        local U = z.string():nullable(io.stdin)
        assertTrue(U:is(io.stdin)); assertTrue(U:is("a")); assertFalse(U:is(io.stderr))
        assertEq(firstIssue(z.string(), io.stdin).got, "null")
        if ffi then
            local sentinel = ffi.cast("void *", 0)
            assertTrue(sentinel == nil)
            local C = z.string():nullable(sentinel)
            assertTrue(C:is(sentinel)); assertTrue(C:is("a"))
            assertFalse(C:is(ffi.cast("void *", 0)))
            assertFalse(C:is(0)); assertFalse(C:is(nil))
            assertEq(firstIssue(z.string(), sentinel).got, "null")
            assertTrue(z.null(sentinel):is(sentinel))
            assertFalse(z.null(sentinel):is(nil))
            assertTrue(z.string():optional():nullable(sentinel):is(nil))
            assertTrue(rawequal(z.string():nullable(sentinel):safeParse(sentinel) and sentinel, sentinel))
        end
    end)

    test("nullable: a number, string or boolean sentinel is matched but not renamed in issues", function()
        local S = z.integer():nullable("NULL")
        assertTrue(S:is("NULL")); assertTrue(S:is(3)); assertFalse(S:is("null"))
        assertEq(firstIssue(z.integer(), "NULL").got, "string")
        local B = z.string():nullable(false)
        assertTrue(B:is(false)); assertTrue(B:is("a")); assertFalse(B:is(true)); assertFalse(B:is(nil))
    end)
end
