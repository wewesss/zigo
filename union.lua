-- Bench : union discriminée de 10 variantes sur `kind`.
-- Question : est-ce que matchigo fait gagner du runtime à validigo ?
--
--   U0 if/elseif à la main sur kind            (borne basse)
--   U1 closures, essai séquentiel              (union naïve)
--   U2 codegen + table de hachage sur kind     (validigo autonome)
--   U3 matchigo m.compile, règles = shapes     (matchigo comme moteur d'union)
--   U4 matchigo m.compile sur v.kind littéral  (fast-path O(1) de matchigo) → test codegen
--
-- Usage : <lua> union.lua <chemin matchigo-lua>

local MATCHIGO = arg[1]
package.path = MATCHIGO .. "/?.lua;" .. MATCHIGO .. "/?/init.lua;" .. package.path
local m = require("matchigo")
local P = m.P
local loadstr = loadstring or load
local type, sfind, huge = type, string.find, math.huge

local NV = 10
local kinds = {}
for i = 1, NV do kinds[i] = "k" .. i end

-- variante i : { kind = "ki", x = entier >= i, label = string min 1 max 16 }
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

-- U0
local function hand(v)
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

-- U1
local seq = {}
for i = 1, NV do seq[i] = closureVariant(i) end
local function u1(v)
    for i = 1, NV do if seq[i](v) then return true end end
    return false
end

-- U2
local map = {}
for i = 1, NV do map[kinds[i]] = codegenVariant(i) end
local function u2(v)
    if type(v) ~= "table" then return false end
    local t = map[v.kind]
    if t == nil then return false end
    return t(v)
end

-- U3 : matchigo, une règle par variante (shape + raffinements)
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

-- U4 : fast-path littéral de matchigo sur v.kind, puis test codegen
local rules4 = {}
for i = 1, NV do local t = map[kinds[i]]; rules4[i] = { with = kinds[i], handler = function() return t end } end
local REJECT = function() return false end
rules4[NV + 1] = { otherwise = function() return REJECT end }
local route = m.compile(rules4)
local function u4(v)
    if type(v) ~= "table" then return false end
    return route(v.kind)(v)
end

-- données : kinds uniformément répartis, 80 % valides
local VALID, MIXED = {}, {}
for i = 1, 200 do
    local k = (i % NV) + 1
    VALID[i] = { kind = kinds[k], x = k + i % 7, label = "lbl" .. (i % 13) }
    if i % 5 == 0 then MIXED[i] = { kind = kinds[k], x = 0, label = "" }        -- invalide
    elseif i % 7 == 0 then MIXED[i] = { kind = "zz", x = 1, label = "a" }     -- kind inconnu
    else MIXED[i] = VALID[i] end
end

-- cohérence
for i = 1, 200 do
    for _, set in ipairs({ VALID, MIXED }) do
        local e = hand(set[i])
        assert(u1(set[i]) == e and u2(set[i]) == e and (u3(set[i]) == e) and u4(set[i]) == e, "incohérence " .. i)
    end
end

-- timer / stats (identique à proto.lua)
local now, TIMER = os.clock, "os.clock"
if jit then
    local ffi = require("ffi")
    ffi.cdef [[ typedef struct { long tv_sec; long tv_nsec; } ts_t; int clock_gettime(int, ts_t*); ]]
    local ts = ffi.new("ts_t")
    now = function() ffi.C.clock_gettime(1, ts); return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9 end
    TIMER = "clock_gettime"
end
local SINK
local function pct(s, p) return s[math.max(1, math.ceil(#s * p))] end
local function hot(fn, inputs, samples, batch)
    local n = #inputs
    for i = 1, 5000 do SINK = fn(inputs[i % n + 1]) end
    local res, j = {}, 0
    for s = 1, samples do
        local t0 = now()
        for _ = 1, batch do j = j % n + 1; SINK = fn(inputs[j]) end
        res[s] = (now() - t0) / batch * 1e9
    end
    table.sort(res)
    collectgarbage("collect"); collectgarbage("stop")
    local b0 = collectgarbage("count")
    for i = 1, 20000 do SINK = fn(inputs[i % n + 1]) end
    local bytes = (collectgarbage("count") - b0) * 1024 / 20000
    collectgarbage("restart")
    return pct(res, .5), pct(res, .99), bytes
end

local BATCH = jit and 50 or 200
print(("## Union 10 variantes — %s — %s — lots de %d"):format(jit and jit.version or _VERSION, TIMER, BATCH))
print("")
print("| Variante | Valides P50 | Valides P99 | Mixte P50 | Mixte P99 | octets/appel |")
print("|---|---:|---:|---:|---:|---:|")
for _, c in ipairs({
    { "U0 if/elseif main", hand }, { "U1 closures séquentiel", u1 },
    { "U2 codegen + hash (autonome)", u2 }, { "U3 matchigo compile (shapes)", u3 },
    { "U4 matchigo fast-path + codegen", u4 },
}) do
    local a50, a99, b = hot(c[2], VALID, 3000, BATCH)
    local m50, m99 = hot(c[2], MIXED, 3000, BATCH)
    print(("| %s | %.0f | %.0f | %.0f | %.0f | %.1f |"):format(c[1], a50, a99, m50, m99, b))
end
