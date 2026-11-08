local mode, noCodegen
for _, a in ipairs(arg or {}) do
    if a == "dist" then mode = "dist" end
    if a == "--no-codegen" then noCodegen = true end
end
local z
if mode == "dist" then
    z = dofile("dist/zigo.lua")
else
    package.path = "./?.lua;./?/init.lua;" .. package.path
    z = require("zigo")
end

if noCodegen then z.config({ codegen = false }) end

local passed, failed = 0, 0
local failures = {}

local function nanEq(a, b)
    if a == b then return true end
    if type(a) == "number" and type(b) == "number" and a ~= a and b ~= b then return true end
    return false
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. " :: " .. tostring(err)
    end
end

local function assertEq(actual, expected)
    if not nanEq(actual, expected) then
        error(("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
    end
end
local function assertTrue(v)  if not v then error("expected truthy", 2) end end
local function assertFalse(v) if v     then error("expected falsy",  2) end end
local function assertThrows(fn) if pcall(fn) then error("expected throw", 2) end end

local function deepEq(a, b)
    if nanEq(a, b) then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not deepEq(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function show(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    local parts = {}
    for i = 1, #keys do parts[i] = tostring(keys[i]) .. "=" .. show(v[keys[i]]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function assertDeepEq(actual, expected)
    if not deepEq(actual, expected) then
        error(("expected %s, got %s"):format(show(expected), show(actual)), 2)
    end
end

local env = {
    z = z, test = test, assertEq = assertEq, assertTrue = assertTrue,
    assertFalse = assertFalse, assertThrows = assertThrows,
    assertDeepEq = assertDeepEq,
}

dofile("tests/smoke_test.lua")(env)
dofile("tests/primitives_test.lua")(env)
dofile("tests/object_array_test.lua")(env)
dofile("tests/errors_test.lua")(env)
dofile("tests/immutability_test.lua")(env)
dofile("tests/determinism_test.lua")(env)
dofile("tests/traps_test.lua")(env)
dofile("tests/codegen_test.lua")(env)
dofile("tests/impure_test.lua")(env)
dofile("tests/coerce_test.lua")(env)
dofile("tests/union_test.lua")(env)
dofile("tests/tuple_test.lua")(env)
dofile("tests/record_test.lua")(env)
dofile("tests/limits_test.lua")(env)
dofile("tests/lazy_test.lua")(env)
dofile("tests/fuzz_test.lua")(env)
dofile("tests/alloc_test.lua")(env)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
    print("Failures:")
    for i = 1, #failures do
        print("  - " .. failures[i])
    end
    os.exit(1)
end
