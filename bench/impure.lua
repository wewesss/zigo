return function(z, b)
    local type, upper = type, string.upper

    local roles = { "admin", "user", "guest" }
    local roleSet = { admin = true, user = true, guest = true }

    local function input(i)
        local v = {
            id = 1 + (i * 7919) % 999999,
            name = ("n" .. i % 50):sub(1, 12),
        }
        if i % 3 ~= 0 then v.role = roles[i % 3 + 1] end
        if i % 4 ~= 0 then v.active = i % 2 == 0 end
        if i % 5 ~= 0 then
            local tags = {}
            for t = 1, i % 6 do tags[t] = "tag" .. (i * t) % 97 end
            v.tags = tags
        end
        if i % 2 == 0 then v.extra = i end
        if i % 7 == 0 then v.junk = { i } end
        return v
    end

    local inputs = {}
    for i = 1, 64 do inputs[i] = input(i) end

    local schema = z.object({
        id = z.integer():min(1),
        name = z.string():min(1):transform(upper),
        role = z.enum(roles):default("user"),
        active = z.boolean():default(true),
        tags = z.array(z.string()):default(function() return {} end),
    }):strip()

    local function hand(v)
        if type(v) ~= "table" then return nil end
        local id = v.id
        if type(id) ~= "number" or id % 1 ~= 0 or id < 1 then return nil end
        local name = v.name
        if type(name) ~= "string" or #name < 1 then return nil end
        local role = v.role
        if role == nil then role = "user" elseif not roleSet[role] then return nil end
        local active = v.active
        if active == nil then active = true elseif type(active) ~= "boolean" then return nil end
        local tags = v.tags
        local out
        if tags == nil then
            out = {}
        else
            if type(tags) ~= "table" then return nil end
            local n = #tags
            local count = 0
            for _ in next, tags do
                count = count + 1
                if count > n then return nil end
            end
            if count ~= n then return nil end
            out = {}
            for i = 1, n do
                local tag = tags[i]
                if type(tag) ~= "string" then return nil end
                out[i] = tag
            end
        end
        return { id = id, name = upper(name), role = role, active = active, tags = out }
    end

    local function same(a, c)
        if type(a) ~= "table" or type(c) ~= "table" then return a == c end
        for k, x in next, a do
            if not same(x, c[k]) then return false end
        end
        for k in next, c do
            if a[k] == nil then return false end
        end
        return true
    end

    local function zigoParse(v)
        local ok, out = schema:safeParse(v)
        if ok then return out end
        return nil
    end

    for i = 1, #inputs do
        assert(same(zigoParse(inputs[i]), hand(inputs[i])), "S8: variants disagree on input " .. i)
    end
    assert(not schema.pure, "S8: the schema must be impure")

    b.scenario("S8 impure schema (default, transform, strip) - valid inputs", {
        { name = "hand-written copy", fn = hand, key = "s8.hand" },
        { name = "zigo safeParse (_parse)", fn = zigoParse, key = "s8.parse" },
        { name = "zigo is (_parse, no result kept)", fn = function(v) return schema:is(v) end, key = "s8.is" },
    }, { inputs = inputs })
end
