return function(z, b)
    local fixtures = require("bench.fixtures")

    for _, make in ipairs(fixtures.all) do
        local f = make()
        if f.register then
            f.register(z, b)
        else
            local codegen, schema = fixtures.compile(z, true, f.build)
            local is, safeParse = schema.is, schema.safeParse
            local closures = fixtures.compile(z, false, f.build)
            assert(z._isGenerated(codegen), f.name .. ": codegen variant was not generated")
            assert(not z._isGenerated(closures), f.name .. ": closures variant is generated")

            local sets = f.sets or { { label = "valid inputs", inputs = f.inputs } }
            local checked = { f.inputs, f.invalid }
            for _, set in ipairs(sets) do checked[#checked + 1] = set.inputs end
            for _, list in ipairs(checked) do
                for i = 1, #list do
                    local expected = f.hand(list[i])
                    assert(codegen(list[i]) == expected and closures(list[i]) == expected,
                        f.name .. ": variants disagree on input " .. i)
                end
            end

            local key = f.name:match("^(S%d+)"):lower()
            for _, set in ipairs(sets) do
                local setKey = set.key and (key .. "." .. set.key) or key
                local variants = {
                    { name = "hand-written if-chain", fn = f.hand, key = setKey .. ".hand" },
                    { name = "zigo codegen",          fn = codegen, key = setKey .. ".codegen" },
                    { name = "zigo closures",         fn = closures, key = setKey .. ".closures" },
                    { name = "zigo :is (public)",     fn = function(v) return is(schema, v) end, key = setKey .. ".is" },
                    { name = "zigo :safeParse (public)", fn = function(v) return (safeParse(schema, v)) end, key = setKey .. ".safeparse" },
                }
                if f.extras then
                    for _, extra in ipairs(f.extras(z, setKey)) do variants[#variants + 1] = extra end
                end
                b.scenario(f.name .. " - " .. set.label, variants, { inputs = set.inputs })
            end
        end
    end
end
