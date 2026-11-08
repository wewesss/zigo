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

local VARIANTS = 10

local function s5()
    local inputs = {}
    for i = 1, 64 do
        local k = i % VARIANTS + 1
        inputs[i] = { kind = "k" .. k, x = k + i % 7, label = ("l"):rep(1 + i % 16) }
        if i % 5 == 0 then inputs[i].extra = i end
    end
    return {
        name = "S5 discriminatedUnion, 10 variants",
        inputs = inputs,
        invalid = {
            { kind = "zz", x = 1, label = "a" },
            { x = 1, label = "a" },
            { kind = 1, x = 1, label = "a" },
            { kind = "k3", x = 2, label = "a" },
            { kind = "k10", x = 9, label = "a" },
            { kind = "k1", x = 2.5, label = "a" },
            { kind = "k1", x = "1", label = "a" },
            { kind = "k1", label = "a" },
            { kind = "k7", x = 7, label = "" },
            { kind = "k7", x = 7, label = ("l"):rep(17) },
            { kind = "k7", x = 7 },
            {},
            "k1",
            5,
        },
        build = function(z)
            local variants = {}
            for i = 1, VARIANTS do
                variants[i] = z.object({
                    kind = z.literal("k" .. i),
                    x = z.integer():min(i),
                    label = z.string():min(1):max(16),
                })
            end
            return z.discriminatedUnion("kind", (table.unpack or unpack)(variants))
        end,
        hand = function(v)
            if type(v) ~= "table" then return false end
            local k = v.kind
            local min
            if k == "k1" then min = 1 elseif k == "k2" then min = 2 elseif k == "k3" then min = 3
            elseif k == "k4" then min = 4 elseif k == "k5" then min = 5 elseif k == "k6" then min = 6
            elseif k == "k7" then min = 7 elseif k == "k8" then min = 8 elseif k == "k9" then min = 9
            elseif k == "k10" then min = 10 else return false end
            local x = v.x
            if type(x) ~= "number" or x % 1 ~= 0 or x < min then return false end
            local label = v.label
            if type(label) ~= "string" or #label < 1 or #label > 16 then return false end
            return true
        end,
    }
end

local function s6Valid(i)
    local role = roles[i % 3 + 1]
    return {
        f01 = 1 + i % 500, f02 = ("n"):rep(1 + i % 31), f03 = role, f04 = i % 2 == 0,
        f05 = (i % 97) + 0.5, f06 = i % 151, f07 = ("%05d"):format(i * 7 % 100000),
        f08 = ("x"):rep(3 + i % 9), f09 = i % 1000, f10 = i % 3 == 0,
        f11 = ("y"):rep(1 + i % 5), f12 = i * 1.25,
    }
end

local function s6With(i, key, value)
    local v = s6Valid(i)
    v[key] = value
    return v
end

local function parseOk(schema)
    return function(v) return (schema:safeParse(v)) end
end

local function s6()
    local valid, early, late = {}, {}, {}
    for i = 1, 64 do
        valid[i] = s6Valid(i)
        early[i] = s6With(i, "f01", i % 2 == 0 and "x" or 0)
        late[i] = s6With(i, "f12", i % 2 == 0 and "x" or 0 / 0)
    end
    local function build(z)
        return z.object({
            f01 = z.integer():min(1),
            f02 = z.string():min(1):max(32),
            f03 = z.enum({ "admin", "user", "guest" }),
            f04 = z.boolean(),
            f05 = z.number():min(0),
            f06 = z.integer():between(0, 150),
            f07 = z.string():len(5),
            f08 = z.string():min(3),
            f09 = z.integer():min(0),
            f10 = z.boolean(),
            f11 = z.string():min(1),
            f12 = z.number(),
        })
    end
    return {
        name = "S6 invalid early or late (12 fields)",
        inputs = valid,
        invalid = { 5, {}, s6With(1, "f07", "1234"), s6With(1, "f03", "root") },
        sets = {
            { label = "valid inputs", inputs = valid, key = "valid" },
            { label = "invalid at the first field", inputs = early, key = "early" },
            { label = "invalid at the last field", inputs = late, key = "late" },
        },
        build = build,
        extras = function(z, key)
            return {
                { name = "zigo safeParse", fn = parseOk(build(z)), key = key .. ".parse" },
                {
                    name = "zigo safeParse, abortEarly",
                    fn = parseOk(build(z):limits({ abortEarly = true })),
                    key = key .. ".abort",
                },
            }
        end,
        hand = function(v)
            if type(v) ~= "table" then return false end
            local x = v.f01
            if type(x) ~= "number" or x % 1 ~= 0 or x < 1 then return false end
            local s = v.f02
            if type(s) ~= "string" or #s < 1 or #s > 32 then return false end
            local r = v.f03
            if r ~= "admin" and r ~= "user" and r ~= "guest" then return false end
            if type(v.f04) ~= "boolean" then return false end
            x = v.f05
            if type(x) ~= "number" or x ~= x or x < 0 then return false end
            x = v.f06
            if type(x) ~= "number" or x % 1 ~= 0 or x < 0 or x > 150 then return false end
            s = v.f07
            if type(s) ~= "string" or #s ~= 5 then return false end
            s = v.f08
            if type(s) ~= "string" or #s < 3 then return false end
            x = v.f09
            if type(x) ~= "number" or x % 1 ~= 0 or x < 0 then return false end
            if type(v.f10) ~= "boolean" then return false end
            s = v.f11
            if type(s) ~= "string" or #s < 1 then return false end
            x = v.f12
            if type(x) ~= "number" or x ~= x then return false end
            return true
        end,
    }
