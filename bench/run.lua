package.path = "./?.lua;./?/init.lua;" .. package.path

local FAST = false
for _, a in ipairs(arg or {}) do
    if a == "--fast" then FAST = true end
end

local b = require("bench.framework")
if FAST then
    b.setDefaults({ samples = 5, warmup = 20, targetMs = 50 })
end

local z = dofile("dist/zigo.lua")

local registerScenarios = assert(loadfile("bench/scenarios.lua"))()
registerScenarios(z, b)

local function ensureDir(path)
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        local winPath = path:gsub("/", "\\")
        os.execute(string.format([[if not exist "%s" mkdir "%s"]], winPath, winPath))
    else
        os.execute(string.format([[mkdir -p "%s"]], path))
    end
end

local stats = b.runAll()

local label      = b.runtimeLabel()
local resultsDir = "bench/results"
local statsDir   = resultsDir .. "/.stats"

ensureDir(resultsDir)
ensureDir(statsDir)

local mdPath    = string.format("%s/runtime-%s.md", resultsDir, label)
local statsPath = string.format("%s/%s.lua", statsDir, label)

local f = assert(io.open(mdPath, "wb"), "Cannot write " .. mdPath)
f:write(b.renderRuntime(stats))
f:close()
print()
print("Wrote " .. mdPath)

b.writeStats(stats, statsPath)
print("Wrote " .. statsPath)
