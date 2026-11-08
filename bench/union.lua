return function(z, b)
    local matchigoPath = os.getenv("MATCHIGO_PATH") or "./matchigo-lua"
    package.path = matchigoPath .. "/?.lua;" .. matchigoPath .. "/?/init.lua;" .. package.path
    local okMatchigo, m = pcall(require, "matchigo")
    if not okMatchigo then
        error("matchigo not found at '" .. matchigoPath .. "' (set MATCHIGO_PATH): " .. tostring(m), 0)
    end

    local P = m.P
    local loadstr = loadstring or load
    local type, huge = type, math.huge

    local NV = 10
    local kinds = {}
    for i = 1, NV do kinds[i] = "k" .. i end

    local function closureVariant(i)
        local kind, min = kinds[i], i
        return function(v)
            if type(v) ~= "table" or v.kind ~= kind then return false end
            local x = v.x
            if type(x) ~= "number" or x % 1 ~= 0 or x ~= x or x == huge or x < min then return false end
            local l = v.label
            if type(l) ~= "string" or #l < 1 or #l > 16 then return false end
            return true
        end
    end

    local function codegenVariant(i)
        local src = ([[
local type, huge = type, math.huge
return function(v)
  local x = v.x
  if type(x) ~= 'number' or x %% 1 ~= 0 or x ~= x or x == huge or x < %d then return false end
  local l = v.label
  if type(l) ~= 'string' or #l < 1 or #l > 16 then return false end
  return true
end]]):format(i)
        return assert(loadstr(src))()
    end

    local function u0(v)
        if type(v) ~= "table" then return false end
        local k = v.kind
        local min
        if k == "k1" then min = 1 elseif k == "k2" then min = 2 elseif k == "k3" then min = 3
        elseif k == "k4" then min = 4 elseif k == "k5" then min = 5 elseif k == "k6" then min = 6
        elseif k == "k7" then min = 7 elseif k == "k8" then min = 8 elseif k == "k9" then min = 9
        elseif k == "k10" then min = 10 else return false end
        local x = v.x
        if type(x) ~= "number" or x % 1 ~= 0 or x ~= x or x == huge or x < min then return false end
        local l = v.label
        if type(l) ~= "string" or #l < 1 or #l > 16 then return false end
        return true
    end

    local seq = {}
    for i = 1, NV do seq[i] = closureVariant(i) end
    local function u1(v)
        for i = 1, NV do if seq[i](v) then return true end end
        return false
    end

    local map = {}
    for i = 1, NV do map[kinds[i]] = codegenVariant(i) end
    local function u2(v)
        if type(v) ~= "table" then return false end
        local t = map[v.kind]
        if t == nil then return false end
        return t(v)
    end

    local rules3 = {}
    for i = 1, NV do
        rules3[i] = {
            with = { kind = kinds[i], x = P.intersection(P.integer, P.gte(i)),
                     label = P.intersection(P.string, P.minLengthStr(1), P.maxLengthStr(16)) },
            handler = true,
        }
    end
    rules3[NV + 1] = { otherwise = false }
    local u3 = m.compile(rules3)

    local rules4 = {}
    for i = 1, NV do
        local t = map[kinds[i]]
        rules4[i] = { with = kinds[i], handler = function() return t end }
    end
    local REJECT = function() return false end
    rules4[NV + 1] = { otherwise = function() return REJECT end }
    local route = m.compile(rules4)
    local function u4(v)
        if type(v) ~= "table" then return false end
        return route(v.kind)(v)
    end

    local VALID, MIXED = {}, {}
    for i = 1, 200 do
        local k = (i % NV) + 1
        VALID[i] = { kind = kinds[k], x = k + i % 7, label = "lbl" .. (i % 13) }
        if i % 5 == 0 then MIXED[i] = { kind = kinds[k], x = 0, label = "" }
        elseif i % 7 == 0 then MIXED[i] = { kind = "zz", x = 1, label = "a" }
        else MIXED[i] = VALID[i] end
    end

    for i = 1, 200 do
        for _, set in ipairs({ VALID, MIXED }) do
            local e = u0(set[i])
            assert(u1(set[i]) == e and u2(set[i]) == e and u3(set[i]) == e and u4(set[i]) == e,
                "union variants disagree on input " .. i)
        end
    end

    local function benches(prefix)
        return {
            { name = "U0 hand-written if/elseif",         fn = u0, key = prefix .. ".u0" },
            { name = "U1 closures, sequential",          fn = u1, key = prefix .. ".u1" },
            { name = "U2 codegen + hash on kind",        fn = u2, key = prefix .. ".u2" },
            { name = "U3 matchigo compile (shapes)",     fn = u3, key = prefix .. ".u3" },
            { name = "U4 matchigo fast-path + codegen",  fn = u4, key = prefix .. ".u4" },
        }
    end

    b.scenario("Union of 10 variants - valid inputs", benches("union.valid"), { inputs = VALID })
    b.scenario("Union of 10 variants - mixed inputs", benches("union.mixed"), { inputs = MIXED })
end
