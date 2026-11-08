return function(env)
    local test, z = env.test, env.z
    local assertTrue, assertEq = env.assertTrue, env.assertEq

    local CALLS = 20000
    local BUDGET = 0.5
    local WARMUP = 5000
    local ROUNDS = 5

    local function round(fn, v)
        for _ = 1, WARMUP do fn(v) end
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, CALLS do fn(v) end
        local after = collectgarbage("count")
        collectgarbage("restart")
        return (after - before) * 1024 / CALLS
    end

    local function bytesPerCall(fn, v)
        local best = math.huge
        for _ = 1, ROUNDS do
            local per = round(fn, v)
            if per < best then best = per end
            if best < BUDGET then break end
        end
        return best
    end

    local Schema = z.object({
        id = z.integer():between(1, 1000000),
        name = z.string():min(3):max(32),
        role = z.enum({ "admin", "user", "guest" }),
        active = z.boolean(),
        age = z.integer():between(0, 150):optional(),
        score = z.number():min(0),
        tags = z.array(z.string():max(16)):max(10),
        address = z.object({ city = z.string():min(1), zip = z.string():len(5) }),
        kind = z.literal("user"),
    }):strict()

    local valid = {
        id = 7, name = "alice", role = "admin", active = true, score = 1.5,
        tags = { "a", "b", "c" }, address = { city = "Paris", zip = "75001" }, kind = "user",
    }

    test("zero allocation: _test on the valid path of a pure schema", function()
        assertEq(Schema.pure, true)
        local t = Schema._test
        local per = bytesPerCall(t, valid)
        assertTrue(per < BUDGET)
    end)

    test("zero allocation: :is() on the valid path", function()
        local per = bytesPerCall(function(v) return Schema:is(v) end, valid)
        assertTrue(per < BUDGET)
    end)

    test("zero allocation: :safeParse() on the valid path", function()
        local per = bytesPerCall(function(v) return Schema:safeParse(v) end, valid)
        assertTrue(per < BUDGET)
    end)

    test("zero allocation: :parse() on the valid path", function()
        local per = bytesPerCall(function(v) return Schema:parse(v) end, valid)
        assertTrue(per < BUDGET)
    end)

    test("zero allocation: primitive and optional schemas", function()
        local P = z.string():min(3):optional()
        assertTrue(bytesPerCall(function(v) return P:is(v) end, "abcd") < BUDGET)
        assertTrue(bytesPerCall(function(v) return P:is(v) end, nil) < BUDGET)
    end)

    test("zero allocation: unions, tuples and records on the valid path", function()
        local Container = z.object({
            u = z.union(z.string(), z.integer()),
            d = z.discriminatedUnion("kind",
                z.object({ kind = z.literal("a"), n = z.integer() }),
                z.object({ kind = z.literal("b"), s = z.string() })),
            t = z.tuple({ z.string(), z.integer() }):rest(z.boolean()),
            r = z.record(z.string(), z.integer()),
        }):strict()
        local value = {
            u = 4, d = { kind = "b", s = "x" }, t = { "a", 1, true, false }, r = { a = 1, b = 2, c = 3 },
        }
        assertEq(Container.pure, true)
        assertTrue(bytesPerCall(Container._test, value) < BUDGET)
        assertTrue(bytesPerCall(function(v) return Container:is(v) end, value) < BUDGET)
        assertTrue(bytesPerCall(function(v) return Container:safeParse(v) end, value) < BUDGET)
    end)

    test("zero allocation: a recursive lazy schema on the valid path", function()
        local Tree
        Tree = z.object({
            value = z.integer(),
            children = z.array(z.lazy(function() return Tree end)):optional(),
        })
        local value = { value = 1, children = { { value = 2 }, { value = 3, children = { { value = 4 } } } } }
        assertTrue(Tree:is(value))
        assertTrue(bytesPerCall(Tree._test, value) < BUDGET)
        assertTrue(bytesPerCall(function(v) return Tree:safeParse(v) end, value) < BUDGET)
    end)

    test("abortEarly: the invalid path allocates at most one error table", function()
        local Rows = z.array(z.object({ id = z.integer(), name = z.string() }))
        local Abort = Rows:limits({ abortEarly = true })
        local oneBad = { { id = "x", name = 1 } }
        local manyBad = {}
        for i = 1, 1000 do manyBad[i] = { id = "x", name = 1 } end
        local _, _, err = Abort:safeParse(manyBad)
        assertEq(#err.issues, 1)
        local _, _, capped = Rows:safeParse(manyBad)
        assertEq(#capped.issues, 100)
        local one = bytesPerCall(function(v) return Abort:safeParse(v) end, oneBad)
        local many = bytesPerCall(function(v) return Abort:safeParse(v) end, manyBad)
        local unbounded = bytesPerCall(function(v) return Rows:safeParse(v) end, manyBad)
        assertTrue(many <= one * 1.05)
        assertTrue(unbounded > many * 10)
    end)

    test("the invalid path does allocate (sanity check of the probe)", function()
        local bad = { id = "x" }
        local per = bytesPerCall(function(v) return Schema:safeParse(v) end, bad)
        assertTrue(per > BUDGET)
    end)
end
