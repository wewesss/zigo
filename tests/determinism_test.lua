return function(env)
    local test, z = env.test, env.z
    local assertEq, assertDeepEq = env.assertEq, env.assertDeepEq

    local function schema(order)
        local shape = {}
        for i = 1, #order do shape[order[i]] = order[i] == "nested"
            and z.object({ b = z.boolean(), a = z.number() }):strict()
            or order[i] == "tags" and z.array(z.string():max(2))
            or order[i] == "age" and z.integer():between(0, 150)
            or z.string():min(3)
        end
        return z.object(shape):strict()
    end

    local function input(extraOrder)
        local v = {
            name = "a", age = 200, tags = { "abc", "d", "xyz" },
            nested = { a = "x", b = 1, zz = 1, aa = 2, [5] = 1, [2] = 2, [true] = 3 },
        }
        for i = 1, #extraOrder do v[extraOrder[i]] = i end
        v[10] = 1
        return v
    end

    local expected = table.concat({
        "age: Expected value of at most 150, got 200",
        "name: Expected length of at least 3, got 1",
        "nested.a: Expected number, got string",
        "nested.b: Expected boolean, got number",
        "nested[2]: Unrecognized key",
        "nested[5]: Unrecognized key",
        "nested.aa: Unrecognized key",
        "nested.zz: Unrecognized key",
        "nested[true]: Unrecognized key",
        "tags[1]: Expected length of at most 2, got 3",
        "tags[3]: Expected length of at most 2, got 3",
        "[10]: Unrecognized key",
        "extra0: Unrecognized key",
        "extra1: Unrecognized key",
        "extra2: Unrecognized key",
    }, "\n")

    test("the same input 100 times gives identical issues and order", function()
        local S = schema({ "name", "age", "tags", "nested" })
        local first
        for run = 1, 100 do
            local _, _, err = S:safeParse(input({ "extra0", "extra1", "extra2" }))
            if run == 1 then
                first = err.issues
                assertEq(err:format(), expected)
            else
                assertDeepEq(err.issues, first)
            end
        end
    end)

    test("insertion order of data keys does not change issue order", function()
        local S = schema({ "name", "age", "tags", "nested" })
        local orders = {
            { "extra0", "extra1", "extra2" },
            { "extra2", "extra1", "extra0" },
            { "extra1", "extra2", "extra0" },
        }
        for _, order in ipairs(orders) do
            local _, _, err = S:safeParse(input(order))
            assertEq(err:format():gsub("extra%d: Unrecognized key", "X"), (expected:gsub("extra%d: Unrecognized key", "X")))
            local names = {}
            for i = 1, #err.issues do
                local p = err.issues[i].path
                if type(p[1]) == "string" and p[1]:find("^extra") then names[#names + 1] = p[1] end
            end
            assertDeepEq(names, { "extra0", "extra1", "extra2" })
        end
    end)

    test("insertion order of shape keys does not change issue order", function()
        local a = schema({ "name", "age", "tags", "nested" })
        local b = schema({ "nested", "tags", "age", "name" })
        local c = schema({ "tags", "name", "nested", "age" })
        local _, _, ea = a:safeParse(input({ "extra0" }))
        local _, _, eb = b:safeParse(input({ "extra0" }))
        local _, _, ec = c:safeParse(input({ "extra0" }))
        assertDeepEq(eb.issues, ea.issues)
        assertDeepEq(ec.issues, ea.issues)
    end)

    test("many unknown keys are reported in sorted order", function()
        local S = z.object({}):strict()
        local v = {}
        for i = 1, 60 do v["k" .. string.format("%03d", (i * 37) % 61)] = i end
        for i = 1, 5 do v[100 - i] = i end
        local _, _, err = S:safeParse(v)
        local last
        for i = 1, #err.issues do
            local key = err.issues[i].path[1]
            if last ~= nil then
                if type(last) == type(key) then assertEq(last < key, true) else assertEq(type(last), "number") end
            end
            last = key
        end
        assertEq(#err.issues, 65)
    end)

    test("errors do not depend on prior validations", function()
        local S = schema({ "name", "age", "tags", "nested" })
        local _, _, e1 = S:safeParse(input({ "extra0" }))
        S:safeParse({})
        S:safeParse({ name = "abc", age = 1, tags = {}, nested = { a = 1, b = true } })
        local _, _, e2 = S:safeParse(input({ "extra0" }))
        assertDeepEq(e2.issues, e1.issues)
    end)
end
