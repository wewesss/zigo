return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertThrows, assertDeepEq = env.assertThrows, env.assertDeepEq

    local matchigoPath = os.getenv("MATCHIGO_PATH")
    if matchigoPath == nil or matchigoPath == "" then
        print("matchigo_test: skipped (MATCHIGO_PATH not set)")
        return
    end

    local savedPath = package.path
    package.path = matchigoPath .. "/?.lua;" .. matchigoPath .. "/?/init.lua;" .. package.path
    local loaded, m = pcall(require, "matchigo")
    package.path = savedPath
    if not loaded then
        print("matchigo_test: skipped (matchigo not loadable from '" .. matchigoPath .. "')")
        return
    end

    local P = m.P

    local User = z.object({ name = z.string():min(1), age = z.integer():min(0) })
    local Ping = z.object({ kind = z.literal("ping") })
    local Num = z.number()

    test("matchigo: isMatching accepts a valid value", function()
        assertTrue(m.isMatching(User, { name = "ann", age = 3 }))
    end)

    test("matchigo: isMatching rejects an invalid value", function()
        assertFalse(m.isMatching(User, { name = "", age = 3 }))
        assertFalse(m.isMatching(User, "nope"))
        assertFalse(m.isMatching(User, nil))
    end)

    test("matchigo: isMatching with a pipeline node", function()
        local trimmed = z.string():transform(function(s) return s:upper() end)
        assertTrue(m.isMatching(trimmed, "a"))
        assertFalse(m.isMatching(trimmed, 1))
    end)

    test("matchigo: a zigo node nested in a shape pattern", function()
        local pat = { user = User, tag = "x" }
        assertTrue(m.isMatching(pat, { user = { name = "a", age = 1 }, tag = "x" }))
        assertFalse(m.isMatching(pat, { user = { name = "a", age = -1 }, tag = "x" }))
        assertFalse(m.isMatching(pat, { user = { name = "a", age = 1 }, tag = "y" }))
    end)

    test("matchigo: a zigo node inside P.intersection and P.anyOf", function()
        local both = P.intersection(Num, P.gte(10))
        assertTrue(m.isMatching(both, 11))
        assertFalse(m.isMatching(both, 9))
        local either = P.anyOf(z.string(), z.boolean())
        assertTrue(m.isMatching(either, "s"))
        assertTrue(m.isMatching(either, false))
        assertFalse(m.isMatching(either, 1))
    end)

    test("matchigo: compile dispatches on zigo nodes", function()
        local f = m.compile({
            { with = Ping, handler = "ping" },
            { with = User, handler = function(v) return v.name end },
            { otherwise = "other" },
        })
        assertEq(f({ kind = "ping" }), "ping")
        assertEq(f({ name = "bo", age = 2 }), "bo")
        assertEq(f(12), "other")
    end)

    test("matchigo: compile without a fallback raises on no match", function()
        local f = m.compile({ { with = Ping, handler = 1 } })
        assertEq(f({ kind = "ping" }), 1)
        assertThrows(function() return f({ kind = "pong" }) end)
    end)

    test("matchigo: matcher():with chain dispatches and falls back", function()
        local run = m.matcher()
            :with(Ping, function() return "ping" end)
            :with(User, function(v) return "user:" .. v.name end)
            :otherwise("none")
        assertEq(run({ kind = "ping" }), "ping")
        assertEq(run({ name = "cy", age = 9 }), "user:cy")
        assertEq(run("zz"), "none")
    end)

    test("matchigo: matcher():with honours a guard", function()
        local run = m.matcher()
            :with(User, function(v) return v.age >= 18 end, function() return "adult" end)
            :with(User, function() return "minor" end)
            :otherwise("none")
        assertEq(run({ name = "a", age = 30 }), "adult")
        assertEq(run({ name = "a", age = 3 }), "minor")
        assertEq(run(1), "none")
    end)

    test("matchigo: matcher():run reuses the compiled dispatcher", function()
        local mt = m.matcher():with(Num, function(v) return v + 1 end):with(z.string(), "str")
        assertEq(mt:run(1), 2)
        assertEq(mt:run("a"), "str")
        assertThrows(function() return mt:run(true) end)
    end)

    test("matchigo: literal fast-path mixed with a zigo node", function()
        local f = m.compile({
            { with = "a", handler = 1 },
            { with = 2, handler = 2 },
            { with = Ping, handler = 3 },
            { with = z.integer():min(100), handler = 4 },
            { otherwise = 0 },
        })
        assertEq(f("a"), 1)
        assertEq(f(2), 2)
        assertEq(f({ kind = "ping" }), 3)
        assertEq(f(150), 4)
        assertEq(f(50), 0)
    end)

    test("matchigo: a node rule placed before a literal rule still wins first", function()
        local f = m.compile({
            { with = z.integer(), handler = "int" },
            { with = 5, handler = "five" },
        })
        assertEq(f(5), "five")
        assertEq(f(6), "int")
    end)

    test("matchigo: P.select with a zigo node", function()
        local f = m.compile({
            { with = P.select(User), handler = function(sel) return sel.name end },
            { otherwise = "none" },
        })
        assertEq(f({ name = "di", age = 4 }), "di")
        assertEq(f({ name = "", age = 4 }), "none")
    end)

    test("matchigo: P.select with a label and a zigo node", function()
        local f = m.compile({
            { with = { who = P.select("who", User), n = P.select("n", z.integer()) },
              handler = function(sel) return sel.who.name .. sel.n end },
            { otherwise = "none" },
        })
        assertEq(f({ who = { name = "ed", age = 1 }, n = 7 }), "ed7")
        assertEq(f({ who = { name = "ed", age = 1 }, n = 7.5 }), "none")
    end)

    test("matchigo: P.select nested in a shape next to a zigo node", function()
        local f = m.compile({
            { with = { kind = "ping", id = P.select(z.integer():min(1)) },
              handler = function(id) return id end },
            { otherwise = -1 },
        })
        assertEq(f({ kind = "ping", id = 9 }), 9)
        assertEq(f({ kind = "ping", id = 0 }), -1)
    end)

    test("matchigo: results are the same with codegen on and off", function()
        local previous = z.config().codegen
        local verdicts = {}
        for _, flag in ipairs({ true, false }) do
            z.config({ codegen = flag })
            local node = z.object({ a = z.integer():min(1) })
            verdicts[#verdicts + 1] = { m.isMatching(node, { a = 2 }), m.isMatching(node, { a = 0 }) }
        end
        z.config({ codegen = previous })
        assertDeepEq(verdicts[1], verdicts[2])
    end)
end