end

local PAYLOAD_ROWS = 10000

local function s7Rows(count, bad, seed)
    local list = {}
    for i = 1, count do
        if bad then
            list[i] = { id = (i + seed) % 2 == 0 and 0 or "x", name = ("u"):rep(1 + (i + seed) % 9) }
        else
            list[i] = { id = i + seed, name = ("u"):rep(1 + (i + seed) % 9) }
        end
    end
    return list
end

local function s7()
    local payloads = {}
    for i = 1, 4 do payloads[i] = s7Rows(PAYLOAD_ROWS, true, i) end
    local function build(z)
        return z.array(z.object({ id = z.integer():min(1), name = z.string():min(1) }))
    end
    return {
        name = "S7 adversarial payload (10 000 potential errors)",
        inputs = payloads,
        invalid = {
            s7Rows(PAYLOAD_ROWS, false, 9),
            s7Rows(PAYLOAD_ROWS + 1, false, 9),
            "x",
            {},
        },
        sets = { { label = "invalid inputs", inputs = payloads, key = "invalid" } },
        build = build,
        extras = function(z, key)
            return {
                {
                    name = "zigo safeParse, maxErrors = inf (10 000 issues)",
                    fn = parseOk(build(z):limits({ maxErrors = math.huge })),
                    key = key .. ".unbounded",
                },
                { name = "zigo safeParse, default maxErrors (100)", fn = parseOk(build(z)), key = key .. ".capped" },
                {
                    name = "zigo safeParse, abortEarly",
                    fn = parseOk(build(z):limits({ abortEarly = true })),
                    key = key .. ".abort",
                },
            }
        end,
        hand = function(v)
            if type(v) ~= "table" then return false end
            local n = #v
            if n > PAYLOAD_ROWS then return false end
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
                if type(id) ~= "number" or id % 1 ~= 0 or id < 1 then return false end
                local name = row.name
                if type(name) ~= "string" or #name < 1 then return false end
            end
            return true
        end,
    }
end

local SCHEMAS = 200
local USED = 10

local function s9Schema(z, i)
    return z.object({
        id = z.integer():min(i),
        name = z.string():min(1):max(8 + i % 24),
        role = z.enum({ "admin", "user", "guest", "r" .. i }),
        tags = z.array(z.string():max(4 + i % 12)):max(3 + i % 7),
        address = z.object({ city = z.string():min(1 + i % 3), zip = z.string():len(5) }),
        active = z.boolean(),
    })
end

