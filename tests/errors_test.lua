return function(env)
    local test, z = env.test, env.z
    local assertEq, assertTrue, assertFalse = env.assertEq, env.assertTrue, env.assertFalse
    local assertDeepEq = env.assertDeepEq

    local S = z.object({
        name = z.string():min(3),
        tags = z.array(z.string()),
        role = z.enum({ "admin", "user" }),
    })
    local bad = { name = "a", tags = { "x", 2 }, role = "root" }

    test("safeParse success returns exactly true, value", function()
        local input = { name = "abc", tags = {}, role = "admin" }
        assertEq(select("#", S:safeParse(input)), 2)
        local ok, value, err = S:safeParse(input)
        assertTrue(ok); assertEq(rawequal(value, input), true); assertEq(err, nil)
    end)

    test("safeParse failure returns false, nil, error object", function()
        local ok, value, err = S:safeParse(bad)
        assertFalse(ok); assertEq(value, nil)
        assertTrue(z.isError(err))
        assertEq(#err.issues, 3)
    end)

    test("issues have path, code, expected, got", function()
        local _, _, err = S:safeParse(bad)
        assertDeepEq(err.issues, {
            { path = { "name" }, code = "too_small", expected = 3, got = 1, type = "string" },
            { path = { "role" }, code = "invalid_enum", expected = { "admin", "user" }, got = "root" },
            { path = { "tags", 2 }, code = "invalid_type", expected = "string", got = "number" },
        })
    end)

    test("parse returns the value on success", function()
        local input = { name = "abc", tags = {}, role = "admin" }
        assertEq(S:parse(input), input)
    end)

    test("parse raises the error object", function()
        local ok, err = pcall(function() return S:parse(bad) end)
        assertFalse(ok)
        assertTrue(z.isError(err))
        assertEq(#err.issues, 3)
    end)

    test("error object has __tostring with the formatted issues", function()
        local _, _, err = S:safeParse(bad)
        local s = tostring(err)
        assertTrue(s:find("ZigoError: 3 issue(s)", 1, true) ~= nil)
        assertTrue(s:find("name: Expected length of at least 3, got 1", 1, true) ~= nil)
    end)

    test("format produces one line per issue", function()
        local _, _, err = S:safeParse(bad)
        assertEq(err:format(), table.concat({
            "name: Expected length of at least 3, got 1",
            'role: Expected one of: "admin", "user", got "root"',
            "tags[2]: Expected string, got number",
        }, "\n"))
    end)

    test("format uses <root> for the root path", function()
        local _, _, err = z.string():safeParse(1)
        assertEq(err:format(), "<root>: Expected string, got number")
    end)

    test("flatten groups messages by path", function()
        local _, _, err = S:safeParse(bad)
        assertDeepEq(err:flatten(), {
            formErrors = {},
            fieldErrors = {
                name = { "Expected length of at least 3, got 1" },
                role = { 'Expected one of: "admin", "user", got "root"' },
                ["tags[2]"] = { "Expected string, got number" },
            },
        })
        local _, _, rootErr = z.string():safeParse(1)
        assertDeepEq(rootErr:flatten(), { formErrors = { "Expected string, got number" }, fieldErrors = {} })
    end)

    test("messages are not stored on issues during validation", function()
        local _, _, err = S:safeParse(bad)
        for i = 1, #err.issues do assertEq(err.issues[i].message, nil) end
    end)

    test("setMessages replaces a message with a function or a template", function()
        local original = z.messages.invalid_type
        local _, _, err = z.string():safeParse(1)
        local ok, problem = pcall(function()
            z.setMessages({ invalid_type = function(i) return "attendu " .. i.expected end })
            assertEq(err:format(), "<root>: attendu string")
            z.setMessages({ invalid_type = "want {expected} not {got}" })
            assertEq(err:format(), "<root>: want string not number")
        end)
        z.setMessages({ invalid_type = original })
        assertTrue(ok, problem)
        assertEq(err:format(), "<root>: Expected string, got number")
    end)

    test("format accepts a per-call message table", function()
        local _, _, err = z.string():safeParse(1)
        assertEq(err:format({ invalid_type = "bad" }), "<root>: bad")
        assertEq(err:format(), "<root>: Expected string, got number")
    end)

    test("unknown code falls back to the code itself", function()
        local _, _, err = z.string():safeParse(1)
        err.issues = { { path = {}, code = "mystery" } }
        assertEq(err:format(), "<root>: mystery")
    end)

    test("literal and exact-length messages", function()
        local _, _, e1 = z.literal("a"):safeParse("b")
        assertEq(e1:format(), '<root>: Expected "a", got "b"')
        local _, _, e2 = z.string():len(5):safeParse("a")
        assertEq(e2:format(), "<root>: Expected length of exactly 5, got 1")
        local _, _, e3 = z.number():min(5):safeParse(1)
        assertEq(e3:format(), "<root>: Expected value of at least 5, got 1")
    end)

    test("issue path is a copy: later validation does not mutate earlier errors", function()
        local _, _, e1 = S:safeParse(bad)
        local snapshot = e1:format()
        S:safeParse({ name = "abc", tags = { 1, 2, 3, 4 }, role = "x" })
        assertEq(e1:format(), snapshot)
    end)
end
