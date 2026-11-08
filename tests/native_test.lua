return function(env)
    local test, z = env.test, env.z
    local assertTrue, assertFalse, assertEq = env.assertTrue, env.assertFalse, env.assertEq
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local fileMt = getmetatable(io.stdout)

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

    local function proxy()
        if newproxy then
            local p = newproxy(true)
            return p, getmetatable(p)
        end
        return nil
    end

    local Class = { __index = {} }
    local Other = { __index = {} }
    local function instance(mt) return setmetatable({}, mt) end

    test("func: accepts functions of every kind and nothing else", function()
        local S = z.func()
        assertTrue(S:is(print)); assertTrue(S:is(function() end)); assertTrue(S:is(string.format))
        assertFalse(S:is(setmetatable({}, { __call = function() end })))
        assertFalse(S:is(nil)); assertFalse(S:is(0)); assertFalse(S:is("f")); assertFalse(S:is({}))
        assertFalse(S:is(io.stdout)); assertFalse(S:is(coroutine.create(function() end)))
        assertEq(S.kind, "func")
    end)

    test("func: the issue names the received type", function()
        assertDeepEq(firstIssue(z.func(), "x"), { path = {}, code = "invalid_type", expected = "function", got = "string" })
        assertDeepEq(firstIssue(z.func(), nil), { path = {}, code = "invalid_type", expected = "function", got = "nil" })
    end)

    test("func: works as a field, optional and nullable", function()
        local S = z.object({ on = z.func(), off = z.func():optional() })
        assertTrue(S:is({ on = print })); assertTrue(S:is({ on = print, off = print }))
        assertFalse(S:is({})); assertFalse(S:is({ on = print, off = 1 }))
        local sentinel = {}
        assertTrue(z.func():nullable(sentinel):is(sentinel))
    end)

    test("userdata: without a metatable it accepts any userdata", function()
        local S = z.userdata()
        assertTrue(S:is(io.stdout)); assertTrue(S:is(io.stderr))
        assertFalse(S:is(nil)); assertFalse(S:is({})); assertFalse(S:is("x")); assertFalse(S:is(print))
        local p = proxy()
        if p then assertTrue(S:is(p)) end
        assertEq(S.kind, "userdata")
    end)

    test("userdata: with a metatable it accepts the userdata whose getmetatable is that table", function()
        local S = z.userdata(fileMt)
        assertTrue(S:is(io.stdout))
        assertFalse(S:is({}))
        assertFalse(z.userdata(Class):is(io.stdout))
        local p, pmt = proxy()
        if p then
            assertTrue(z.userdata(pmt):is(p))
            assertFalse(z.userdata(pmt):is(io.stdout))
            assertFalse(S:is(p))
        end
    end)

    test("userdata: the issue names the expectation and the received type", function()
        assertDeepEq(firstIssue(z.userdata(), 1), { path = {}, code = "invalid_type", expected = "userdata", got = "number" })
        local issue = firstIssue(z.userdata(Class), io.stdout)
        assertEq(issue.code, "invalid_type")
        assertEq(issue.expected, "userdata with the given metatable")
        assertEq(issue.got, "userdata")
    end)

    test("userdata and instanceOf: the argument must be a table", function()
        assertThrows(function() z.userdata(1) end)
        assertThrows(function() z.userdata("mt") end)
        assertThrows(function() z.instanceOf() end)
        assertThrows(function() z.instanceOf("mt") end)
        assertThrows(function() z.instanceOf(print) end)
    end)

    test("instanceOf: accepts tables and userdata whose metatable is exactly mt", function()
        local S = z.instanceOf(Class)
        assertTrue(S:is(instance(Class)))
        assertFalse(S:is(instance(Other))); assertFalse(S:is({})); assertFalse(S:is(nil))
        assertFalse(S:is(Class)); assertFalse(S:is("x")); assertFalse(S:is(1)); assertFalse(S:is(print))
        assertTrue(z.instanceOf(fileMt):is(io.stdout))
        assertFalse(z.instanceOf(fileMt):is(instance(Class)))
        assertEq(S.kind, "instanceOf")
    end)

    test("instanceOf: does not follow inheritance through __index, only the exact metatable", function()
        local Base = {}
        Base.__index = Base
        local Child = setmetatable({}, { __index = Base })
        Child.__index = Child
        local obj = setmetatable({}, Child)
        assertTrue(z.instanceOf(Child):is(obj))
        assertFalse(z.instanceOf(Base):is(obj))
    end)

    test("instanceOf: strings and other types never match, even with the string metatable", function()
        local S = z.instanceOf(getmetatable(""))
        assertFalse(S:is("abc")); assertFalse(S:is(""))
        assertFalse(z.instanceOf(Class):is(true))
    end)

    test("instanceOf and userdata: a __metatable field replaces what getmetatable returns", function()
        local locked = setmetatable({}, { __metatable = "locked" })
        assertFalse(z.instanceOf(Class):is(locked))
        local shown = setmetatable({}, { __metatable = Class })
        assertTrue(z.instanceOf(Class):is(shown))
        local mt = { __metatable = Class }
        assertFalse(z.instanceOf(mt):is(setmetatable({}, mt)))
        assertTrue(z.instanceOf(Class):is(setmetatable({}, mt)))
    end)

    test("instanceOf: the issue names the expectation and the received type", function()
        local issue = firstIssue(z.instanceOf(Class), instance(Other))
        assertEq(issue.code, "invalid_type")
        assertEq(issue.expected, "instance of the given metatable")
        assertEq(issue.got, "table")
        assertEq(firstIssue(z.instanceOf(Class), 1).got, "number")
    end)

    test("instanceOf: as a field, an item, optional and nullable", function()
        local S = z.object({
            a = z.instanceOf(Class),
            list = z.array(z.instanceOf(Class)),
            maybe = z.instanceOf(Class):optional(),
        })
        assertTrue(S:is({ a = instance(Class), list = { instance(Class) } }))
        assertTrue(S:is({ a = instance(Class), list = {}, maybe = instance(Class) }))
        assertFalse(S:is({ a = instance(Other), list = {} }))
        assertFalse(S:is({ a = instance(Class), list = { instance(Other) } }))
        assertFalse(S:is({ a = instance(Class), list = {}, maybe = {} }))
        local sentinel = {}
        assertTrue(z.instanceOf(Class):nullable(sentinel):is(sentinel))
        assertEq(firstIssue(z.instanceOf(Class), sentinel).got, "null")
    end)

    test("instanceOf: an object with a metatable still goes through the object checks", function()
        local S = z.object({ x = z.integer() })
        assertTrue(S:is(setmetatable({ x = 1 }, Class)))
        local I = z.instanceOf(Class)
        assertTrue(I:is(setmetatable({ x = 1 }, Class)))
    end)

    test("userdata, instanceOf and func: codegen and closures agree", function()
        local values = {
            n = 12, nil, 1, "x", print, {}, io.stdout, io.stderr, instance(Class), instance(Other),
            setmetatable({}, { __metatable = "locked" }),
        }
        local builds = {
            function() return z.func() end,
            function() return z.func():optional() end,
            function() return z.userdata() end,
            function() return z.userdata(fileMt) end,
            function() return z.userdata(Class):optional() end,
            function() return z.instanceOf(Class) end,
            function() return z.instanceOf(fileMt) end,
            function() return z.instanceOf(Class):optional() end,
            function() return z.array(z.instanceOf(Class)) end,
            function() return z.union(z.func(), z.instanceOf(Class)) end,
            function() return z.object({ a = z.func():optional(), b = z.userdata():optional() }) end,
        }
        for _, build in ipairs(builds) do sameVerdict(build, values) end
    end)

    test("userdata, instanceOf and func: transforms and defaults still run on top", function()
        local S = z.func():transform(function(f) return f() end)
        local ok, out = S:safeParse(function() return 7 end)
        assertTrue(ok); assertEq(out, 7)
        assertFalse(S:is(1))
        local D = z.instanceOf(Class):default(instance(Class))
        assertTrue(D:safeParse(nil))
    end)

    test("userdata, instanceOf and func: do not allocate for a valid value", function()
        local S = z.object({ f = z.func(), u = z.userdata(fileMt), i = z.instanceOf(Class) })
        local v = { f = print, u = io.stdout, i = instance(Class) }
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
end
