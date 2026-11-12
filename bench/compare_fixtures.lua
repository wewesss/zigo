local fixtures = require("bench.fixtures")

local M = {}

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function derive(list, mutate)
    local out = {}
    for i = 1, #list do out[i] = mutate(list[i], i) end
    return out
end

local function with(key, value)
    return function(input)
        local out = copy(input)
        out[key] = value
        return out
    end
end

function M.all()
    local s1, s2, s3, s4, s5 = fixtures.s1(), fixtures.s2(), fixtures.s3(), fixtures.s4(), fixtures.s5()

    return {
        {
            id = "s1",
            fixture = s1,
            early = derive(s1.inputs, function(_, i) return ("x"):rep(i % 3) end),
            earlyLabel = "string shorter than the minimum",
        },
        {
            id = "s2",
            fixture = s2,
            early = derive(s2.inputs, with("id", 0)),
            earlyLabel = "id out of range",
        },
        {
            id = "s3",
            fixture = s3,
            early = derive(s3.inputs, with("n", 1.5)),
            earlyLabel = "outermost n not an integer",
        },
        {
            id = "s4",
            fixture = s4,
            early = derive(s4.inputs, function(rows)
                local out = copy(rows)
                out[1] = { id = -1, name = "a", active = true }
                return out
            end),
            earlyLabel = "first row invalid",
        },
        {
            id = "s5",
            fixture = s5,
            early = derive(s5.inputs, with("kind", "zz")),
            earlyLabel = "unknown discriminator",
        },
    }
end

return M
