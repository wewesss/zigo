return function(z, b)
    local fixtures = require("bench.fixtures")

    for _, make in ipairs(fixtures.all) do
        local f = make()
        local codegen = fixtures.compile(z, true, f.build)
        local closures = fixtures.compile(z, false, f.build)
        assert(z._isGenerated(codegen), f.name .. ": codegen variant was not generated")
        assert(not z._isGenerated(closures), f.name .. ": closures variant is generated")

        for _, set in ipairs({ f.inputs, f.invalid }) do
            for i = 1, #set do
                local expected = f.hand(set[i])
                assert(codegen(set[i]) == expected and closures(set[i]) == expected,
                    f.name .. ": variants disagree on input " .. i)
            end
        end

        local key = f.name:match("^(S%d)"):lower()
        b.scenario(f.name .. " - valid inputs", {
            { name = "hand-written if-chain", fn = f.hand, key = key .. ".hand" },
            { name = "zigo codegen",          fn = codegen, key = key .. ".codegen" },
            { name = "zigo closures",         fn = closures, key = key .. ".closures" },
        }, { inputs = f.inputs })
    end
end
