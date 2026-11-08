local mode = arg and arg[1]
local z
if mode == "dist" then
    z = dofile("dist/zigo.lua")
else
    package.path = "./?.lua;./?/init.lua;" .. package.path
    z = require("zigo")
end

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

local env = {
    z = z, test = test, assertEq = assertEq, assertTrue = assertTrue,
    assertFalse = assertFalse, assertThrows = assertThrows,
}

dofile("tests/smoke_test.lua")(env)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
    print("Failures:")
    for i = 1, #failures do
        print("  - " .. failures[i])
    end
    os.exit(1)
end
