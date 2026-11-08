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

    local function makeTree()
        local Tree
        Tree = z.object({
            value = z.integer(),
            children = z.array(z.lazy(function() return Tree end)):optional(),
        })
        return Tree
    end

    local function chain(levels)
        local root = { value = 0 }
        local cur = root
        for i = 2, levels do
            local nxt = { value = i }
            cur.children = { nxt }
            cur = nxt
        end
        return root
    end

    local function firstIssue(schema, v)
        local ok, _, err = schema:safeParse(v)
        assertFalse(ok)
        return err.issues[1], err
    end

    test("lazy: a recursive tree validates and reports the path", function()
        bothModes(function(flag)
            local Tree = makeTree()
            assertTrue(Tree.pure)
            assertEq(Tree.maxDepth, math.huge)
            if flag then assertTrue(z._isGenerated(Tree._test)) end
            local good = { value = 1, children = { { value = 2 }, { value = 3, children = { { value = 4 } } } } }
            assertTrue(Tree:is(good))
            local ok, out = Tree:safeParse(good)
            assertTrue(ok)
            assertEq(out, good)
            local bad = { value = 1, children = { { value = 2 }, { value = 3, children = { { value = "x" } } } } }
            assertFalse(Tree:is(bad))
            local issue, err = firstIssue(Tree, bad)
            assertEq(issue.code, "invalid_type")
            assertEq(err:format(), "children[2].children[1].value: Expected integer, got string")
            assertFalse(Tree:is({ value = 1, children = { 5 } }))
            assertFalse(Tree:is("x"))
            assertFalse(Tree:is(nil))
        end)
    end)

    test("lazy: the function runs once, on the first validation", function()
        bothModes(function()
            local calls = 0
            local Self
            Self = z.object({
                next = z.lazy(function() calls = calls + 1 return Self end):optional(),
            })
            assertEq(calls, 0)
            local _ = Self._test
            _ = Self._check
            assertEq(calls, 0)
            assertTrue(Self:is({ next = { next = {} } }))
            assertEq(calls, 1)
            assertFalse(Self:is({ next = { next = 1 } }))
            Self:safeParse({ next = { next = 1 } })
            assertEq(calls, 1)
        end)
    end)

    test("lazy: cyclic data is stopped by maxDepth", function()
        bothModes(function()
            local Tree = makeTree()
            local cyc = { value = 1 }
            cyc.children = { cyc }
            assertFalse(Tree:is(cyc))
            local issue, err = firstIssue(Tree, cyc)
            assertEq(issue.code, "too_deep")
            assertEq(issue.expected, 64)
            assertEq(#issue.path, 64)
            assertEq(#err.issues, 1)
            local a, b = { value = 1 }, { value = 2 }
            a.children, b.children = { b }, { a }
            assertEq(firstIssue(Tree, a).code, "too_deep")
            local ok, perr = pcall(function() return Tree:parse(cyc) end)
            assertFalse(ok)
            assertTrue(z.isError(perr))
            assertEq(perr.issues[1].code, "too_deep")
        end)
    end)

    test("lazy: 100000 levels of nesting end in too_deep, not in a stack error", function()
        bothModes(function()
            local Tree = makeTree()
            local deep = chain(100000)
            assertFalse(Tree:is(deep))
            local ok, _, err = Tree:safeParse(deep)
            assertFalse(ok)
            assertEq(err.issues[1].code, "too_deep")
            assertEq(#err.issues, 1)
            local U = z.union(Tree, z.string())
            assertFalse(U:is(deep))
            local R = z.record(z.string(), z.lazy(function() return Tree end))
            assertFalse(R:is({ a = deep }))
            local I = z.object({ title = z.string():transform(string.upper), tree = Tree })
            assertFalse(I:is({ title = "t", tree = deep }))
            assertEq(firstIssue(I, { title = "t", tree = deep }).code, "too_deep")
        end)
    end)

    test("lazy: the depth boundary is the same in _test, _check and _parse", function()
        bothModes(function()
            local Tree = makeTree()
            assertTrue(Tree:is(chain(32)))
            assertFalse(Tree:is(chain(33)))
            assertTrue(Tree:safeParse(chain(32)))
            assertFalse(Tree:safeParse(chain(33)))
            local Impure = z.object({ title = z.string():default("t"), tree = Tree })
            assertFalse(Impure.pure)
            assertTrue(Impure:is({ tree = chain(32) }))
            assertFalse(Impure:is({ tree = chain(33) }))
            local ok, out = Impure:safeParse({ tree = chain(32) })
            assertTrue(ok)
            assertEq(out.title, "t")
            assertEq(firstIssue(Impure, { tree = chain(33) }).code, "too_deep")
            local Tight = Tree:limits({ maxDepth = 6 })
            assertTrue(Tight:is(chain(3)))
            assertFalse(Tight:is(chain(4)))
            assertEq(firstIssue(Tight, chain(4)).code, "too_deep")
            local Loose = Tree:limits({ maxDepth = 200 })
            assertTrue(Loose:is(chain(100)))
            assertFalse(Loose:is(chain(101)))
        end)
    end)

    test("lazy: maxDepth can be lifted for deep but finite data", function()
        bothModes(function()
            local Tree = makeTree():limits({ maxDepth = math.huge })
            assertTrue(Tree:is(chain(300)))
            assertTrue(Tree:safeParse(chain(300)))
        end)
    end)

    test("lazy: mutual recursion", function()
        bothModes(function()
            local A, B
            A = z.object({ b = z.lazy(function() return B end):optional() })
            B = z.object({ a = z.lazy(function() return A end):optional(), n = z.integer() })
            assertTrue(A:is({}))
            assertTrue(A:is({ b = { n = 1, a = { b = { n = 2 } } } }))
            assertFalse(A:is({ b = { n = 1, a = { b = { n = "x" } } } }))
            assertFalse(A:is({ b = {} }))
            assertEq(firstIssue(A, { b = { n = 1, a = { b = {} } } }).code, "invalid_type")
        end)
    end)

    test("lazy: a recursive union of arrays and records (json)", function()
        bothModes(function()
            local Json
            Json = z.union(
                z.string(), z.number(), z.boolean(),
                z.array(z.lazy(function() return Json end)),
                z.record(z.string(), z.lazy(function() return Json end))
            )
            assertTrue(Json:is("x"))
            assertTrue(Json:is({ 1, "a", { true, { b = { 1, 2 } } } }))
            assertTrue(Json:is({ a = { b = { c = { 1 } } } }))
            assertFalse(Json:is({ 1, print }))
            assertFalse(Json:is({ a = { b = { c = print } } }))
            local ok, _, err = Json:safeParse({ 1, { 2, print } })
            assertFalse(ok)
            assertEq(err.issues[1].code, "invalid_union")
            local cyc = {}
            cyc[1] = cyc
            assertFalse(Json:is(cyc))
            assertFalse(Json:is(chain(100000)))
        end)
    end)

    test("lazy: inside a tuple, a discriminated union and as the root", function()
        bothModes(function()
            local Pair
            Pair = z.tuple({ z.integer() }):rest(z.lazy(function() return Pair end))
            assertTrue(Pair:is({ 1 }))
            assertTrue(Pair:is({ 1, { 2 }, { 3, { 4 } } }))
            assertFalse(Pair:is({ 1, { "x" } }))
            local Expr
            Expr = z.discriminatedUnion("kind",
                z.object({ kind = z.literal("num"), value = z.number() }),
                z.object({ kind = z.literal("neg"), arg = z.lazy(function() return Expr end) }))
            assertTrue(Expr:is({ kind = "neg", arg = { kind = "neg", arg = { kind = "num", value = 1 } } }))
            assertFalse(Expr:is({ kind = "neg", arg = { kind = "neg", arg = { kind = "num", value = "x" } } }))
            local Root = z.lazy(function() return z.array(z.string()) end)
            assertTrue(Root:is({ "a" }))
            assertFalse(Root:is({ 1 }))
            assertFalse(Root:is(nil))
            assertTrue(Root:optional():is(nil))
        end)
    end)

    test("lazy: optional lazy fields accept nil, required ones do not", function()
        bothModes(function()
            local S = z.object({
                a = z.lazy(function() return z.string() end),
                b = z.lazy(function() return z.string() end):optional(),
                c = z.lazy(function() return z.string():optional() end),
            })
            assertTrue(S:is({ a = "x" }))
            assertFalse(S:is({ b = "x" }))
            assertFalse(S:is({ a = "x", b = 1 }))
            assertTrue(S:is({ a = "x", b = "y", c = "z" }))
        end)
    end)

    test("lazy: an impure parent keeps its transforms around a lazy child", function()
        local Tree = makeTree()
        local Root = z.object({ title = z.string():transform(string.upper), tree = z.lazy(function() return Tree end) })
        local ok, out = Root:safeParse({ title = "t", tree = { value = 1, children = { { value = 2 } } } })
        assertTrue(ok)
        assertEq(out.title, "T")
        assertEq(out.tree.children[1].value, 2)
        local cyc = { value = 1 }
        cyc.children = { cyc }
        local bad, _, err = Root:safeParse({ title = "t", tree = cyc })
        assertFalse(bad)
        assertEq(err.issues[1].code, "too_deep")
        assertEq(err.issues[1].path[1], "tree")
    end)

    test("lazy: bad functions and bad targets fail loudly", function()
        assertThrows(function() z.lazy() end)
        assertThrows(function() z.lazy("x") end)
        assertThrows(function() z.lazy(function() return nil end):is(1) end)
        assertThrows(function() z.lazy(function() return {} end):is(1) end)
        local ok, err = pcall(function()
            return z.lazy(function() return z.string():transform(string.upper) end):is("a")
        end)
        assertFalse(ok)
        assertTrue(tostring(err):find("pure", 1, true) ~= nil)
        local ok2, err2 = pcall(function() return z.lazy(function() return 5 end):safeParse(1) end)
        assertFalse(ok2)
        assertTrue(tostring(err2):find("schema", 1, true) ~= nil)
    end)

    test("lazy: a lazy node can carry transforms and limits of its own", function()
        local L = z.lazy(function() return z.string() end):transform(string.upper)
        assertFalse(L.pure)
        local ok, out = L:safeParse("abc")
        assertTrue(ok)
        assertEq(out, "ABC")
        assertFalse(L:is(1))
        local Lim = z.lazy(function() return z.array(z.integer()) end):limits({ maxKeys = 2 })
        assertTrue(Lim:is({ 1, 2 }))
        assertFalse(Lim:is({ 1, 2, 3 }))
    end)

    test("lazy: safeParse returns the input itself for a recursive schema", function()
        local Tree = makeTree()
        local good = chain(10)
        local ok, out = Tree:safeParse(good)
        assertTrue(ok)
        assertEq(out, good)
    end)
end
