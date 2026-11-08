return function(env)
    local test, z = env.test, env.z
    local assertTrue, assertEq = env.assertTrue, env.assertEq

    local SEED = 20261108
    local IMPURE_SEED = 20261109
    local IMPURE_SCHEMAS = 2500
    local SCHEMAS = 4000
    local INPUTS = 8
    local MAX_DEPTH = 3

    local LIMITS_SEED = 20261110
    local LIMITS_SCHEMAS = 1500

    local huge = math.huge
    local nan = 0 / 0
    local unpack = table.unpack or unpack
    local loader = loadstring or load

    local ffi
    if jit then
        local okFfi, lib = pcall(require, "ffi")
        if okFfi then ffi = lib end
    end
    local nativeInt = math.type ~= nil and math.maxinteger ~= nil and math.maxinteger > 2 ^ 53

    local fixedRanges = {
        u8 = { 0, 255 }, u16 = { 0, 65535 }, u32 = { 0, 4294967295 },
        i8 = { -128, 127 }, i16 = { -32768, 32767 }, i32 = { -2147483648, 2147483647 },
    }
    local fixedNames = { "u8", "u16", "u32", "i8", "i16", "i32" }
    local p4aKinds = { "u8", "u16", "u32", "i8", "i16", "i32", "int64", "bytes", "utf8" }
    local p4aSet = {}
    for _, k in ipairs(p4aKinds) do p4aSet[k] = true end

    local state = SEED
    local function reseed(s) state = s end
    local function nextInt()
        state = (state * 16807) % 2147483647
        return state
    end
    local function rand(n) return nextInt() % n + 1 end
    local function chance(percent) return nextInt() % 100 < percent end
    local function pick(list) return list[rand(#list)] end

    local function sortedKeys(t)
        local keys = {}
        for k in next, t do
            local tk = type(k)
            if tk == "string" or tk == "number" or tk == "boolean" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            if ta == "boolean" then return (not a) and b end
            return a < b
        end)
        return keys
    end

    local function show(v, depth)
        depth = depth or 0
        if type(v) == "string" then return ("%q"):format(v) end
        if type(v) ~= "table" then
            local t = type(v)
            if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
            return "<" .. t .. ">"
        end
        if depth > 5 then return "{...}" end
        local parts = {}
        local keys = sortedKeys(v)
        for i = 1, #keys do
            parts[i] = "[" .. show(keys[i], depth + 1) .. "]=" .. show(rawget(v, keys[i]), depth + 1)
        end
        local suffix = getmetatable(v) ~= nil and "+mt" or ""
        return "{" .. table.concat(parts, ",") .. "}" .. suffix
    end

    local keyPool = { "a", "b", "c", "id", "name", "x y", "]]", "\0k", "k\"q", "\195\169", "__index", "1", "" }
    local numPool = { -10, -1.5, -1, 0, 0.5, 1, 2, 3, 7, 10, 100, 2 ^ 53 }
    local intPool = { 0, 1, 2, 3, 5, 8 }
    local stringPool = { "", "a", "abc", "abcdef", "xyz", "a b", "\0", "]]" }

    local function pickBounds(pool, integerOnly)
        local lo, hi = pick(pool), pick(pool)
        if lo > hi then lo, hi = hi, lo end
        if not integerOnly and chance(6) then
            if chance(50) then lo = -huge else hi = huge end
        end
        return lo, hi
    end

    local function fixedPool(kind)
        local lo, hi = fixedRanges[kind][1], fixedRanges[kind][2]
        return { lo - 1, lo, lo + 1, -1, 0, 1, 2, hi - 1, hi, hi + 1 }
    end

    local function genMods(kind, integerOnly, custom)
        local pool = custom or (integerOnly and intPool or numPool)
        local mods = {}
        local count = rand(4) - 1
        for _ = 1, count do
            local which = pick(kind == "string" and { "min", "max", "len", "between" }
                or kind == "array" and { "min", "max", "len", "between" }
                or { "min", "max", "between" })
            if which == "between" then
                local lo, hi = pickBounds(pool, integerOnly)
                mods[#mods + 1] = { "between", lo, hi }
            else
                mods[#mods + 1] = { which, pick(pool) }
            end
        end
        return mods
    end

    local SENT_T = setmetatable({}, { __tostring = function() return "fuzz-null" end })
    local sentinelPool = { SENT_T, io.stdin }
    local sentinelNames = { [SENT_T] = "T", [io.stdin] = "stdin" }
    local ClassA = { __index = {} }
    local ClassB = { __index = {} }
    local fileMt = getmetatable(io.stdout)
    local userdataValues = { io.stdout, io.stderr }
    local mtPool = { ClassA, ClassB, fileMt }
    local mtNames = { [ClassA] = "A", [ClassB] = "B", [fileMt] = "file" }
    local proxyValue, proxyMt
    if newproxy then
        proxyValue = newproxy(true)
        proxyMt = getmetatable(proxyValue)
        userdataValues[#userdataValues + 1] = proxyValue
        mtPool[#mtPool + 1] = proxyMt
        mtNames[proxyMt] = "proxy"
    end
    local functionValues = { print, function() end, string.format }

    local function instanceFor(mt)
        if mt == fileMt then return io.stdout end
        if mt == proxyMt then return proxyValue end
        return setmetatable({}, mt)
    end

    local cdataInfo = setmetatable({}, { __mode = "k" })
    local cdataCtypes = { "int64_t" }
    local pointerCtypes = { "void *" }
    local cdataMakers, nullMakers = {}, {}
    if ffi then
        ffi.cdef([[
            typedef struct zigo_fz_point { int x; } zigo_fz_point;
            typedef struct zigo_fz_other { int a; } zigo_fz_other;
        ]])
        cdataCtypes = {
            "int64_t", "uint64_t", "int32_t", "double", "void *", "int *", "zigo_fz_point *", "zigo_fz_point",
            "zigo_fz_other *",
        }
        pointerCtypes = { "void *", "int *", "zigo_fz_point *", "zigo_fz_other *" }
        local backing = ffi.new("zigo_fz_point[2]")
        local function register(v, ptr, null)
            cdataInfo[v] = { ptr = ptr, null = null }
            return v
        end
        cdataMakers = {
            function() return register(ffi.new("int64_t", rand(3) - 1), false) end,
            function() return register(ffi.new("uint64_t", rand(3) - 1), false) end,
            function() return register(ffi.new("int32_t", rand(3) - 1), false) end,
            function() return register(ffi.new("double", rand(3) - 1), false) end,
            function() return register(loader("return 1LL")(), false) end,
            function() return register(ffi.new("zigo_fz_point"), false) end,
            function() return register(ffi.new("zigo_fz_other"), false) end,
            function() return register(ffi.cast("void *", backing), true, false) end,
            function() return register(ffi.cast("int *", backing), true, false) end,
            function() return register(ffi.cast("zigo_fz_point *", backing), true, false) end,
            function() return register(ffi.cast("zigo_fz_other *", backing), true, false) end,
        }
        nullMakers = {
            function() return register(ffi.cast("void *", 0), true, true) end,
            function() return register(ffi.cast("int *", 0), true, true) end,
            function() return register(ffi.cast("zigo_fz_point *", 0), true, true) end,
            function() return register(ffi.cast("zigo_fz_other *", 0), true, true) end,
        }
    end

    local leafKinds = {
        "string", "string", "string", "number", "number", "integer", "integer", "integer",
        "boolean", "boolean", "literal", "literal", "enum", "enum", "any", "unknown", "never",
        "u8", "u16", "u32", "i8", "i16", "i32", "int64", "int64", "bytes", "utf8", "utf8",
    }
    for _, k in ipairs({ "null", "null", "func", "userdata", "userdata", "instanceOf", "instanceOf" }) do
        leafKinds[#leafKinds + 1] = k
    end
    if ffi then
        for _, k in ipairs({ "cdata", "cdata", "notNullPtr", "notNullPtr" }) do leafKinds[#leafKinds + 1] = k end
    end
    local p4bSet = { null = true, func = true, userdata = true, instanceOf = true, cdata = true, notNullPtr = true }
    local p4bKinds = { "literal", "null", "func", "userdata", "instanceOf" }
    if ffi then
        p4bKinds[#p4bKinds + 1] = "cdata"
        p4bKinds[#p4bKinds + 1] = "notNullPtr"
    end

    local function leafSpec(kind)
        local spec = { kind = kind }
        if kind == "string" or kind == "bytes" or kind == "utf8" then
            spec.mods = genMods("string", true)
        elseif fixedRanges[kind] then
            spec.strict = chance(25)
            spec.mods = genMods("integer", false, fixedPool(kind))
        elseif kind == "number" then
            spec.mods = genMods("number", false)
        elseif kind == "integer" then
            spec.strict = chance(25)
            spec.mods = genMods("integer", false)
        elseif kind == "literal" then
            local t = rand(3)
            if t == 1 then spec.value = pick(stringPool)
            elseif t == 2 then spec.value = pick(numPool)
            else spec.value = chance(50) end
        elseif kind == "enum" then
            spec.values = {}
            for i = 1, rand(4) do
                local t = rand(4)
                if t <= 2 then spec.values[i] = pick(stringPool)
                elseif t == 3 then spec.values[i] = pick(numPool)
                else spec.values[i] = chance(50) end
            end
        elseif kind == "null" then
            spec.sentinel = pick(sentinelPool)
        elseif kind == "userdata" then
            if chance(70) then spec.mt = pick(mtPool) end
        elseif kind == "instanceOf" then
            spec.mt = pick(mtPool)
        elseif kind == "cdata" then
            spec.ctype = pick(cdataCtypes)
        elseif kind == "notNullPtr" then
            spec.ctype = pick(pointerCtypes)
        end
        return spec
    end

    local recordKeyKinds = { "string", "string", "integer", "number", "enum", "boolean", "any", "literal", "u8", "utf8" }
    local discriminantKeys = { "kind", "type", "t", "\0d", "]]" }
    local discriminantValues = { "a", "b", "c", "", 1, 2, 2.5, true, false }

    local genSpec
    genSpec = function(depth)
        local roll = rand(100)
        local spec
        if depth < MAX_DEPTH and roll <= 16 then
            spec = { kind = "object", fields = {}, strict = chance(35), meta = chance(15) }
            local pool = {}
            for i = 1, #keyPool do pool[i] = keyPool[i] end
            for _ = 1, rand(6) - 1 do
                local idx = rand(#pool)
                spec.fields[#spec.fields + 1] = { key = table.remove(pool, idx), spec = genSpec(depth + 1) }
            end
        elseif depth < MAX_DEPTH and roll <= 28 then
            spec = { kind = "array", item = genSpec(depth + 1), meta = chance(20), mods = genMods("array", true) }
        elseif depth < MAX_DEPTH and roll <= 34 then
            spec = { kind = "tuple", items = {}, meta = chance(15) }
            for i = 1, rand(4) - 1 do spec.items[i] = genSpec(depth + 1) end
            if chance(40) then spec.rest = genSpec(depth + 1) end
        elseif depth < MAX_DEPTH and roll <= 40 then
            local key = leafSpec(pick(recordKeyKinds))
            key.optional = false
            spec = { kind = "record", key = key, value = genSpec(depth + 1) }
        elseif depth < MAX_DEPTH and roll <= 46 then
            spec = { kind = "union", variants = {} }
            for i = 1, rand(3) + 1 do spec.variants[i] = genSpec(depth + 1) end
        elseif depth < MAX_DEPTH and roll <= 52 then
            spec = { kind = "dunion", key = pick(discriminantKeys), variants = {} }
            local values = {}
            for i = 1, #discriminantValues do values[i] = discriminantValues[i] end
            for i = 1, rand(3) do
                local variant = {
                    kind = "object", fields = {}, strict = chance(25), meta = chance(15),
                    variant = true, optional = false,
                }
                variant.fields[1] = {
                    key = spec.key,
                    spec = { kind = "literal", value = table.remove(values, rand(#values)), plain = true, optional = false },
                }
                local pool = {}
                for j = 1, #keyPool do
                    if keyPool[j] ~= spec.key then pool[#pool + 1] = keyPool[j] end
                end
                for _ = 1, rand(3) - 1 do
                    local idx = rand(#pool)
                    variant.fields[#variant.fields + 1] = { key = table.remove(pool, idx), spec = genSpec(depth + 2) }
                end
                spec.variants[i] = variant
            end
        elseif depth < MAX_DEPTH and roll <= 58 then
            spec = { kind = "lazy", target = genSpec(depth + 1) }
        else
            spec = leafSpec(pick(leafKinds))
        end
        if spec.optional == nil then spec.optional = chance(22) end
        if spec.nullable == nil then
            spec.nullable = chance(14) and { at = 0, sentinel = pick(sentinelPool) } or false
        end
        return spec
    end

    local function describe(spec)
        local parts = { spec.kind }
        if spec.strict then parts[#parts + 1] = "strict" end
        if spec.meta then parts[#parts + 1] = "meta" end
        for _, m in ipairs(spec.mods or {}) do
            parts[#parts + 1] = m[1] .. "(" .. tostring(m[2]) .. (m[3] ~= nil and ("," .. tostring(m[3])) or "") .. ")"
        end
        if spec.value ~= nil then parts[#parts + 1] = "=" .. show(spec.value) end
        if spec.values then parts[#parts + 1] = "in " .. show(spec.values) end
        if spec.strip then parts[#parts + 1] = "strip" end
        for _, step in ipairs(spec.chain or {}) do parts[#parts + 1] = step.op .. ":" .. step.def end
        if spec.default then
            parts[#parts + 1] = "default@" .. spec.default.at .. "=" .. show(spec.default.value)
        end
        if spec.optional then parts[#parts + 1] = "optional" end
        if spec.sentinel ~= nil then parts[#parts + 1] = "sentinel=" .. sentinelNames[spec.sentinel] end
        if spec.mt ~= nil then parts[#parts + 1] = "mt=" .. mtNames[spec.mt] end
        if spec.ctype ~= nil then parts[#parts + 1] = "ctype=" .. spec.ctype end
        if spec.nullable then
            parts[#parts + 1] = "nullable@" .. spec.nullable.at .. "=" .. sentinelNames[spec.nullable.sentinel]
        end
        local out = table.concat(parts, " ")
        if spec.kind == "array" then out = out .. " of (" .. describe(spec.item) .. ")" end
        if spec.kind == "tuple" then
            local items = {}
            for i, item in ipairs(spec.items) do items[i] = describe(item) end
            out = out .. " (" .. table.concat(items, "; ") .. ")"
            if spec.rest then out = out .. " rest (" .. describe(spec.rest) .. ")" end
        end
        if spec.kind == "record" then
            out = out .. " (" .. describe(spec.key) .. " => " .. describe(spec.value) .. ")"
        end
        if spec.kind == "lazy" then
            out = out .. " lazy (" .. describe(spec.target) .. ")"
        end
        if spec.kind == "union" or spec.kind == "dunion" then
            local variants = {}
            for i, variant in ipairs(spec.variants) do variants[i] = describe(variant) end
            out = out .. (spec.key and (" on " .. show(spec.key)) or "") .. " <" .. table.concat(variants, " | ") .. ">"
        end
        if spec.kind == "object" then
            local fields = {}
            for i, f in ipairs(spec.fields) do fields[i] = show(f.key) .. ": " .. describe(f.spec) end
            out = out .. " {" .. table.concat(fields, "; ") .. "}"
        end
        return out
    end

    local transformDefs = {
        box = function(v) return { v } end,
        const = function() return 42 end,
        drop = function() return nil end,
        noNumbers = function(v, ctx)
            if type(v) == "number" then ctx:addIssue({ message = "no numbers" }) end
            return v
        end,
    }
    local transformNames = { "box", "const", "drop", "noNumbers" }

    local refineDefs = {
        notFalse = function(v) return v ~= false end,
        truthy = function(v) return v end,
        notNumber = function(v) return type(v) ~= "number" end,
        reporter = function(v, ctx)
            if type(v) == "string" then ctx:addIssue({ message = "no strings" }) end
            return true
        end,
    }
    local refineNames = { "notFalse", "truthy", "notNumber", "reporter" }

    local defaultValues = {
        5, "d", false, {}, function() return { made = true } end, function() return 7 end,
    }

    local function applyImpure(n, spec)
        local chain = spec.chain or {}
        local default = spec.default
        for i = 0, #chain do
            if default and default.at == i then n = n:default(default.value) end
            if spec.nullable and spec.nullable.at == i then n = n:nullable(spec.nullable.sentinel) end
            local step = chain[i + 1]
            if step then
                if step.op == "transform" then
                    n = n:transform(transformDefs[step.def])
                else
                    n = n:refine(refineDefs[step.def], { message = "refined" })
                end
            end
        end
        return n
    end

    local forcers = {}

    local function build(spec)
        local kind, n = spec.kind, nil
        if kind == "string" then n = z.string()
        elseif kind == "number" then n = z.number()
        elseif kind == "integer" then n = z.integer(spec.strict and { strict = true } or nil)
        elseif fixedRanges[kind] then n = z[kind](spec.strict and { strict = true } or nil)
        elseif kind == "int64" then n = z.int64()
        elseif kind == "bytes" then n = z.bytes()
        elseif kind == "utf8" then n = z.utf8()
        elseif kind == "boolean" then n = z.boolean()
        elseif kind == "literal" then n = z.literal(spec.value)
        elseif kind == "enum" then n = z.enum(spec.values)
        elseif kind == "any" then n = z.any()
        elseif kind == "unknown" then n = z.unknown()
        elseif kind == "never" then n = z.never()
        elseif kind == "null" then n = z.null(spec.sentinel)
        elseif kind == "func" then n = z.func()
        elseif kind == "userdata" then n = z.userdata(spec.mt)
        elseif kind == "instanceOf" then n = z.instanceOf(spec.mt)
        elseif kind == "cdata" then n = z.cdata(spec.ctype)
        elseif kind == "notNullPtr" then n = z.notNullPtr(spec.ctype)
        elseif kind == "array" then n = z.array(build(spec.item), spec.meta and { meta = true } or nil)
        elseif kind == "object" then
            local shape = {}
            for _, f in ipairs(spec.fields) do shape[f.key] = build(f.spec) end
            n = z.object(shape, spec.meta and { meta = true } or nil)
            if spec.strict then n = n:strict() end
            if spec.strip then n = n:strip() end
        elseif kind == "tuple" then
            local items = {}
            for i, item in ipairs(spec.items) do items[i] = build(item) end
            n = z.tuple(items, spec.meta and { meta = true } or nil)
            if spec.rest then n = n:rest(build(spec.rest)) end
        elseif kind == "record" then
            n = z.record(build(spec.key), build(spec.value))
        elseif kind == "lazy" then
            local target = build(spec.target)
            forcers[#forcers + 1] = function()
                local _ = target._test
                _ = target._testD
                _ = target._check
            end
            n = z.lazy(function() return target end)
        elseif kind == "union" or kind == "dunion" then
            local variants = {}
            for i, variant in ipairs(spec.variants) do variants[i] = build(variant) end
            if kind == "union" then
                n = z.union(unpack(variants))
            else
                n = z.discriminatedUnion(spec.key, unpack(variants))
            end
        end
        for _, m in ipairs(spec.mods or {}) do n = n[m[1]](n, m[2], m[3]) end
        n = applyImpure(n, spec)
        if spec.optional then n = n:optional() end
        return n
    end

    local junkMakers = {
        function() return nil end, function() return true end, function() return false end,
        function() return 0 end, function() return -0.0 end, function() return 1 end,
        function() return -1 end, function() return 3.0 end, function() return 2.5 end,
        function() return 2 ^ 53 end, function() return 2 ^ 63 end, function() return huge end,
        function() return -huge end, function() return nan end, function() return "" end,
        function() return "a" end, function() return "abc" end, function() return "abcdef" end,
        function() return print end, function() return io.stdout end,
        function() return coroutine.create(function() end) end, function() return {} end,
        function() return { 1, 2, 3 } end, function() return { a = 1 } end,
        function() return { 1, nil, 3 } end, function() return { { a = "a" } } end,
        function() return SENT_T end, function() return io.stdin end, function() return io.stderr end,
        function() return function() end end, function() return instanceFor(ClassA) end,
        function() return instanceFor(ClassB) end,
    }
    for i = 1, #cdataMakers do junkMakers[#junkMakers + 1] = cdataMakers[i] end
    local function junk() return pick(junkMakers)() end

    local function genP4b(spec)
        local kind = spec.kind
        if chance(10) then return junk() end
        if kind == "null" then
            if chance(85) then return spec.sentinel end
            return pick(sentinelPool)
        elseif kind == "func" then
            return pick(functionValues)
        elseif kind == "userdata" then
            return pick(userdataValues)
        elseif kind == "instanceOf" then
            if chance(75) then return instanceFor(spec.mt) end
            return instanceFor(pick(mtPool))
        end
        return pick(cdataMakers)()
    end

    local codePoints = {
        0, 0x41, 0x7F, 0x80, 0xE9, 0x7FF, 0x800, 0x20AC, 0xD7FF, 0xE000, 0xFFFD, 0xFFFF, 0x10000, 0x1F600, 0x10FFFF,
    }
    local badUtf8 = {
        "\128", "\191", "\192\128", "\193\191", "\224\128\128", "\224\159\191", "\240\128\128\128",
        "\240\143\191\191", "\237\160\128", "\237\175\191", "\237\176\128", "\237\191\191", "\244\144\128\128",
        "\245\128\128\128", "\248\136\128\128\128", "\252\132\128\128\128\128", "\254", "\255",
        "\194", "\226\130", "\240\159\152", "\194A", "\226\130A", "\240\159\152A", "\226A\172",
    }

    local function encodeChar(cp)
        if cp < 0x80 then return string.char(cp) end
        if cp < 0x800 then
            return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
        end
        if cp < 0x10000 then
            return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
        end
        return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
            0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
    end

    local int64Edges = nil
    local function edgesOfInt64()
        if int64Edges then return int64Edges end
        local list = {
            0, 1, -1, 3.0, -0.0, 2 ^ 53, -(2 ^ 53), 2 ^ 53 - 1, 2 ^ 53 + 2, -(2 ^ 53) - 2, 2 ^ 53 + 1,
            2 ^ 62, 2 ^ 63, -(2 ^ 63), 2 ^ 64, 2.5, nan, huge, -huge, 1e300, "1", "9007199254740993", true, {},
        }
        if nativeInt then
            list[#list + 1] = math.maxinteger
            list[#list + 1] = math.mininteger
            list[#list + 1] = loader("return 9007199254740993")()
            list[#list + 1] = loader("return -9007199254740993")()
            list[#list + 1] = loader("return 9007199254740992")()
            list[#list + 1] = loader("return 9007199254740991")()
            list[#list + 1] = loader("return 9007199254740994")()
        end
        if ffi then
            local i64 = function(x) return ffi.new("int64_t", x) end
            local u64 = function(x) return ffi.new("uint64_t", x) end
            list[#list + 1] = i64(0)
            list[#list + 1] = i64(1)
            list[#list + 1] = i64(-1)
            list[#list + 1] = loader("return 1LL")()
            list[#list + 1] = loader("return 9007199254740993LL")()
            list[#list + 1] = loader("return -9007199254740993LL")()
            list[#list + 1] = loader("return 9223372036854775807LL")()
            list[#list + 1] = loader("return -9223372036854775807LL - 1")()
            list[#list + 1] = u64(0)
            list[#list + 1] = u64(1)
            list[#list + 1] = loader("return 1ULL")()
            list[#list + 1] = loader("return 18446744073709551615ULL")()
            list[#list + 1] = ffi.new("int32_t", 5)
            list[#list + 1] = ffi.new("double", 5)
            list[#list + 1] = ffi.new("int64_t[1]", 5)
            list[#list + 1] = ffi.cast("void *", 0)
        end
        int64Edges = list
        return list
    end

    local function lengthOf(spec, fallback)
        local lo, hi, len = 0, nil, nil
        for _, m in ipairs(spec.mods) do
            if m[1] == "min" then lo = m[2]
            elseif m[1] == "max" then hi = m[2]
            elseif m[1] == "len" then len = m[2]
            else lo, hi = m[2], m[3] end
        end
        local n
        if len and chance(70) then n = len + (chance(70) and 0 or (chance(50) and -1 or 1))
        else n = lo - 1 + rand(math.max(1, (hi or lo + fallback) - lo + 3)) - 1 end
        if n < 0 then n = 0 end
        return n
    end

    local function genFixed(spec)
        local range = fixedRanges[spec.kind]
        local cands = { range[1], range[2], range[1] - 1, range[2] + 1, 0, 1, -1, 3, range[1] + 1, range[2] - 1 }
        for _, m in ipairs(spec.mods) do
            for i = 2, 3 do
                local b = m[i]
                if b ~= nil and b == b and b ~= huge and b ~= -huge then
                    cands[#cands + 1] = b
                    cands[#cands + 1] = b - 1
                    cands[#cands + 1] = b + 1
                end
            end
        end
        local x = pick(cands)
        local r = rand(24)
        if r == 1 then return nan end
        if r == 2 then return pick({ huge, -huge }) end
        if r == 3 then return x + 0.5 end
        if r == 4 then return pick({ 2 ^ 53, 2 ^ 63, 2 ^ 32, -(2 ^ 31) - 1 }) end
        if r == 5 then return tostring(x) end
        if r == 6 and ffi then return ffi.new("int64_t", x) end
        if r <= 11 then return x + 0.0 end
        return x
    end

    local function genUtf8(spec)
        local n = lengthOf(spec, 4)
        local parts = {}
        for i = 1, n do parts[i] = encodeChar(pick(codePoints)) end
        local s = table.concat(parts)
        local r = rand(100)
        if r <= 20 then
            local at = rand(#s + 1)
            s = s:sub(1, at - 1) .. pick(badUtf8) .. s:sub(at)
        elseif r <= 28 and #s > 0 then
            s = s:sub(1, #s - rand(2))
        end
        return s
    end

    local function between(lo, hi)
        if lo ~= lo or hi ~= hi or lo == -huge or hi == huge then return 0 end
        return lo + (hi - lo) * (rand(1000) - 1) / 999
    end

    local genValid
    genValid = function(spec)
        if (spec.optional or spec.default) and chance(25) then return nil end
        if spec.nullable and chance(18) then return spec.nullable.sentinel end
        local kind = spec.kind
        if p4bSet[kind] then return genP4b(spec) end
        if p4aSet[kind] then
            if kind == "int64" then
                if chance(15) then return junk() end
                local edges = edgesOfInt64()
                return edges[rand(#edges)]
            elseif kind == "utf8" then
                if chance(6) then return junk() end
                return genUtf8(spec)
            elseif kind == "bytes" then
                if chance(6) then return junk() end
                local chars = {}
                for i = 1, lengthOf(spec, 4) do
                    chars[i] = string.char(chance(40) and rand(256) - 1 or 96 + rand(5))
                end
                return table.concat(chars)
            end
            if chance(5) then return junk() end
            return genFixed(spec)
        elseif kind == "string" then
            local lo, hi, len = 0, nil, nil
            for _, m in ipairs(spec.mods) do
                if m[1] == "min" then lo = m[2]
                elseif m[1] == "max" then hi = m[2]
                elseif m[1] == "len" then len = m[2]
                else lo, hi = m[2], m[3] end
            end
            local n
            if len and chance(70) then n = len + (chance(70) and 0 or (chance(50) and -1 or 1))
            else n = lo - 1 + rand(math.max(1, (hi or lo + 4) - lo + 3)) - 1 end
            if n < 0 then n = 0 end
            local chars = {}
            for i = 1, n do chars[i] = string.char(96 + rand(5)) end
            return table.concat(chars)
        elseif kind == "number" or kind == "integer" then
            if chance(8) then return pick({ nan, huge, -huge, -0.0, 2.5, 3.0, 2 ^ 63 }) end
            local lo, hi = -10, 10
            for _, m in ipairs(spec.mods) do
                if m[1] == "min" then lo = m[2]
                elseif m[1] == "max" then hi = m[2]
                else lo, hi = m[2], m[3] end
            end
            local x
            local t = rand(4)
            if t == 1 then x = lo elseif t == 2 then x = hi
            elseif t == 3 then x = between(lo, hi)
            else x = pick({ lo - 1, hi + 1, (lo ~= lo or lo == -huge) and 0 or math.floor(between(lo, hi)) }) end
            if x ~= x or x == huge or x == -huge then return x end
            if kind == "integer" and chance(85) then
                x = math.floor(x)
                if chance(30) then x = x + 0.0 end
            end
            return x
        elseif kind == "boolean" then
            return chance(50)
        elseif kind == "literal" then
            if chance(80) then return spec.value end
            return junk()
        elseif kind == "enum" then
            if chance(80) then return pick(spec.values) end
            return junk()
        elseif kind == "any" or kind == "unknown" or kind == "never" then
            return junk()
        elseif kind == "array" then
            local lo, hi, len = 0, nil, nil
            for _, m in ipairs(spec.mods) do
                if m[1] == "min" then lo = m[2]
                elseif m[1] == "max" then hi = m[2]
                elseif m[1] == "len" then len = m[2]
                else lo, hi = m[2], m[3] end
            end
            local n
            if len and chance(70) then n = len + (chance(70) and 0 or (chance(50) and -1 or 1))
            else n = lo - 1 + rand(math.max(1, (hi or lo + 3) - lo + 3)) - 1 end
            if n < 0 then n = 0 end
            local t = {}
            for i = 1, n do t[i] = genValid(spec.item) end
            if chance(8) then t.extra = junk() end
            return t
        elseif kind == "object" then
            local t = {}
            for _, f in ipairs(spec.fields) do
                local x = genValid(f.spec)
                if x ~= nil then t[f.key] = x end
            end
            if chance(25) then t[chance(50) and "extra" or 1] = junk() end
            return t
        elseif kind == "tuple" then
            local t = {}
            local count = #spec.items
            local n = count
            if chance(8) then n = rand(count + 1) - 1 end
            for i = 1, n do
                local x = genValid(spec.items[i])
                if x == nil then break end
                t[i] = x
            end
            if spec.rest then
                if chance(70) then
                    for _ = 1, rand(3) - 1 do
                        local x = genValid(spec.rest)
                        if x ~= nil then t[#t + 1] = x end
                    end
                end
            elseif chance(8) then
                local x = junk()
                if x ~= nil then t[#t + 1] = x end
            end
            if chance(4) then t.extra = junk() end
            return t
        elseif kind == "record" then
            local t = {}
            for _ = 1, rand(4) - 1 do
                local k = genValid(spec.key)
                if k ~= nil and k == k then
                    local x = genValid(spec.value)
                    if x ~= nil then t[k] = x end
                end
            end
            if chance(6) then
                local k = junk()
                if k ~= nil and k == k then t[k] = junk() end
            end
            return t
        elseif kind == "lazy" then
            return genValid(spec.target)
        elseif kind == "union" then
            if chance(10) then return junk() end
            return genValid(pick(spec.variants))
        elseif kind == "dunion" then
            if chance(8) then return junk() end
            local t = genValid(pick(spec.variants))
            if type(t) == "table" and chance(8) then t[spec.key] = junk() end
            return t
        end
    end

    local function proxyOf(v)
        local partial = {}
        local keys = sortedKeys(v)
        for i = 1, #keys do
            if i % 2 == 1 then partial[keys[i]] = v[keys[i]] end
        end
        return setmetatable(partial, { __index = v, __len = function() return #v end })
    end

    local function mutate(v)
        if type(v) ~= "table" or getmetatable(v) ~= nil then return junk() end
        local keys = sortedKeys(v)
        local r = rand(10)
        if #keys > 0 and r <= 5 then
            local k = keys[rand(#keys)]
            v[k] = mutate(v[k])
            return v
        elseif r == 6 then
            v.zz = junk()
            return v
        elseif r == 7 then
            v[100] = 1
            return v
        elseif r == 8 and #keys > 0 then
            v[keys[rand(#keys)]] = nil
            return v
        elseif r == 9 then
            return proxyOf(v)
        end
        return junk()
    end

    local function genInput(spec)
        local roll = rand(100)
        if roll <= 40 then return genValid(spec) end
        if roll <= 85 then
            local v = genValid(spec)
            for _ = 1, rand(2) do v = mutate(v) end
            return v
        end
        return junk()
    end

    local function force()
        for i = 1, #forcers do forcers[i]() end
        forcers = {}
    end

    local function compileBoth(spec)
        local previous = z.config().codegen
        z.config({ codegen = true })
        forcers = {}
        local generated = build(spec)
        local gTest = generated._test
        force()
        z.config({ codegen = false })
        local reference = build(spec)
        local cTest, cCheck = reference._test, reference._check
        force()
        z.config({ codegen = previous })
        return gTest, cTest, cCheck
    end

    local function verdicts(gTest, cTest, cCheck, data)
        local okG, g = pcall(gTest, data)
        local okC, c = pcall(cTest, data)
        local okK, issues = pcall(cCheck, data, {}, 0, nil)
        return okG, g, okC, c, okK, issues == nil
    end

    test("fuzz: the generators are deterministic for a fixed seed", function()
        local function sample()
            reseed(SEED)
            local out = {}
            for i = 1, 60 do
                local spec = genSpec(0)
                out[i] = describe(spec) .. " <- " .. show(genInput(spec))
            end
            return table.concat(out, "\n")
        end
        assertEq(sample(), sample())
    end)

    test("fuzz: codegen _test == closures _test == (_check found no issue)", function()
        reseed(SEED)
        local accepted, rejected, cases = 0, 0, 0
        for s = 1, SCHEMAS do
            local spec = genSpec(0)
            local gTest, cTest, cCheck = compileBoth(spec)
            if not z._isGenerated(gTest) then
                error(("schema #%d fell back to closures: %s"):format(s, describe(spec)), 0)
            end
            for j = 1, INPUTS do
                local data = genInput(spec)
                local okG, g, okC, c, okK, k = verdicts(gTest, cTest, cCheck, data)
                cases = cases + 1
                if okG ~= okC or okC ~= okK or (okG and (g ~= c or c ~= k)) then
                    error(("mismatch on schema #%d input #%d\nschema: %s\ndata: %s\ncodegen=%s(%s) closures=%s(%s) check-clean=%s(%s)")
                        :format(s, j, describe(spec), show(data), tostring(g), tostring(okG),
                            tostring(c), tostring(okC), tostring(k), tostring(okK)), 0)
                end
                if okG then
                    if g then accepted = accepted + 1 else rejected = rejected + 1 end
                end
            end
        end
        print(("fuzz: %d cases, %d accepted, %d rejected"):format(cases, accepted, rejected))
        assertEq(cases, SCHEMAS * INPUTS)
        assertTrue(accepted >= SCHEMAS)
        assertTrue(rejected >= SCHEMAS)
    end)

    local function signature(issue)
        local parts = {}
        for i = 1, #issue.path do parts[i] = tostring(issue.path[i]) end
        return table.concat(parts, "\1") .. "\2" .. issue.code
    end

    test("fuzz: tight limits agree between codegen, closures and _check, and maxErrors keeps a prefix", function()
        reseed(LIMITS_SEED)
        local before = z.config()
        local cases, rejected, capped = 0, 0, 0
        local ok, err = pcall(function()
            for s = 1, LIMITS_SCHEMAS do
                local spec = genSpec(0)
                z.config({ maxKeys = pick({ 1, 2, 3, 4, 10000 }), maxDepth = pick({ 1, 2, 3, 4, 64 }) })
                local gTest, cTest, cCheck = compileBoth(spec)
                if not z._isGenerated(gTest) then
                    error(("schema #%d fell back to closures: %s"):format(s, describe(spec)), 0)
                end
                for j = 1, INPUTS do
                    local data = genInput(spec)
                    local okG, g, okC, c, okK, k = verdicts(gTest, cTest, cCheck, data)
                    cases = cases + 1
                    if okG ~= okC or okC ~= okK or (okG and (g ~= c or c ~= k)) then
                        error(("limits mismatch on schema #%d input #%d\nschema: %s\ndata: %s\ncodegen=%s(%s) closures=%s(%s) check-clean=%s(%s)")
                            :format(s, j, describe(spec), show(data), tostring(g), tostring(okG),
                                tostring(c), tostring(okC), tostring(k), tostring(okK)), 0)
                    end
                    if okG and not g then rejected = rejected + 1 end
                    local okF, all = pcall(cCheck, data, {}, 0, nil)
                    local okP, few = pcall(cCheck, data, { cap = 3 }, 0, nil)
                    if okF and okP then
                        if (all == nil) ~= (few == nil) or (few and #few > 3) then
                            error(("maxErrors disagrees on schema #%d input #%d\nschema: %s\ndata: %s")
                                :format(s, j, describe(spec), show(data)), 0)
                        end
                        if few then
                            capped = capped + 1
                            for i = 1, #few do
                                if signature(few[i]) ~= signature(all[i]) then
                                    error(("maxErrors is not a prefix on schema #%d input #%d\nschema: %s\ndata: %s")
                                        :format(s, j, describe(spec), show(data)), 0)
                                end
                            end
                        end
                    end
                end
            end
        end)
        z.config({
            maxKeys = before.maxKeys, maxDepth = before.maxDepth,
            maxErrors = before.maxErrors, abortEarly = before.abortEarly,
        })
        if not ok then error(err, 0) end
        print(("fuzz limits: %d cases, %d rejected, %d with issues"):format(cases, rejected, capped))
        assertEq(cases, LIMITS_SCHEMAS * INPUTS)
        assertTrue(rejected >= LIMITS_SCHEMAS)
    end)

    local function decorate(spec)
        if spec.kind == "object" then
            for _, f in ipairs(spec.fields) do
                if not f.spec.plain then decorate(f.spec) end
            end
        elseif spec.kind == "array" then
            decorate(spec.item)
        elseif spec.kind == "tuple" then
            for _, item in ipairs(spec.items) do decorate(item) end
            if spec.rest then decorate(spec.rest) end
        elseif spec.kind == "record" then
            decorate(spec.value)
        elseif spec.kind == "union" or spec.kind == "dunion" then
            for _, variant in ipairs(spec.variants) do decorate(variant) end
        end
        if chance(30) then
            local steps = {}
            for _ = 1, rand(3) - 1 do
                if chance(50) then
                    steps[#steps + 1] = { op = "transform", def = pick(transformNames) }
                else
                    steps[#steps + 1] = { op = "refine", def = pick(refineNames) }
                end
            end
            if #steps > 0 then spec.chain = steps end
            if spec.nullable then spec.nullable.at = rand(#steps + 1) - 1 end
            if chance(50) and not spec.variant then
                spec.default = { at = rand(#steps + 1) - 1, value = pick(defaultValues) }
                if chance(70) then spec.optional = false end
            end
            if spec.kind == "object" and chance(40) then spec.strip = true end
        end
    end

    local isPure

    local function allPure(list)
        for _, child in ipairs(list) do
            if not isPure(child) then return false end
        end
        return true
    end

    local function childrenPure(spec)
        local kind = spec.kind
        if kind == "object" then
            for _, f in ipairs(spec.fields) do
                if not isPure(f.spec) then return false end
            end
        elseif kind == "array" then
            return isPure(spec.item)
        elseif kind == "tuple" then
            return allPure(spec.items) and (spec.rest == nil or isPure(spec.rest))
        elseif kind == "record" then
            return isPure(spec.value)
        elseif kind == "union" or kind == "dunion" then
            return allPure(spec.variants)
        end
        return true
    end

    isPure = function(spec)
        if spec.chain or spec.default or spec.strip then return false end
        return childrenPure(spec)
    end

    local function needsStructure(spec)
        if spec.kind == "object" and spec.strip then return true end
        return not childrenPure(spec)
    end

    local newKinds = {
        tuple = true, record = true, union = true, dunion = true, lazy = true, literal = true,
    }
    for _, k in ipairs(p4aKinds) do newKinds[k] = true end
    for k in pairs(p4bSet) do newKinds[k] = true end

    local function independent(spec)
        if spec.nullable or newKinds[spec.kind] then return true end
        if spec.kind == "object" then
            for _, f in ipairs(spec.fields) do
                if independent(f.spec) then return true end
            end
        elseif spec.kind == "array" then
            return independent(spec.item)
        end
        return false
    end

    local function baseOnly(spec)
        local copy = {}
        for k, v in pairs(spec) do copy[k] = v end
        copy.chain, copy.default, copy.optional, copy.strip, copy.nullable = nil, nil, nil, nil, nil
        return copy
    end

    local function same(a, b)
        if a == b then return true end
        if type(a) == "number" and type(b) == "number" then return a ~= a and b ~= b end
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        for k, x in next, a do
            if not same(x, rawget(b, k)) then return false end
        end
        for k in next, b do
            if rawget(a, k) == nil then return false end
        end
        return true
    end

    local function rawLength(t)
        if rawlen then return rawlen(t) end
        return #t
    end

    local pureSchemas = setmetatable({}, { __mode = "k" })
    local baseSchemas = setmetatable({}, { __mode = "k" })

    local function cached(cache, spec, make)
        local schema = cache[spec]
        if not schema then
            schema = build(make(spec))
            cache[spec] = schema
        end
        return schema
    end

    local oracle

    local function oracleObject(spec, v)
        if type(v) ~= "table" then return false end
        local strict = spec.strict and not spec.strip
        local out, known = {}, {}
        if not spec.strip and not strict then
            for k, x in next, v do out[k] = x end
        end
        for _, f in ipairs(spec.fields) do
            known[f.key] = true
            local x
            if spec.meta then x = v[f.key] else x = rawget(v, f.key) end
            local ok, y = oracle(f.spec, x)
            if not ok then return false end
            out[f.key] = y
        end
        if strict then
            for k in next, v do
                if not known[k] then return false end
            end
        end
        return true, out
    end

    local function oracleArray(spec, v)
        if type(v) ~= "table" then return false end
        local n
        if spec.meta then
            n = #v
            for i = 1, n do
                if v[i] == nil then return false end
            end
        else
            n = rawLength(v)
            local count = 0
            for k in next, v do
                count = count + 1
                if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
            end
            if count ~= n then return false end
        end
        local min, max, len
        for _, m in ipairs(spec.mods) do
            if m[1] == "min" then min = m[2]
            elseif m[1] == "max" then max = m[2]
            elseif m[1] == "len" then len = m[2]
            else min, max = m[2], m[3] end
        end
        if (min and n < min) or (max and n > max) or (len and n ~= len) then return false end
        local out = {}
        for i = 1, n do
            local x
            if spec.meta then x = v[i] else x = rawget(v, i) end
            local ok, y = oracle(spec.item, x)
            if not ok then return false end
            out[i] = y
        end
        return true, out
    end

    local function sequenceLength(v, meta)
        local n
        if meta then
            n = #v
            for i = 1, n do
                if v[i] == nil then return nil end
            end
            return n
        end
        n = rawLength(v)
        local count = 0
        for k in next, v do
            count = count + 1
            if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return nil end
        end
        if count ~= n then return nil end
        return n
    end

    local function oracleTuple(spec, v)
        if type(v) ~= "table" then return false end
        local n = sequenceLength(v, spec.meta)
        if not n then return false end
        local count = #spec.items
        if n > count and not spec.rest then return false end
        local out = {}
        for i = 1, n > count and n or count do
            local itemSpec = spec.items[i] or spec.rest
            local x
            if spec.meta then x = v[i] else x = rawget(v, i) end
            local ok, y = oracle(itemSpec, x)
            if not ok then return false end
            out[i] = y
        end
        return true, out
    end

    local function oracleRecord(spec, v)
        if type(v) ~= "table" then return false end
        local out = {}
        for k, x in next, v do
            local tk = type(k)
            if tk ~= "string" and tk ~= "number" and tk ~= "boolean" then return false end
            if not oracle(spec.key, k) then return false end
            local ok, y = oracle(spec.value, x)
            if not ok then return false end
            out[k] = y
        end
        return true, out
    end

    local function oracleUnion(spec, v)
        for _, variant in ipairs(spec.variants) do
            local ok, out = oracle(variant, v)
            if ok then return true, out end
        end
        return false
    end

    local function oracleDunion(spec, v)
        if type(v) ~= "table" then return false end
        local viaIndex = false
        for _, variant in ipairs(spec.variants) do
            if variant.meta then viaIndex = true end
        end
        local x
        if viaIndex then x = v[spec.key] else x = rawget(v, spec.key) end
        for _, variant in ipairs(spec.variants) do
            local value = variant.fields[1].spec.value
            if type(x) == type(value) and value == x then return oracle(variant, v) end
        end
        return false
    end

    local function oracleLazy(spec, v)
        return oracle(spec.target, v)
    end

    local structuredOracles = {
        object = oracleObject, array = oracleArray, tuple = oracleTuple, record = oracleRecord,
        union = oracleUnion, dunion = oracleDunion, lazy = oracleLazy,
    }

    local function modBounds(spec)
        local min, max, len
        for _, m in ipairs(spec.mods or {}) do
            if m[1] == "min" then min = m[2]
            elseif m[1] == "max" then max = m[2]
            elseif m[1] == "len" then len = m[2]
            else min, max = m[2], m[3] end
        end
        return min, max, len
    end

    local function oracleFixed(spec, v)
        local range = fixedRanges[spec.kind]
        if type(v) ~= "number" or v ~= v or v == huge or v == -huge then return false end
        if v ~= math.floor(v) then return false end
        if spec.strict and math.type and math.type(v) ~= "integer" then return false end
        if v < range[1] or v > range[2] then return false end
        local min, max = modBounds(spec)
        if min and v < min then return false end
        if max and v > max then return false end
        return true
    end

    local function oracleInt64(_, v)
        if type(v) == "number" then
            if v ~= v then return false end
            if math.type and math.type(v) == "integer" then return true end
            if v == huge or v == -huge then return false end
            return v == math.floor(v) and v >= -(2 ^ 53) and v <= 2 ^ 53
        end
        if type(v) == "cdata" and ffi then return ffi.istype("int64_t", v) end
        return false
    end

    local function oracleBytes(spec, v)
        if type(v) ~= "string" then return false end
        local min, max, len = modBounds(spec)
        local n = #v
        if (min and n < min) or (max and n > max) or (len and n ~= len) then return false end
        return true
    end

    local sequencePatterns = {
        "^[\194-\223][\128-\191]",
        "^\224[\160-\191][\128-\191]",
        "^[\225-\236][\128-\191][\128-\191]",
        "^\237[\128-\159][\128-\191]",
        "^[\238-\239][\128-\191][\128-\191]",
        "^\240[\144-\191][\128-\191][\128-\191]",
        "^[\241-\243][\128-\191][\128-\191][\128-\191]",
        "^\244[\128-\143][\128-\191][\128-\191]",
    }

    local function countCharacters(s)
        local i, n, size = 1, 0, #s
        while i <= size do
            if s:byte(i) < 128 then
                i = i + 1
            else
                local stop
                for _, pattern in ipairs(sequencePatterns) do
                    local _, e = s:find(pattern, i)
                    if e then stop = e break end
                end
                if not stop then return nil end
                i = stop + 1
            end
            n = n + 1
        end
        return n
    end

    local function oracleUtf8(spec, v)
        if type(v) ~= "string" then return false end
        local n = countCharacters(v)
        if n == nil then return false end
        local min, max, len = modBounds(spec)
        if (min and n < min) or (max and n > max) or (len and n ~= len) then return false end
        return true
    end

    local function oracleLiteral(spec, v)
        return type(v) == type(spec.value) and v == spec.value
    end

    local function oracleNull(spec, v)
        return rawequal(v, spec.sentinel)
    end

    local function oracleFunc(_, v)
        return type(v) == "function"
    end

    local function oracleUserdata(spec, v)
        if type(v) ~= "userdata" then return false end
        return spec.mt == nil or getmetatable(v) == spec.mt
    end

    local function oracleInstance(spec, v)
        local t = type(v)
        if t ~= "table" and t ~= "userdata" then return false end
        return getmetatable(v) == spec.mt
    end

    local function oracleCdata(spec, v)
        return ffi ~= nil and ffi.istype(spec.ctype, v)
    end

    local function oracleNotNullPtr(spec, v)
        if not ffi then return false end
        local info = cdataInfo[v]
        if not info or not info.ptr or info.null then return false end
        return ffi.istype(spec.ctype, v)
    end

    local leafOracles = {
        int64 = oracleInt64, bytes = oracleBytes, utf8 = oracleUtf8, literal = oracleLiteral,
        null = oracleNull, func = oracleFunc, userdata = oracleUserdata, instanceOf = oracleInstance,
        cdata = oracleCdata, notNullPtr = oracleNotNullPtr,
    }
    for _, name in ipairs(fixedNames) do leafOracles[name] = oracleFixed end

    local function oracleBase(spec, v)
        local leafOracle = leafOracles[spec.kind]
        if leafOracle then return leafOracle(spec, v), v end
        local structured = structuredOracles[spec.kind]
        if structured then
            if needsStructure(spec) then return structured(spec, v) end
            if independent(spec) then return structured(spec, v) and true or false, v end
        end
        return cached(baseSchemas, spec, baseOnly):is(v), v
    end

    oracle = function(spec, v)
        if isPure(spec) and not independent(spec) then
            return cached(pureSchemas, spec, function(x) return x end):is(v), v
        end
        local chain = spec.chain or {}
        local nilKind, nilAt
        if spec.optional then
            nilKind, nilAt = "optional", #chain
        elseif spec.default then
            nilKind, nilAt = "default", spec.default.at
        end
        local x, first
        if v == nil and nilKind then
            first = nilAt + 1
            if nilKind == "default" then
                local value = spec.default.value
                if type(value) == "function" then x = value() else x = value end
            end
        elseif spec.nullable and rawequal(v, spec.nullable.sentinel) then
            first = spec.nullable.at + 1
            x = v
        else
            local ok
            ok, x = oracleBase(spec, v)
            if not ok then return false end
            first = 1
        end
        for i = first, #chain do
            local step = chain[i]
            local ctx = { failed = false, addIssue = function(self) self.failed = true end }
            if step.op == "transform" then
                x = transformDefs[step.def](x, ctx)
                if ctx.failed then return false end
            else
                local pass = refineDefs[step.def](x, ctx)
                if ctx.failed or not pass then return false end
            end
        end
        return true, x
    end

    local function disagreement(schema, data, ok, out, err, expectOk, expectOut)
        if ok ~= expectOk then
            return ("verdict %s, oracle %s"):format(tostring(ok), tostring(expectOk))
        end
        if ok and not same(out, expectOut) then
            return "output differs: " .. show(out) .. " vs oracle " .. show(expectOut)
        end
        if not ok and (out ~= nil or not z.isError(err) or #err.issues < 1) then
            return "failure without a proper error object"
        end
        if schema:is(data) ~= ok then return "is() disagrees with safeParse" end
        if schema._test(data) ~= ok then return "_test disagrees with safeParse" end
        if (schema._check(data, {}, 0, nil) == nil) ~= ok then return "_check disagrees with safeParse" end
        if (pcall(schema.parse, schema, data)) ~= ok then return "parse disagrees with safeParse" end
        if not ok then
            local _, _, again = schema:safeParse(data)
            if again:format() ~= err:format() then return "issues are not deterministic" end
        end
        return nil
    end

    test("fuzz: impure schemas follow the oracle and is() == safeParse ok", function()
        reseed(IMPURE_SEED)
        local cases, accepted, rejected, impure = 0, 0, 0, 0
        for s = 1, IMPURE_SCHEMAS do
            local spec = genSpec(0)
            decorate(spec)
            local schema = build(spec)
            local pure = isPure(spec)
            if not pure then impure = impure + 1 end
            if schema.pure ~= pure then
                error(("schema #%d purity mismatch: %s\nschema: %s"):format(s, tostring(schema.pure), describe(spec)), 0)
            end
            for j = 1, INPUTS do
                local data = genInput(spec)
                local expectOk, expectOut = oracle(spec, data)
                local ran, ok, out, err = pcall(schema.safeParse, schema, data)
                local problem
                if ran then
                    problem = disagreement(schema, data, ok, out, err, expectOk, expectOut)
                else
                    problem = "safeParse raised: " .. tostring(ok)
                end
                if problem then
                    error(("%s\nschema #%d input #%d\nschema: %s\ndata: %s"):format(
                        problem, s, j, describe(spec), show(data)), 0)
                end
                cases = cases + 1
                if ok then accepted = accepted + 1 else rejected = rejected + 1 end
            end
        end
        print(("fuzz impure: %d cases, %d accepted, %d rejected, %d impure schemas"):format(
            cases, accepted, rejected, impure))
        assertEq(cases, IMPURE_SCHEMAS * INPUTS)
        assertTrue(impure >= IMPURE_SCHEMAS / 5)
        assertTrue(accepted >= IMPURE_SCHEMAS / 2)
        assertTrue(rejected >= IMPURE_SCHEMAS / 2)
    end)

    local P4A_SEED = 20261111
    local P4A_SCHEMAS = 500
    local P4A_INPUTS = 40
    local FROM_STRING_SEED = 20261112
    local FROM_STRING_CASES = 6000

    local function expectIssue(spec, v)
        local kind = spec.kind
        local min, max, len = modBounds(spec)
        if fixedRanges[kind] then
            local range = fixedRanges[kind]
            local whole = type(v) == "number" and v == v and v ~= huge and v ~= -huge and v == math.floor(v)
            if whole and spec.strict and math.type and math.type(v) ~= "integer" then whole = false end
            if not whole then return "invalid_type" end
            local lo, hi = range[1], range[2]
            if min and min > lo then lo = min end
            if max and max < hi then hi = max end
            if v < lo then return "too_small", lo end
            if v > hi then return "too_big", hi end
            return nil
        elseif kind == "int64" then
            return "invalid_type"
        end
        local n
        if kind == "bytes" then
            if type(v) ~= "string" then return "invalid_type" end
            n = #v
        else
            if type(v) ~= "string" then return "invalid_type" end
            n = countCharacters(v)
            if n == nil then return "invalid_type" end
        end
        if min and n < min then return "too_small", min end
        if max and n > max then return "too_big", max end
        if len and n ~= len then return n < len and "too_small" or "too_big", len end
        return nil
    end

    test("fuzz: fixed-size integers, int64, bytes and utf8 follow the independent oracles", function()
        reseed(P4A_SEED)
        local cases, accepted, rejected = 0, 0, 0
        for _, kind in ipairs(p4aKinds) do
            for s = 1, P4A_SCHEMAS do
                local spec = leafSpec(kind)
                spec.optional = chance(20)
                local gTest, cTest, cCheck = compileBoth(spec)
                if not z._isGenerated(gTest) then
                    error(("schema #%d fell back to closures: %s"):format(s, describe(spec)), 0)
                end
                for j = 1, P4A_INPUTS do
                    local data = genValid(spec)
                    local want
                    if data == nil then want = spec.optional == true else want = leafOracles[kind](spec, data) end
                    local okG, g = pcall(gTest, data)
                    local okC, c = pcall(cTest, data)
                    local okK, issues = pcall(cCheck, data, {}, 0, nil)
                    if not (okG and okC and okK) or g ~= want or c ~= want or (issues == nil) ~= want then
                        error(("oracle mismatch on schema #%d input #%d\nschema: %s\ndata: %s\n"
                            .. "oracle=%s codegen=%s(%s) closures=%s(%s) check-clean=%s(%s)"):format(
                            s, j, describe(spec), show(data), tostring(want), tostring(g), tostring(okG),
                            tostring(c), tostring(okC), tostring(issues == nil), tostring(okK)), 0)
                    end
                    cases = cases + 1
                    if want then
                        accepted = accepted + 1
                    else
                        rejected = rejected + 1
                        local code, limit = expectIssue(spec, data)
                        local first = issues[1]
                        if first.code ~= code or (limit ~= nil and first.expected ~= limit) then
                            error(("issue mismatch on schema #%d input #%d\nschema: %s\ndata: %s\n"
                                .. "oracle=%s(%s) got=%s(%s)"):format(
                                s, j, describe(spec), show(data), tostring(code), tostring(limit),
                                tostring(first.code), tostring(first.expected)), 0)
                        end
                    end
                end
            end
        end
        print(("fuzz p4a: %d cases, %d accepted, %d rejected"):format(cases, accepted, rejected))
        assertEq(cases, #p4aKinds * P4A_SCHEMAS * P4A_INPUTS)
        assertTrue(accepted >= #p4aKinds * P4A_SCHEMAS)
        assertTrue(rejected >= #p4aKinds * P4A_SCHEMAS)
    end)

    local function digitsOnly(s)
        local start = s:sub(1, 1) == "-" and 2 or 1
        if #s < start then return false end
        for i = start, #s do
            local b = s:byte(i)
            if b < 48 or b > 57 then return false end
        end
        return true
    end

    local function normalizedDecimal(s)
        local negative = s:sub(1, 1) == "-"
        local digits = negative and s:sub(2) or s
        digits = digits:gsub("^0+", "")
        if digits == "" then return "0", false, "0" end
        return (negative and "-" or "") .. digits, negative, digits
    end

    local function fitsInt64(digits, negative)
        if not (nativeInt or ffi) then
            if #digits < 16 then return true end
            if #digits > 16 then return false end
            return digits <= "9007199254740992"
        end
        if #digits < 19 then return true end
        if #digits > 19 then return false end
        return digits <= (negative and "9223372036854775808" or "9223372036854775807")
    end

    test("fuzz: int64 fromString agrees with an independent decimal comparison and keeps every digit", function()
        reseed(FROM_STRING_SEED)
        local schema = z.int64({ fromString = true })
        local alphabet = { "0", "1", "2", "5", "9", "9", "9", "0", "-", "+", ".", " ", "e", "x" }
        local edges = {
            "0", "-0", "1", "-1", "9007199254740991", "9007199254740992", "9007199254740993",
            "-9007199254740993", "9223372036854775806", "9223372036854775807", "9223372036854775808",
            "-9223372036854775807", "-9223372036854775808", "-9223372036854775809", "18446744073709551615",
            "18446744073709551616", "00000000000000000000009223372036854775807", ("9"):rep(400),
            "999999999999999", "9999999999999999", "1000000000000000", "-999999999999999", "-1000000000000000",
        }
        local accepted, rejected = 0, 0
        for i = 1, FROM_STRING_CASES do
            local s
            if i <= #edges then
                s = edges[i]
            elseif chance(70) then
                local parts = {}
                if chance(30) then parts[1] = "-" end
                for _ = 1, rand(25) do parts[#parts + 1] = tostring(chance(35) and 9 or rand(10) - 1) end
                s = table.concat(parts)
            else
                local parts = {}
                for k = 1, rand(7) - 1 do parts[k] = pick(alphabet) end
                s = table.concat(parts)
            end
            local ok, value, err = schema:safeParse(s)
            local want, why = false, "invalid_type"
            if digitsOnly(s) then
                local text, negative, digits = normalizedDecimal(s)
                if fitsInt64(digits, negative) then
                    want = true
                else
                    why = negative and "too_small" or "too_big"
                end
                if ok then
                    local shown
                    if type(value) == "number" and not (math.type and math.type(value) == "integer") then
                        shown = ("%.0f"):format(value)
                    else
                        shown = tostring(value):gsub("LL$", "")
                    end
                    if shown ~= text then
                        error(("fromString %q returned %s, expected %s"):format(s, shown, text), 0)
                    end
                end
            end
            if ok ~= want then
                error(("fromString %q: verdict %s, oracle %s"):format(s, tostring(ok), tostring(want)), 0)
            end
            if ok then
                accepted = accepted + 1
                if ffi then
                    assertTrue(ffi.istype("int64_t", value))
                elseif nativeInt then
                    assertEq(math.type(value), "integer")
                end
            else
                rejected = rejected + 1
                if err.issues[1].code ~= why then
                    error(("fromString %q: code %s, oracle %s"):format(s, err.issues[1].code, why), 0)
                end
            end
            if schema:is(s) ~= want then
                error(("fromString %q: is() disagrees with safeParse"):format(s), 0)
            end
        end
        print(("fuzz fromString: %d cases, %d accepted, %d rejected"):format(accepted + rejected, accepted, rejected))
        assertTrue(accepted >= FROM_STRING_CASES / 10)
        assertTrue(rejected >= FROM_STRING_CASES / 10)
    end)

    local P4B_SEED = 20261113
    local P4B_SCHEMAS = 300
    local P4B_INPUTS = 40

    local function leafInput(spec)
        if (spec.kind == "cdata" or spec.kind == "notNullPtr") and chance(25) then
            return pick(nullMakers)()
        end
        return genValid(spec)
    end

    local function expectedLeaf(spec, v)
        if spec.optional and rawequal(v, nil) then return true end
        if spec.nullable and rawequal(v, spec.nullable.sentinel) then return true end
        return leafOracles[spec.kind](spec, v)
    end

    test("fuzz: literal, null, func, userdata, instanceOf, cdata and notNullPtr follow the independent oracles", function()
        reseed(P4B_SEED)
        local cases, accepted, rejected = 0, 0, 0
        for _, kind in ipairs(p4bKinds) do
            for s = 1, P4B_SCHEMAS do
                local spec = leafSpec(kind)
                spec.optional = chance(25)
                spec.nullable = chance(30) and { at = 0, sentinel = pick(sentinelPool) } or false
                local gTest, cTest, cCheck = compileBoth(spec)
                if not z._isGenerated(gTest) then
                    error(("schema #%d fell back to closures: %s"):format(s, describe(spec)), 0)
                end
                local schema = build(spec)
                for j = 1, P4B_INPUTS do
                    local data = leafInput(spec)
                    local want = expectedLeaf(spec, data)
                    local okG, g = pcall(gTest, data)
                    local okC, c = pcall(cTest, data)
                    local okK, issues = pcall(cCheck, data, {}, 0, nil)
                    local okP, parsed, out = pcall(schema.safeParse, schema, data)
                    if not (okG and okC and okK and okP) or g ~= want or c ~= want or (issues == nil) ~= want
                        or parsed ~= want or (want and not rawequal(out, data)) then
                        error(("oracle mismatch on %s schema #%d input #%d\nschema: %s\ndata: %s\n"
                            .. "oracle=%s codegen=%s(%s) closures=%s(%s) check-clean=%s(%s) safeParse=%s(%s)"):format(
                            kind, s, j, describe(spec), show(data), tostring(want), tostring(g), tostring(okG),
                            tostring(c), tostring(okC), tostring(issues == nil), tostring(okK),
                            tostring(parsed), tostring(okP)), 0)
                    end
                    cases = cases + 1
                    if want then
                        accepted = accepted + 1
                    else
                        rejected = rejected + 1
                        local code = kind == "literal" and "invalid_literal" or "invalid_type"
                        if issues[1].code ~= code then
                            error(("issue mismatch on %s schema #%d input #%d\nschema: %s\ndata: %s\n"
                                .. "oracle=%s got=%s"):format(
                                kind, s, j, describe(spec), show(data), code, tostring(issues[1].code)), 0)
                        end
                    end
                end
            end
        end
        print(("fuzz p4b: %d cases, %d accepted, %d rejected"):format(cases, accepted, rejected))
        assertEq(cases, #p4bKinds * P4B_SCHEMAS * P4B_INPUTS)
        assertTrue(accepted >= #p4bKinds * P4B_SCHEMAS)
        assertTrue(rejected >= #p4bKinds * P4B_SCHEMAS)
    end)

    test("fuzz: the sentinel and the optional marker stay apart on every kind", function()
        reseed(P4B_SEED + 1)
        local kinds = { "string", "number", "integer", "boolean", "int64", "utf8", "any", "null", "func", "userdata" }
        local seen = 0
        for _, kind in ipairs(kinds) do
            for _ = 1, 40 do
                local spec = leafSpec(kind)
                spec.optional = chance(50)
                spec.nullable = chance(50) and { at = 0, sentinel = pick(sentinelPool) } or false
                local schema = build(spec)
                local other = pick(sentinelPool)
                local wantNil = spec.optional == true
                if kind == "any" or kind == "unknown" then wantNil = true end
                if schema:is(nil) ~= wantNil then
                    error(("nil verdict wrong on %s"):format(describe(spec)), 0)
                end
                if spec.nullable then
                    if not schema:is(spec.nullable.sentinel) then
                        error(("sentinel refused on %s"):format(describe(spec)), 0)
                    end
                    seen = seen + 1
                elseif kind ~= "any" and kind ~= "null" and kind ~= "userdata" and schema:is(other) then
                    error(("sentinel accepted without nullable on %s"):format(describe(spec)), 0)
                end
            end
        end
        assertTrue(seen > 100)
    end)
end
