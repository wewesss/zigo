return function(env)
    local test     = env.test
    local assertEq = env.assertEq
    local z        = env.z

    test("require zigo returns a table", function()
        assertEq(type(z), "table")
    end)

    test("_VERSION is a string", function()
        assertEq(type(z._VERSION), "string")
    end)
end
