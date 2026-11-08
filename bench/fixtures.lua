local M = {}

local type = type

local function inCodegenMode(z, codegen, build)
    local previous = z.config().codegen
    z.config({ codegen = codegen })
    local ok, schema = pcall(build, z)
    local test
    if ok then ok, test = pcall(function() return schema._test end) end
    z.config({ codegen = previous })
    if not ok then error(schema, 0) end
    return test, schema
end

function M.compile(z, codegen, build)
    return inCodegenMode(z, codegen, build)
end

local function s1()
    local inputs, invalid = {}, { "", "a", "ab", 3, true, false, {} }
    for i = 1, 64 do
        inputs[i] = ("x"):rep(3 + (i * 7) % 29)
    end
    return {
        name = "S1 string():min(3)",
        inputs = inputs,
        invalid = invalid,
        build = function(z) return z.string():min(3) end,
        hand = function(v)
            return type(v) == "string" and #v >= 3
        end,
    }
end

local roles = { "admin", "user", "guest" }

local function s2Input(i)
    local tags = {}
    for t = 1, i % 11 do tags[t] = ("tag" .. (i * t) % 97):sub(1, 16) end
    local v = {
        id = 1 + (i * 7919) % 999999,
        name = ("n"):rep(3 + i % 30),
        role = roles[i % 3 + 1],
        active = i % 2 == 0,
        tags = tags,
        address = { city = ("c"):rep(1 + i % 12), zip = ("%05d"):format((i * 331) % 100000) },
    }
    if i % 3 ~= 0 then v.age = i % 151 end
    if i % 5 == 0 then v.extra = i end
    return v
end

local function s2()
    local inputs = {}
    for i = 1, 64 do inputs[i] = s2Input(i) end
    local invalid = {
        { id = 0, name = "abc", role = "admin", active = true, tags = {}, address = { city = "c", zip = "12345" } },
        { id = 1, name = "ab", role = "admin", active = true, tags = {}, address = { city = "c", zip = "12345" } },
        { id = 1, name = "abc", role = "root", active = true, tags = {}, address = { city = "c", zip = "12345" } },
        { id = 1, name = "abc", role = "admin", active = 1, tags = {}, address = { city = "c", zip = "12345" } },
        { id = 1, name = "abc", role = "admin", active = true, tags = { 1 }, address = { city = "c", zip = "12345" } },
        { id = 1, name = "abc", role = "admin", active = true, tags = {}, address = { city = "", zip = "12345" } },
        { id = 1, name = "abc", role = "admin", active = true, tags = {}, address = { city = "c", zip = "1234" } },
        { id = 1, name = "abc", role = "admin", active = true, tags = {}, age = 151, address = { city = "c", zip = "12345" } },
        { id = 1, name = "abc", role = "admin", active = true, tags = {} },
        { id = 1, name = "abc", role = "admin", active = true, tags = { "a", extra = "b" }, address = { city = "c", zip = "12345" } },
        { id = 1, name = "abc", role = "admin", active = true, tags = { "a", nil, "c" }, address = { city = "c", zip = "12345" } },
        { id = 1, name = "abc", role = "admin", active = true, tags = { "a", [4] = "d" }, address = { city = "c", zip = "12345" } },
        "x",
    }
    return {
        name = "S2 reference schema (7 fields, nested object, array, enum, optional)",
        inputs = inputs,
        invalid = invalid,
        build = function(z)
            return z.object({
                id = z.integer():between(1, 1000000),
                name = z.string():min(3):max(32),
                role = z.enum({ "admin", "user", "guest" }),
                active = z.boolean(),
                age = z.integer():between(0, 150):optional(),
                tags = z.array(z.string():max(16)):max(10),
                address = z.object({ city = z.string():min(1), zip = z.string():len(5) }),
            })
        end,
        hand = function(v)
            if type(v) ~= "table" then return false end
            local id = v.id
            if type(id) ~= "number" or id % 1 ~= 0 or id < 1 or id > 1000000 then return false end
            local name = v.name
            if type(name) ~= "string" or #name < 3 or #name > 32 then return false end
            local role = v.role
            if role ~= "admin" and role ~= "user" and role ~= "guest" then return false end
            if type(v.active) ~= "boolean" then return false end
            local age = v.age
            if age ~= nil and (type(age) ~= "number" or age % 1 ~= 0 or age < 0 or age > 150) then
                return false
            end
            local tags = v.tags
            if type(tags) ~= "table" then return false end
            local n = #tags
            if n > 10 then return false end
            local count = 0
            for _ in next, tags do
                count = count + 1
                if count > n then return false end
            end
            if count ~= n then return false end
            for i = 1, n do
                local tag = tags[i]
                if type(tag) ~= "string" or #tag > 16 then return false end
            end
            local address = v.address
            if type(address) ~= "table" then return false end
            local city = address.city
            if type(city) ~= "string" or #city < 1 then return false end
            local zip = address.zip
            if type(zip) ~= "string" or #zip ~= 5 then return false end
            return true
        end,
    }