local function s9()
    local sample = {
        id = 100000, name = "alice", role = "admin", tags = { "a", "b" },
        address = { city = "Paris", zip = "75001" }, active = true,
    }
    local function buildAll(z)
        local list = {}
        for i = 1, SCHEMAS do list[i] = s9Schema(z, i) end
        return list
    end
    local function useSome(list)
        local hits = 0
        for i = 1, USED do
            if list[i]:is(sample) then hits = hits + 1 end
        end
        return hits
    end
    return {
        name = "S9 200 schemas defined, 10 used",
        register = function(z, b)
            assert(useSome(buildAll(z)) == USED, "S9: the sample must satisfy the first schemas")
            local function withCodegen(flag, fn)
                local previous = z.config().codegen
                z.config({ codegen = flag })
                local ok, out = pcall(fn)
                z.config({ codegen = previous })
                if not ok then error(out, 0) end
                return out
            end
            b.scenario("S9 200 schemas defined, 10 used - cold start", {
                { name = "define 200 (no compilation)", fn = function() return #buildAll(z) end, key = "s9.define" },
                {
                    name = "define 200, validate with 10 (compiled on first use)",
                    fn = function() return useSome(buildAll(z)) end,
                    key = "s9.lazy",
                },
                {
                    name = "define 200, compile all 200, validate with 10",
                    fn = function()
                        local all = buildAll(z)
                        for i = 1, #all do local _ = all[i]._test end
                        return useSome(all)
                    end,
                    key = "s9.eager",
                },
                {
                    name = "define 200, validate with 10 (closures)",
                    fn = function()
                        return withCodegen(false, function() return useSome(buildAll(z)) end)
                    end,
                    key = "s9.closures",
                },
            })
        end,
    }
end

local ffi
if jit then
    local okFfi, lib = pcall(require, "ffi")
    if okFfi then ffi = lib end
end
local nativeInt = math.type ~= nil and math.maxinteger ~= nil and math.maxinteger > 2 ^ 53
local SAFE = 2 ^ 53

local function utf8Length(s)
    if not s:find("[\128-\255]") then return #s end
    local n, i, len = 0, 1, #s
    local byte = string.byte
    while i <= len do
        local c = byte(s, i)
        if c < 0x80 then
            i = i + 1
        elseif c < 0xC2 then
            return nil
        elseif c < 0xE0 then
            local c2 = byte(s, i + 1)
            if not c2 or c2 < 0x80 or c2 > 0xBF then return nil end
            i = i + 2
        elseif c < 0xF0 then
            local c2, c3 = byte(s, i + 1, i + 2)
            if not c3 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF then return nil end
            if (c == 0xE0 and c2 < 0xA0) or (c == 0xED and c2 > 0x9F) then return nil end
            i = i + 3
        elseif c < 0xF5 then
            local c2, c3, c4 = byte(s, i + 1, i + 3)
            if not c4 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF or c4 < 0x80 or c4 > 0xBF then
                return nil
            end
            if (c == 0xF0 and c2 < 0x90) or (c == 0xF4 and c2 > 0x8F) then return nil end
            i = i + 4
        else
            return nil
        end
        n = n + 1
    end
    return n
end

local function int64Ok(id)
    if type(id) == "number" then
        if nativeInt and math.type(id) == "integer" then return true end
        return id >= -SAFE and id <= SAFE and id % 1 == 0
    end
    return ffi ~= nil and ffi.istype("int64_t", id)
end

local function s10Name(i)
    local k = i % 4
    if k == 1 then return "h\195\169llo" .. i end
    if k == 2 then return "\230\151\165\230\156\172" .. i end
    return "user" .. i
end

local function s10Valid(i)
    local id = 1099511627776 + i * 1234567
    if ffi and i % 5 == 0 then id = ffi.new("int64_t", id) end
    return { a = i % 256, b = (i * 65537) % 2000000 - 1000000, id = id, name = s10Name(i) }
end

local function s10With(key, value)
    local v = s10Valid(3)
    v[key] = value
    return v
end

local function s10()
    local inputs = {}
    for i = 1, 64 do inputs[i] = s10Valid(i) end
    local invalid = {
        "x", 5, {},
        s10With("a", 256), s10With("a", -1), s10With("a", 1.5), s10With("a", "1"), s10With("a", nil),
        s10With("b", 2147483648), s10With("b", -2147483649), s10With("b", 0.5), s10With("b", 0 / 0),
        s10With("id", 2 ^ 53 + 2), s10With("id", 1.5), s10With("id", "1"), s10With("id", nil),
        s10With("name", ""), s10With("name", ("n"):rep(33)), s10With("name", "\192\128"),
        s10With("name", "\237\160\128"), s10With("name", "\255"), s10With("name", 5),
        s10With("name", ("\195\169"):rep(33)),
    }
    if ffi then
        invalid[#invalid + 1] = s10With("id", ffi.new("uint64_t", 5))
        invalid[#invalid + 1] = s10With("id", ffi.new("int32_t", 5))
    end
    return {
        name = "S10 boundary object (u8, i32, int64, utf8)",
        inputs = inputs,
        invalid = invalid,
        build = function(z)
            return z.object({
                a = z.u8(),
                b = z.i32(),
                id = z.int64(),
                name = z.utf8():min(1):max(32),
            })
        end,
        hand = function(v)
            if type(v) ~= "table" then return false end
            local a = v.a
            if type(a) ~= "number" or a % 1 ~= 0 or a < 0 or a > 255 then return false end
            local b = v.b
            if type(b) ~= "number" or b % 1 ~= 0 or b < -2147483648 or b > 2147483647 then return false end
            if not int64Ok(v.id) then return false end
            local name = v.name
            if type(name) ~= "string" then return false end
            local n = utf8Length(name)
            return n ~= nil and n >= 1 and n <= 32
        end,
    }
end

M.s1, M.s2, M.s3, M.s4, M.s5, M.s6, M.s7, M.s9, M.s10 = s1, s2, s3, s4, s5, s6, s7, s9, s10

M.all = { s1, s2, s3, s4, s5, s6, s7, s9, s10 }

return M
