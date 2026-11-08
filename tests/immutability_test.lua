return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local function copyDescriptor(n)
        local c = {}
        for k, v in pairs(n.d) do c[k] = v end
        return c
    end

    test("every modifier returns a new node and leaves the source untouched", function()
        local base = z.string()
        local before = copyDescriptor(base)
        local mods = {
            function(n) return n:min(1) end, function(n) return n:max(9) end,
            function(n) return n:len(3) end, function(n) return n:between(1, 2) end,
            function(n) return n:optional() end,
        }
        for _, m in ipairs(mods) do
            local derived = m(base)
            assertTrue(derived ~= base)
            assertDeepEq(copyDescriptor(base), before)
            assertEq(base.isOptional, false)
        end
    end)

    test("a derived node does not affect its source verdicts", function()
        local base = z.string()
        local short = base:max(2)
        assertTrue(base:is("abcdef"))
        assertFalse(short:is("abcdef"))
        short:optional()
        assertFalse(short:is(nil))
    end)

    test("object modifiers do not change the source", function()
        local o = z.object({ a = z.number() })
        local s = o:strict()
        assertTrue(o ~= s)
        assertTrue(o:is({ a = 1, b = 2 }))
        assertFalse(s:is({ a = 1, b = 2 }))
        assertEq(o.d.strict, false)
        assertEq(s.d.strict, true)
    end)

    test("array modifiers do not change the source", function()
        local a = z.array(z.number())
        local limited = a:max(1)
        assertTrue(a:is({ 1, 2, 3 }))
        assertFalse(limited:is({ 1, 2, 3 }))
    end)

    test("assigning to a node raises", function()
        local n = z.string()
        assertThrows(function() n.kind = "x" end)
        assertThrows(function() n.extra = 1 end)
        assertThrows(function() n._test = nil end)
        assertEq(n.kind, "string")
        local _ = n._test
        assertThrows(function() n.kind = "x" end)
        assertThrows(function() n.d = {} end)
        assertEq(n.kind, "string")
    end)

    test("nodes are recognised by isNode", function()
        assertTrue(z.isNode(z.string()))
        assertFalse(z.isNode({})); assertFalse(z.isNode("x")); assertFalse(z.isNode(nil))
    end)

    test("compilation is lazy and cached on the node", function()
        local n = z.string():min(2)
        assertEq(rawget(n, "_test"), nil)
        assertEq(rawget(n, "_check"), nil)
        assertEq(rawget(n, "kind"), nil)
        local t = n._test
        assertEq(type(t), "function")
        assertEq(rawget(n, "_test"), t)
        assertEq(n._test, t)
        assertEq(rawget(n, "_check"), nil)
        local c = n._check
        assertEq(rawget(n, "_check"), c)
    end)

    test("a derived node compiles on its own", function()
        local n = z.string()
        local t = n._test
        local m = n:min(2)
        assertEq(rawget(m, "_test"), nil)
        assertTrue(m._test ~= t)
    end)

    test("a shared child compiles once and is reused by parents", function()
        local child = z.string()
        local a = z.object({ x = child })
        local b = z.array(child)
        assertEq(rawget(child, "_test"), nil)
        local _ = a._test, b._test
        assertEq(type(rawget(child, "_test")), "function")
    end)

    test("_test can be read as a matchigo-style predicate", function()
        local pred = z.integer()._test
        assertTrue(pred(3)); assertFalse(pred("3"))
    end)

    test("schemas can be shared across coroutines", function()
        local S = z.object({ n = z.integer() })
        local co = coroutine.wrap(function()
            for i = 1, 3 do coroutine.yield(S:is({ n = i })) end
        end)
        assertTrue(co()); assertTrue(S:is({ n = 1 })); assertTrue(co()); assertTrue(co())
    end)
end