end

local DEPTH = 8

local function nested(i, bad)
    local node = { n = i, label = ("l"):rep(1 + i % 5) }
    if bad then node.label = "" end
    for level = DEPTH - 1, 1, -1 do
        node = { n = i + level, child = node }
    end
    return node
end

local function s3()
    local inputs = {}
    for i = 1, 64 do inputs[i] = nested(i) end
    return {
        name = "S3 nesting depth 8",
        inputs = inputs,
        invalid = { nested(1, true), { n = 1, child = { n = 2 } }, { n = 1, child = 5 }, 7 },
        build = function(z)
            local schema = z.object({ n = z.integer(), label = z.string():min(1) })
            for _ = DEPTH - 1, 1, -1 do
                schema = z.object({ n = z.integer(), child = schema })
            end
            return schema
        end,
        hand = function(v)
            for _ = 1, DEPTH - 1 do
                if type(v) ~= "table" then return false end
                local n = v.n
                if type(n) ~= "number" or n % 1 ~= 0 then return false end
                v = v.child
            end
            if type(v) ~= "table" then return false end
            local n, label = v.n, v.label
            if type(n) ~= "number" or n % 1 ~= 0 then return false end
            return type(label) == "string" and #label >= 1
        end,
    }
end

local ROWS = 1000

local function rows(seed)
    local list = {}
    for i = 1, ROWS do
        list[i] = { id = seed * ROWS + i, name = ("u"):rep(1 + (i + seed) % 20), active = (i + seed) % 3 == 0 }
    end
    return list
end

local function s4()
    local inputs = {}
    for i = 1, 8 do inputs[i] = rows(i) end
    local badRow = rows(9)
    badRow[ROWS] = { id = 1, name = "", active = true }
    local hole = rows(10)
    hole[500] = nil
    local strayKey = rows(11)
    strayKey.extra = true
    local strayIndex = rows(12)
    strayIndex[ROWS + 5] = strayIndex[1]
    return {
        name = "S4 array of 1000 objects",
        inputs = inputs,
        invalid = { badRow, hole, strayKey, strayIndex, {}, "x", { 1 } },
        build = function(z)
            return z.array(z.object({
                id = z.integer():min(0),
                name = z.string():min(1),
                active = z.boolean(),
            }))
        end,
        hand = function(v)
            if type(v) ~= "table" then return false end
            local n = #v
            local count = 0
            for _ in next, v do
                count = count + 1
                if count > n then return false end
            end
            if count ~= n then return false end
            for i = 1, n do
                local row = v[i]
                if type(row) ~= "table" then return false end
                local id = row.id
                if type(id) ~= "number" or id % 1 ~= 0 or id < 0 then return false end
                local name = row.name
                if type(name) ~= "string" or #name < 1 then return false end
                if type(row.active) ~= "boolean" then return false end
            end
            return true
        end,
    }
end

M.s1, M.s2, M.s3, M.s4 = s1, s2, s3, s4

M.all = { s1, s2, s3, s4 }

return M
