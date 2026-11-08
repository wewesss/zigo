package.path = "./?.lua;./?/init.lua;" .. package.path

local z = require("zigo")
local fixtures = require("bench.fixtures")

local RATIO_BUDGET = 1.2
local ALLOC_BUDGET = 0.5
local ALLOC_CALLS = 20000
local ALLOC_WARMUP = 5000
local ROUNDS = 41
local WARMUP_PASSES = 300
local BATCH_SECONDS = 0.03

local clock = os.clock
local loader = loadstring or load

local label
if jit then
    label = "luajit-" .. (jit.version:match("(%d+%.%d+)") or "?")
else
    label = _VERSION:match("(%d+%.%d+)") or "?"
end

local runnerSource = [[
return function(fn, inputs, n, passes)
    local hits = 0
    for _ = 1, passes do
        for j = 1, n do
            if fn(inputs[j]) then hits = hits + 1 end
        end
    end
    return hits
end
]]

local function newRunner(name)
    return assert(loader(runnerSource, "=budget-runner-" .. name))()
end

local function median(list)
    table.sort(list)
    local n = #list
    if n % 2 == 1 then return list[(n + 1) / 2] end
    return (list[n / 2] + list[n / 2 + 1]) / 2
end

local function calibrate(run, fn, inputs, n)
    local passes = 50
    while true do
        local t0 = clock()
        run(fn, inputs, n, passes)
        if clock() - t0 >= BATCH_SECONDS then return passes end
        passes = passes * 2
    end
end

local function bytesPerCall(fn, inputs, n)
    local run = newRunner("alloc")
    local best = math.huge
    for _ = 1, 5 do
        run(fn, inputs, n, math.ceil(ALLOC_WARMUP / n))
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        run(fn, inputs, n, math.ceil(ALLOC_CALLS / n))
        local after = collectgarbage("count")
        collectgarbage("restart")
        local per = (after - before) * 1024 / (math.ceil(ALLOC_CALLS / n) * n)
        if per < best then best = per end
        if best < ALLOC_BUDGET then break end
    end
    return best
end

local fixture = fixtures.s2()
local inputs = fixture.inputs
local n = #inputs

local codegen, schema = fixtures.compile(z, true, fixture.build)
if not z._isGenerated(codegen) then
    print("budgets: codegen is not available on this runtime (load missing or rejected)")
    os.exit(1)
end
if not schema.pure then
    print("budgets: the S2 reference schema is not pure")
    os.exit(1)
end
for i = 1, n do
    if codegen(inputs[i]) ~= true or fixture.hand(inputs[i]) ~= true then
        print("budgets: S2 input " .. i .. " is not valid for both variants")
        os.exit(1)
    end
end

local variants = {
    { name = "hand-written if-chain", fn = fixture.hand, run = newRunner("hand"), samples = {} },
    { name = "zigo codegen", fn = codegen, run = newRunner("codegen"), samples = {} },
}

for _, v in ipairs(variants) do
    v.passes = calibrate(v.run, v.fn, inputs, n)
    v.run(v.fn, inputs, n, WARMUP_PASSES)
end
local common = math.max(variants[1].passes, variants[2].passes)

for round = 1, ROUNDS do
    for k = 1, #variants do
        local v = variants[(round + k) % #variants + 1]
        collectgarbage("collect")
        local t0 = clock()
        v.run(v.fn, inputs, n, common)
        v.samples[#v.samples + 1] = (clock() - t0) / (common * n)
    end
end

local hand = median(variants[1].samples)
local gen = median(variants[2].samples)
local ratio = gen / hand
local alloc = bytesPerCall(codegen, inputs, n)

print(("budgets on %s - S2 reference schema, %d valid inputs, %d rounds of %d passes"):format(label, n, ROUNDS, common))
print(("  hand-written if-chain  P50 %7.1f ns/call"):format(hand * 1e9))
print(("  zigo codegen           P50 %7.1f ns/call"):format(gen * 1e9))
print(("  ratio codegen / hand   %.3f   (budget <= %.2f)"):format(ratio, RATIO_BUDGET))
print(("  valid-path allocation  %.3f B/call   (budget < %.2f)"):format(alloc, ALLOC_BUDGET))

local failed = false
if ratio > RATIO_BUDGET then
    print("FAIL: P50 ratio above budget")
    failed = true
end
if alloc >= ALLOC_BUDGET then
    print("FAIL: valid-path allocation above budget")
    failed = true
end
if failed then os.exit(1) end
print("OK: budgets held")
