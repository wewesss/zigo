return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local function upper(v) return v:upper() end
    local function toNumber(v) return tonumber(v) end

    test("purity: plain schemas stay pure, every impure modifier clears the flag", function()
        assertTrue(z.string().pure)
        assertTrue(z.string():min(2):optional().pure)
        assertTrue(z.object({ a = z.string() }):strict().pure)
        assertFalse(z.string():default("x").pure)
        assertFalse(z.string():transform(upper).pure)
        assertFalse(z.string():refine(function() return true end).pure)
        assertFalse(z.string():pipe(z.string()).pure)
        assertFalse(z.coerce.number().pure)
        assertFalse(z.object({}):strip().pure)
    end)

    test("purity: containers propagate impurity from their children", function()
        local impure = z.string():default("x")
        assertFalse(z.object({ a = impure }).pure)
        assertFalse(z.array(impure).pure)
        assertFalse(z.array(z.object({ a = z.number():transform(tostring) })).pure)
        assertTrue(z.object({ a = z.string(), b = z.array(z.number()) }).pure)
    end)

    test("purity: strict after strip makes the object pure again", function()
        assertFalse(z.object({}):strip().pure)
        assertTrue(z.object({}):strip():strict().pure)
    end)

    test("default: a nil input becomes the value as-is", function()
        local S = z.string():default("x")
        local ok, value = S:safeParse(nil)
        assertTrue(ok); assertEq(value, "x")
        assertEq(S:parse(nil), "x")
        assertEq(S:parse("given"), "given")
    end)

    test("default: false is a valid default and is not replaced", function()
        local S = z.boolean():default(false)
        assertEq(S:parse(nil), false)
        assertEq(z.boolean():default(true):parse(false), false)
    end)

    test("default: a table is returned as the same table every time", function()
        local shared = {}
        local S = z.array(z.string()):default(shared)
        assertTrue(rawequal(S:parse(nil), shared))
        assertTrue(rawequal(S:parse(nil), shared))
    end)

    test("default: a function is called each time and gives a fresh value", function()
        local calls = 0
        local S = z.array(z.string()):default(function()
            calls = calls + 1
            return {}
        end)
        local a, b = S:parse(nil), S:parse(nil)
        assertTrue(a ~= b)
        assertEq(calls, 2)
        S:parse({ "kept" })
        assertEq(calls, 2)
    end)

    test("default: the default value is not validated", function()
        assertEq(z.string():default(5):parse(nil), 5)
    end)

    test("default: nil is accepted by _test and _check", function()
        local S = z.integer():default(1)
        assertTrue(S._test(nil))
        assertEq(S._check(nil, {}, 0, nil), nil)
        assertTrue(S:is(nil))
        assertFalse(S:is("x"))
    end)

    test("default: a non-nil invalid input is still rejected", function()
        local ok, _, err = z.integer():default(1):safeParse("x")
        assertFalse(ok)
        assertEq(err.issues[1].code, "invalid_type")
    end)

    test("default: default() without a value raises", function()
        assertThrows(function() return z.string():default(nil) end)
        assertThrows(function() return z.string():default() end)
    end)

    test("default: fills a missing field of an object without touching the input", function()
        local S = z.object({ name = z.string(), role = z.string():default("user") })
        local input = { name = "a", extra = 1 }
        local out = S:parse(input)
        assertDeepEq(out, { name = "a", role = "user", extra = 1 })
        assertEq(input.role, nil)
        assertTrue(out ~= input)
    end)

    test("default: fills array items only through item schemas", function()
        local S = z.array(z.string():default("x"))
        assertDeepEq(S:parse({ "a", "b" }), { "a", "b" })
        assertDeepEq(S:parse({}), {})
    end)

    test("transform: the output replaces the input", function()
        local S = z.string():transform(upper)
        local ok, value = S:safeParse("abc")
        assertTrue(ok); assertEq(value, "ABC")
        assertEq(S:parse("abc"), "ABC")
    end)

    test("transform: base validation runs first and the function is skipped on failure", function()
        local calls = 0
        local S = z.string():min(2):transform(function(v) calls = calls + 1 return v end)
        assertFalse(S:is(5))
        assertFalse(S:is("a"))
        assertEq(calls, 0)
    end)

    test("transform: runs once on success for parse, safeParse and is", function()
        local calls = 0
        local S = z.string():transform(function(v) calls = calls + 1 return v end)
        S:parse("a"); assertEq(calls, 1)
        S:safeParse("a"); assertEq(calls, 2)
        S:is("a"); assertEq(calls, 3)
    end)

    test("transform: receives the context and the failure comes from ctx:addIssue", function()
        local S = z.string():transform(function(v, ctx)
            if v == "bad" then
                ctx:addIssue({ message = "no bad words", code = "banned" })
                return v
            end
            return v
        end)
        assertEq(S:parse("ok"), "ok")
        local ok, value, err = S:safeParse("bad")
        assertFalse(ok); assertEq(value, nil)
        assertDeepEq(err.issues, { { path = {}, code = "banned", message = "no bad words" } })
        assertFalse(S:is("bad"))
    end)

    test("transform: addIssue defaults to the custom code and several issues are kept", function()
        local S = z.string():transform(function(v, ctx)
            ctx:addIssue({ message = "first" })
            ctx:addIssue({ message = "second" })
            return v
        end)
        local _, _, err = S:safeParse("x")
        assertEq(#err.issues, 2)
        assertEq(err.issues[1].code, "custom")
        assertEq(err.issues[2].message, "second")
    end)

    test("transform: issues carry the path of the field", function()
        local S = z.object({
            n = z.array(z.string():transform(function(v, ctx)
                if v == "x" then ctx:addIssue({ message = "no x" }) end
                return v
            end)),
        })
        local _, _, err = S:safeParse({ n = { "a", "x", "b", "x" } })
        assertEq(err:format(), "n[2]: no x\nn[4]: no x")
    end)

    test("transform: addIssue validates its argument", function()
        local S = z.string():transform(function(v, ctx) ctx:addIssue("nope") return v end)
        assertThrows(function() return S:safeParse("x") end)
        local T = z.string():transform(function(v, ctx) ctx:addIssue({ message = 5 }) return v end)
        assertThrows(function() return T:safeParse("x") end)
    end)

    test("transform: an error raised by the function is not caught", function()
        local S = z.string():transform(function() error("boom", 0) end)
        local ok, err = pcall(function() return S:safeParse("x") end)
        assertFalse(ok); assertEq(err, "boom")
        local ok2, err2 = pcall(function() return S:parse("x") end)
        assertFalse(ok2); assertEq(err2, "boom")
    end)

    test("transform: a transform can return nil", function()
        local S = z.string():transform(function() return nil end)
        local ok, value = S:safeParse("x")
        assertTrue(ok); assertEq(value, nil)
    end)

    test("transform: expects a function", function()
        assertThrows(function() return z.string():transform("no") end)
        assertThrows(function() return z.string():transform() end)
    end)

    test("transform: chained transforms run in order", function()
        local S = z.string():transform(upper):transform(function(v) return v .. "!" end)
        assertEq(S:parse("a"), "A!")
    end)

    test("refine: a true result keeps the value, false adds a custom issue", function()
        local S = z.integer():refine(function(v) return v % 2 == 0 end, { message = "must be even" })
        assertEq(S:parse(4), 4)
        local ok, value, err = S:safeParse(3)
        assertFalse(ok); assertEq(value, nil)
        assertDeepEq(err.issues, { { path = {}, code = "custom", message = "must be even" } })
        assertEq(err:format(), "<root>: must be even")
    end)

    test("refine: a nil result counts as a failure", function()
        local S = z.string():refine(function() end)
        assertFalse(S:is("x"))
    end)

    test("refine: without a message the default text is used", function()
        local _, _, err = z.string():refine(function() return false end):safeParse("x")
        assertEq(err:format(), "<root>: Invalid input")
    end)

    test("refine: options code and path", function()
        local S = z.object({ a = z.string(), b = z.string() }):refine(function(v)
            return v.a == v.b
        end, { message = "a and b differ", code = "mismatch", path = { "b" } })
        assertTrue(S:is({ a = "x", b = "x" }))
        local _, _, err = S:safeParse({ a = "x", b = "y" })
        assertDeepEq(err.issues, { { path = { "b" }, code = "mismatch", message = "a and b differ" } })
        assertEq(err:format(), "b: a and b differ")
    end)

    test("refine: the path option is appended to the path of the node", function()
        local S = z.object({
            inner = z.object({ x = z.number() }):refine(function() return false end, { path = { "x" }, message = "bad" }),
        })
        local _, _, err = S:safeParse({ inner = { x = 1 } })
        assertDeepEq(err.issues[1].path, { "inner", "x" })
    end)

    test("refine: the function may report through ctx:addIssue", function()
        local S = z.string():refine(function(v, ctx)
            if #v > 2 then ctx:addIssue({ message = "too long", code = "long" }) end
            return true
        end)
        assertTrue(S:is("ab"))
        local _, _, err = S:safeParse("abc")
        assertDeepEq(err.issues, { { path = {}, code = "long", message = "too long" } })
    end)

    test("refine: the function only runs after the base validation", function()
        local calls = 0
        local S = z.string():refine(function() calls = calls + 1 return true end)
        S:is(5)
        assertEq(calls, 0)
    end)

    test("refine: opts and function are checked", function()
        assertThrows(function() return z.string():refine("no") end)
        assertThrows(function() return z.string():refine(function() end, "no") end)
        assertThrows(function() return z.string():refine(function() end, { message = 1 }) end)
        assertThrows(function() return z.string():refine(function() end, { code = 1 }) end)
        assertThrows(function() return z.string():refine(function() end, { path = "a" }) end)
    end)

    test("refine after transform sees the transformed value", function()
        local seen
        local S = z.string():transform(upper):refine(function(v) seen = v return v == "ABC" end)
        assertEq(S:parse("abc"), "ABC")
        assertEq(seen, "ABC")
        assertFalse(S:is("abd"))
    end)

    test("transform after refine sees the original value", function()
        local seen
        local S = z.string():refine(function(v) seen = v return true end):transform(upper)
        assertEq(S:parse("abc"), "ABC")
        assertEq(seen, "abc")
    end)

    test("chain order: a failing refine stops the later steps", function()
        local later = 0
        local S = z.string():refine(function() return false end):transform(function(v) later = later + 1 return v end)
        assertFalse(S:is("x"))
        assertEq(later, 0)
    end)

    test("pipe: the next schema validates the output of the previous one", function()
        local S = z.string():transform(toNumber):pipe(z.integer():min(1))
        assertEq(S:parse("5"), 5)
        local ok, _, err = S:safeParse("0")
        assertFalse(ok)
        assertEq(err.issues[1].code, "too_small")
        local ok2, _, err2 = S:safeParse("abc")
        assertFalse(ok2)
        assertEq(err2.issues[1].code, "invalid_type")
        assertEq(err2.issues[1].expected, "integer")
    end)

    test("pipe: is() checks the output of the pipe", function()
        local S = z.string():transform(function(v) return #v end):pipe(z.integer():min(3))
        assertTrue(S:is("abc"))
        assertFalse(S:is("ab"))
    end)

    test("pipe: the target can be impure", function()
        local S = z.string():pipe(z.string():transform(upper))
        assertEq(S:parse("a"), "A")
        local T = z.string():transform(upper):pipe(z.string():refine(function(v) return v ~= "A" end, { message = "no A" }))
        assertFalse(T:is("a"))
        assertEq(T:parse("b"), "B")
    end)

    test("pipe: issues of the target keep the path of the field", function()
        local S = z.object({ n = z.string():transform(toNumber):pipe(z.integer()) })
        local _, _, err = S:safeParse({ n = "1.5" })
        assertEq(err:format(), "n: Expected integer, got float")
    end)

    test("pipe: expects a schema", function()
        assertThrows(function() return z.string():pipe("x") end)
        assertThrows(function() return z.string():pipe() end)
    end)

    test("optional before transform: the function sees nil", function()
        local seen = "unset"
        local S = z.string():optional():transform(function(v) seen = v return "t" end)
        assertEq(S:parse(nil), "t")
        assertEq(seen, nil)
    end)

    test("optional after transform: nil skips the function", function()
        local calls = 0
        local S = z.string():transform(function(v) calls = calls + 1 return v end):optional()
        local ok, value = S:safeParse(nil)
        assertTrue(ok); assertEq(value, nil)
        assertEq(calls, 0)
        S:parse("a")
        assertEq(calls, 1)
    end)

    test("default before refine: the refine runs on the default", function()
        local S = z.string():default("d"):refine(function(v) return v ~= "d" end, { message = "no d" })
        assertFalse(S:is(nil))
        assertTrue(S:is("e"))
    end)

    test("default after transform: nil skips the transform", function()
        local S = z.string():transform(upper):default("d")
        assertEq(S:parse(nil), "d")
        assertEq(S:parse("a"), "A")
    end)

    test("optional after default: the last call wins", function()
        local S = z.string():default("d"):optional()
        assertEq(S:parse(nil), nil)
        local T = z.string():optional():default("d")
        assertEq(T:parse(nil), "d")
    end)

    test("a kind modifier after transform, refine or pipe raises", function()
        assertThrows(function() return z.string():transform(upper):min(1) end)
        assertThrows(function() return z.number():refine(function() return true end):between(1, 2) end)
        assertThrows(function() return z.array(z.string()):pipe(z.any()):max(1) end)
        assertThrows(function() return z.object({}):transform(function(v) return v end):strict() end)
        assertThrows(function() return z.object({}):transform(function(v) return v end):strip() end)
    end)

    test("a kind modifier after default still applies to the base", function()
        local S = z.string():default("d"):min(3)
        assertEq(S:parse(nil), "d")
        assertFalse(S:is("ab"))
    end)

    test("object: an impure child gives a new output and keeps unknown keys", function()
        local S = z.object({ a = z.string():transform(upper), b = z.number() })
        local input = { a = "x", b = 1, extra = true }
        local out = S:parse(input)
        assertDeepEq(out, { a = "X", b = 1, extra = true })
        assertEq(input.a, "x")
    end)

    test("object: strict still rejects unknown keys when a child is impure", function()
        local S = z.object({ a = z.string():default("d") }):strict()
        assertTrue(S:is({}))
        local ok, _, err = S:safeParse({ a = "x", z = 1 })
        assertFalse(ok)
        assertDeepEq(err.issues, { { path = { "z" }, code = "unrecognized_key" } })
    end)

    test("object: all failing fields are reported in key order", function()
        local S = z.object({
            b = z.string():transform(upper),
            a = z.integer():default(1),
            c = z.string():refine(function() return false end, { message = "never" }),
        })
        local _, _, err = S:safeParse({ a = "x", b = 2, c = "y" })
        assertEq(err:format(), table.concat({
            "a: Expected integer, got string",
            "b: Expected string, got number",
            "c: never",
        }, "\n"))
    end)

    test("object: a non-table input is reported as invalid_type", function()
        local S = z.object({ a = z.string():default("d") })
        local _, _, err = S:safeParse(5)
        assertDeepEq(err.issues, { { path = {}, code = "invalid_type", expected = "object", got = "number" } })
        local _, _, nilErr = S:safeParse(nil)
        assertEq(nilErr.issues[1].got, "nil")
    end)

    test("object: meta objects are read through their metatable", function()
        local S = z.object({ a = z.string():default("d") }, { meta = true })
        local proxy = setmetatable({}, { __index = { a = "inherited" } })
        assertEq(S:parse(proxy).a, "inherited")
    end)

    test("array: items are transformed into a new array", function()
        local S = z.array(z.string():transform(upper))
        local input = { "a", "b" }
        local out = S:parse(input)
        assertDeepEq(out, { "A", "B" })
        assertDeepEq(input, { "a", "b" })
    end)

    test("array: bounds, holes and shape are still checked", function()
        local S = z.array(z.string():transform(upper)):max(2)
        assertFalse(S:is({ "a", "b", "c" }))
        assertFalse(S:is({ "a", nil, "c" }))
        assertFalse(S:is({ "a", extra = 1 }))
        assertFalse(S:is("x"))
        local _, _, err = S:safeParse({ "a", "b", "c" })
        assertEq(err.issues[1].code, "too_big")
        local _, _, shape = S:safeParse({ "a", extra = 1 })
        assertEq(shape.issues[1].code, "invalid_array")
    end)

    test("array: item issues carry the index", function()
        local S = z.array(z.number():refine(function(v) return v > 0 end, { message = "positive" }))
        local _, _, err = S:safeParse({ 1, -1, 2, -3 })
        assertEq(err:format(), "[2]: positive\n[4]: positive")
    end)

    test("impure schemas: safeParse and parse keep the tuple and the error object", function()
        local S = z.string():transform(upper)
        assertEq(select("#", S:safeParse("a")), 2)
        local ok, value, err = S:safeParse(1)
        assertFalse(ok); assertEq(value, nil); assertTrue(z.isError(err))
        local raised, e = pcall(function() return S:parse(1) end)
        assertFalse(raised); assertTrue(z.isError(e))
        assertEq(tostring(e):find("ZigoError: 1 issue(s)", 1, true) ~= nil, true)
    end)

    test("impure schemas: _test and _check answer like safeParse", function()
        local S = z.object({ n = z.string():transform(toNumber):pipe(z.integer()) })
        local good, bad = { n = "3" }, { n = "x" }
        assertTrue(S._test(good)); assertFalse(S._test(bad))
        assertEq(S._check(good, {}, 0, nil), nil)
        local issues = S._check(bad, {}, 0, nil)
        assertEq(#issues, 1)
        assertDeepEq(issues[1].path, { "n" })
        assertEq(S:is(good), S._test(good))
    end)

    test("impure schemas: _check appends to the list it receives", function()
        local S = z.string():refine(function() return false end, { message = "m" })
        local existing = { { path = {}, code = "x" } }
        local out = S._check("a", {}, 0, existing)
        assertTrue(rawequal(out, existing))
        assertEq(#out, 2)
    end)

    test("impure schemas: compilation is lazy and cached", function()
        local S = z.string():transform(upper)
        assertEq(rawget(S, "_parse"), nil)
        local p = S._parse
        assertEq(rawget(S, "_parse"), p)
        local _ = S._test
        assertEq(type(rawget(S, "_test")), "function")
    end)

    test("impure schemas: nodes are frozen and shareable", function()
        local S = z.string():transform(upper)
        assertThrows(function() S.kind = "x" end)
        assertThrows(function() S.extra = 1 end)
        local co = coroutine.wrap(function()
            for _ = 1, 3 do coroutine.yield(S:parse("a")) end
        end)
        assertEq(co(), "A"); assertEq(S:parse("b"), "B"); assertEq(co(), "A")
    end)

    test("impure schemas: hostile keys work with refine and default", function()
        local key = "]] os.exit() --"
        local S = z.object({ [key] = z.string():default("d") }):refine(function(v) return v[key] ~= "" end)
        assertEq(S:parse({})[key], "d")
        assertFalse(S:is({ [key] = "" }))
    end)

    test("custom issues are deterministic over 100 runs", function()
        local S = z.object({
            c = z.string():refine(function(v) return #v > 5 end, { message = "short c" }),
            a = z.string():transform(function(v, ctx)
                ctx:addIssue({ message = "a1" })
                ctx:addIssue({ message = "a2", code = "second" })
                return v
            end),
            b = z.array(z.number():refine(function(v) return v > 0 end, { message = "neg" })),
        }):strict()
        local input = { c = "x", a = "y", b = { 1, -1, -2 }, z = 1, [3] = 1 }
        local first
        for run = 1, 100 do
            local _, _, err = S:safeParse(input)
            local text = err:format()
            if run == 1 then
                first = text
                assertEq(first, table.concat({
                    "a: a1", "a: a2", "b[2]: neg", "b[3]: neg", "c: short c", "[3]: Unrecognized key",
                    "z: Unrecognized key",
                }, "\n"))
            else
                assertEq(text, first)
            end
        end
    end)

    test("issues: a message wins over the registered text and flatten uses it", function()
        local _, _, err = z.string():refine(function() return false end, { message = "mine" }):safeParse("x")
        assertEq(err:format({ custom = "other" }), "<root>: mine")
        assertDeepEq(err:flatten(), { formErrors = { "mine" }, fieldErrors = {} })
    end)

    test("issues: the custom text can be replaced through setMessages", function()
        local original = z.messages.custom
        local _, _, err = z.string():refine(function() return false end):safeParse("x")
        local ok, problem = pcall(function()
            z.setMessages({ custom = "refus" })
            assertEq(err:format(), "<root>: refus")
        end)
        z.setMessages({ custom = original })
        assertTrue(ok, problem)
    end)

    test("a failure that disappears on the second pass still reports an error", function()
        local first = true
        local S = z.string():refine(function()
            if first then first = false return false end
            return true
        end)
        local ok, _, err = S:safeParse("x")
        assertFalse(ok)
        assertTrue(z.isError(err))
        assertTrue(#err.issues >= 1)
    end)

    local function withCodegen(flag, fn)
        local previous = z.config().codegen
        z.config({ codegen = flag })
        local ok, err = pcall(fn)
        z.config({ codegen = previous })
        if not ok then error(err, 0) end
    end

    local function counted()
        local c = { n = 0 }
        function c.bump(v) c.n = c.n + 1 return v end
        function c.pass(v) c.n = c.n + 1 return true end
        function c.fail(v) c.n = c.n + 1 return false end
        function c.add(v, ctx) c.n = c.n + 1 ctx:addIssue({ message = "bad" }) return v end
        function c.make() c.n = c.n + 1 return "d" end
        return c
    end

    local function eachCodegen(name, build)
        for _, flag in ipairs({ true, false }) do
            test(name .. (flag and " (codegen)" or " (closures)"), function()
                withCodegen(flag, function() build(flag) end)
            end)
        end
    end

    eachCodegen("callbacks run once: transform, valid and invalid input", function()
        local c = counted()
        local S = z.object({
            bad = z.string():transform(c.bump),
            ok = z.string():transform(c.bump),
            wrong = z.number(),
        })
        local good = { bad = "a", ok = "b", wrong = 1 }
        assertTrue((S:safeParse(good))); assertEq(c.n, 2)
        c.n = 0
        assertTrue(pcall(S.parse, S, good)); assertEq(c.n, 2)
        c.n = 0
        local ok = S:safeParse({ bad = "a", ok = "b", wrong = "x" })
        assertFalse(ok); assertEq(c.n, 2)
        c.n = 0
        assertFalse(pcall(S.parse, S, { bad = "a", ok = "b", wrong = "x" })); assertEq(c.n, 2)
    end)

    eachCodegen("callbacks run once: refine, valid and invalid input", function()
        local c = counted()
        local P = z.string():refine(c.pass)
        local F = z.string():refine(c.fail)
        assertTrue((P:safeParse("a"))); assertEq(c.n, 1)
        c.n = 0
        assertFalse((F:safeParse("a"))); assertEq(c.n, 1)
        c.n = 0
        assertFalse(pcall(F.parse, F, "a")); assertEq(c.n, 1)
        c.n = 0
        assertTrue(pcall(P.parse, P, "a")); assertEq(c.n, 1)
    end)

    eachCodegen("callbacks run once: ctx:addIssue from transform and refine", function()
        local c = counted()
        local T = z.string():transform(c.add)
        local R = z.string():refine(function(v, ctx) c.n = c.n + 1 ctx:addIssue({ message = "r" }) return true end)
        local ok, _, err = T:safeParse("a")
        assertFalse(ok); assertEq(c.n, 1); assertEq(err.issues[1].message, "bad")
        c.n = 0
        ok, _, err = R:safeParse("a")
        assertFalse(ok); assertEq(c.n, 1); assertEq(err.issues[1].message, "r")
        c.n = 0
        assertFalse(pcall(T.parse, T, "a")); assertEq(c.n, 1)
    end)

    eachCodegen("callbacks run once: default function and pipe", function()
        local c = counted()
        local D = z.object({ a = z.string():default(c.make), b = z.number() })
        assertTrue((D:safeParse({ b = 1 }))); assertEq(c.n, 1)
        c.n = 0
        local ok, _, err = D:safeParse({ b = "x" })
        assertFalse(ok); assertEq(c.n, 1); assertEq(#err.issues, 1)
        c.n = 0
        assertFalse(pcall(D.parse, D, { b = "x" })); assertEq(c.n, 1)
        c.n = 0
        local P = z.string():transform(c.bump):pipe(z.string():min(3):refine(c.fail))
        assertFalse((P:safeParse("abcd"))); assertEq(c.n, 2)
        c.n = 0
        assertFalse((P:safeParse("ab"))); assertEq(c.n, 1)
    end)

    eachCodegen("callbacks run once: nested in object, array and union", function()
        local c = counted()
        local Item = z.object({ n = z.number():refine(c.fail, { message = "no" }) })
        local S = z.object({ list = z.array(Item), tag = z.string():transform(c.bump) })
        local ok, _, err = S:safeParse({ list = { { n = 1 }, { n = 2 } }, tag = "t" })
        assertFalse(ok); assertEq(c.n, 3); assertEq(#err.issues, 2)
        c.n = 0
        local U = z.union(z.number():refine(c.fail), z.string():refine(c.pass))
        assertTrue((U:safeParse("s"))); assertEq(c.n, 1)
        c.n = 0
        assertFalse((U:safeParse(5))); assertEq(c.n, 1)
        c.n = 0
        assertFalse(pcall(U.parse, U, 5)); assertEq(c.n, 1)
        c.n = 0
        local W = z.object({ u = U, t = z.string():transform(c.bump) })
        assertFalse((W:safeParse({ u = 5, t = "x" }))); assertEq(c.n, 2)
        c.n = 0
        assertTrue((W:safeParse({ u = "s", t = "x" }))); assertEq(c.n, 2)
    end)

    eachCodegen("callbacks run once: a pure sibling failing does not repeat an impure one", function()
        local c = counted()
        local S = z.array(z.object({ a = z.string():transform(c.bump), b = z.integer() }))
        local ok = S:safeParse({ { a = "x", b = 1 }, { a = "y", b = "no" }, { a = "z", b = 3 } })
        assertFalse(ok); assertEq(c.n, 3)
    end)

    test("context reuse: a parse started inside a callback leaves the outer one intact", function()
        local innerErr
        local inner = z.object({ n = z.string():transform(upper) })
        local outer = z.object({
            a = z.string():transform(function(v)
                local ok, _, err = inner:safeParse({ n = 5 })
                assertFalse(ok)
                innerErr = err
                return v
            end),
            b = z.number(),
        })
        local ok, _, err = outer:safeParse({ a = "x", b = "no" })
        assertFalse(ok)
        assertEq(err:format(), "b: Expected number, got string")
        assertEq(innerErr:format(), "n: Expected string, got number")
        local good, value = outer:safeParse({ a = "x", b = 1 })
        assertTrue(good); assertEq(value.a, "x")
    end)

    test("context reuse: an issue recorded before a nested parse survives it", function()
        local inner = z.object({ n = z.string():transform(upper) })
        local outer = z.object({
            a = z.number(),
            b = z.string():transform(function(v)
                local ok = inner:safeParse({ n = 5 })
                assertFalse(ok)
                return v
            end),
            c = z.string():refine(function() return false end, { message = "late" }),
        })
        local ok, _, err = outer:safeParse({ a = "no", b = "x", c = "y" })
        assertFalse(ok)
        assertEq(err:format(), "a: Expected number, got string\nc: late")
    end)

    test("context reuse: a callback that raises leaves later parses correct", function()
        local S = z.object({
            a = z.string():transform(function(v)
                if v == "boom" then error("boom", 0) end
                return v
            end),
            b = z.integer(),
        })
        local ok, err = pcall(S.safeParse, S, { a = "boom", b = 1 })
        assertFalse(ok); assertEq(err, "boom")
        local _, _, bad = S:safeParse({ a = "ok", b = "x" })
        assertEq(bad:format(), "b: Expected integer, got string")
        assertTrue((S:safeParse({ a = "ok", b = 1 })))
        local raised, e = pcall(S.parse, S, { a = "boom", b = 1 })
        assertFalse(raised); assertEq(e, "boom")
        assertTrue(pcall(S.parse, S, { a = "ok", b = 1 }))
    end)

    test("context reuse: a raise inside an abort-early union does not leave collection off", function()
        local U = z.union(
            z.string():transform(function(v)
                if v == "boom" then error("boom", 0) end
                return v
            end),
            z.number()
        )
        local S = z.object({ u = U, w = z.string():transform(function(v) return v end) }):limits({ abortEarly = true })
        local ok, err = pcall(S.safeParse, S, { u = "boom", w = "x" })
        assertFalse(ok); assertEq(err, "boom")
        local _, _, e1 = S:safeParse({ u = true, w = "x" })
        assertEq(e1.issues[1].code, "invalid_union")
        assertDeepEq(e1.issues[1].path, { "u" })
        local _, _, e2 = S:safeParse({ u = 1, w = 5 })
        assertDeepEq(e2.issues[1].path, { "w" })
    end)

    test("context reuse: the issues of one failure are not touched by the next parse", function()
        local S = z.object({
            a = z.string():refine(function() return false end, { message = "first" }),
            b = z.string():refine(function() return false end, { message = "second" }),
        })
        local _, _, e1 = S:safeParse({ a = "x", b = "y" })
        local before = e1:format()
        local _, _, e2 = S:safeParse({ a = "x", b = "y" })
        assertEq(e1:format(), before)
        assertEq(#e1.issues, 2)
        assertTrue(e1.issues ~= e2.issues)
        assertTrue(e1.issues[1].path ~= e2.issues[1].path)
    end)

    test("context reuse: the issue cap of each schema is honoured when contexts are shared", function()
        local function two() return z.object({
            a = z.string():refine(function() return false end),
            b = z.string():refine(function() return false end),
        }) end
        local capped, open = two():limits({ abortEarly = true }), two()
        for _ = 1, 3 do
            local _, _, e1 = capped:safeParse({ a = "x", b = "y" })
            local _, _, e2 = open:safeParse({ a = "x", b = "y" })
            assertEq(#e1.issues, 1)
            assertEq(#e2.issues, 2)
        end
    end)
end
