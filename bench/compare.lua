package.path = "./?.lua;./?/init.lua;" .. package.path

local FAST = false
for _, a in ipairs(arg or {}) do
    if a == "--fast" then FAST = true end
end

local libPath = os.getenv("ZIGO_COMPARE_PATH")
if libPath and libPath ~= "" then
    package.path = package.path .. ";" .. libPath
end
local libCpath = os.getenv("ZIGO_COMPARE_CPATH")
if libCpath and libCpath ~= "" then
    package.cpath = package.cpath .. ";" .. libCpath
end

local b = require("bench.framework")
if FAST then
    b.setDefaults({ samples = 5, warmup = 20, targetMs = 50 })
end

local z = dofile("dist/zigo.lua")
local fixtures = require("bench.fixtures")
local scenarios = require("bench.compare_fixtures").all()
local registry = require("bench.compare_libs")

local MAX_LISTED = 5

local loaded, skipped, versions = {}, {}, {}

for _, lib in ipairs(registry.libraries) do
    local ok, err = pcall(require, lib.module)
    if not ok then
        local reason = tostring(err):match("^[^\n]*")
        skipped[#skipped + 1] = lib.id .. ": " .. reason
        print(("compare: skipping %s (%s). Set ZIGO_COMPARE_PATH and ZIGO_COMPARE_CPATH."):format(lib.id, reason))
    else
        versions[#versions + 1] = lib.id .. " " .. lib.version()
        for _, variant in ipairs(lib.variants) do
            local usable, why = true, nil
            if variant.module then usable, why = pcall(require, variant.module) end
            local builders
            if usable then usable, builders = pcall(variant.builders) end
            if usable then
                loaded[#loaded + 1] = { id = lib.id, label = variant.label, builders = builders }
            else
                local reason = tostring(why or builders):match("^[^\n]*")
                skipped[#skipped + 1] = variant.label .. ": " .. reason
                print(("compare: skipping %s (%s)"):format(variant.label, reason))
            end
        end
    end
end

local function listIndexes(prefix, indexes)
    local parts = {}
    for i = 1, math.min(#indexes, MAX_LISTED) do parts[i] = prefix .. indexes[i] end
    local text = table.concat(parts, ",")
    if #indexes > MAX_LISTED then text = text .. ",+" .. (#indexes - MAX_LISTED) end
    return text
end

local function acceptance(fn, hand, valid, invalid, early)
    local errored = 0
    local function run(v)
        local ok, res = pcall(fn, v)
        if not ok then
            errored = errored + 1
            return false
        end
        return res and true or false
    end
    local function scan(list, expectOf)
        local agree, wrongAccept, wrongReject = 0, {}, {}
        for i = 1, #list do
            local expected = expectOf(list[i], i)
            local got = run(list[i])
            if got == expected then
                agree = agree + 1
            elseif got then
                wrongAccept[#wrongAccept + 1] = i
            else
                wrongReject[#wrongReject + 1] = i
            end
        end
        return agree, wrongAccept, wrongReject
    end
    local function fromHand(v) return hand(v) and true or false end
    local function mustBe(expected, label)
        return function(v, i)
            if fromHand(v) ~= expected then
                error(("fixture bug: the hand-written baseline disagrees with %s input #%d"):format(label, i), 0)
            end
            return expected
        end
    end

    local vOk, _, vReject = scan(valid, mustBe(true, "valid"))
    local iOk, iAccept, iReject = scan(invalid, function(v) return fromHand(v) end)
    local eOk, eAccept = scan(early, mustBe(false, "first-field invalid"))
    local summary = ("valid %d/%d, invalid %d/%d, first-field invalid %d/%d"):format(
        vOk, #valid, iOk, #invalid, eOk, #early)

    local problems = {}
    local function add(prefix, list, indexPrefix)
        if #list > 0 then problems[#problems + 1] = prefix .. " " .. listIndexes(indexPrefix, list) end
    end
    add("rejects valid", vReject, "#")
    add("rejects what the baseline accepts, invalid list", iReject, "#")
    add("accepts invalid", iAccept, "#")
    add("accepts first-field invalid", eAccept, "#")
    if errored > 0 then problems[#problems + 1] = errored .. " calls raised" end
    return summary, problems
end

local meta = {}
local mismatches = {}

local zigoNotes = {
    s1 = "string min length",
    s2 = "unknown keys allowed; integer ranges; dense arrays (holes and stray keys rejected)",
    s3 = "unknown keys allowed; integers checked",
    s4 = "unknown keys allowed; integers checked; dense arrays (holes and stray keys rejected)",
    s5 = "unknown keys allowed; integers checked; discriminated union",
}

for _, scn in ipairs(scenarios) do
    local f = scn.fixture
    local _, schema = fixtures.compile(z, true, f.build)

    local rows = {
        { id = "hand", name = "hand-written if-chain", fn = f.hand, notes = "reference" },
        {
            id = "is",
            name = "zigo :is",
            fn = function(v) return schema:is(v) end,
            notes = zigoNotes[scn.id],
        },
        {
            id = "parse",
            name = "zigo :safeParse",
            fn = function(v) return (schema:safeParse(v)) end,
            notes = zigoNotes[scn.id] .. "; builds issues on failure",
        },
    }

    for _, lib in ipairs(loaded) do
        local build = lib.builders[scn.id]
        local ok, fn, notes = pcall(build)
        if ok then
            rows[#rows + 1] = { id = lib.id .. "." .. lib.label:gsub("[^%w]+", "_"), name = lib.label, fn = fn, notes = notes }
        else
            local reason = tostring(fn):match("^[^\n]*")
            print(("compare: skipping %s on %s (%s)"):format(lib.label, f.name, reason))
            skipped[#skipped + 1] = lib.label .. " on " .. scn.id:upper() .. ": " .. reason
        end
    end

    for _, row in ipairs(rows) do
        local summary, problems = acceptance(row.fn, f.hand, f.inputs, f.invalid, scn.early)
        local guarantees = row.notes or ""
        if #problems > 0 then
            guarantees = "MISMATCH (" .. table.concat(problems, "; ") .. "); " .. guarantees
            mismatches[#mismatches + 1] = ("%s / %s: %s"):format(f.name, row.name, table.concat(problems, "; "))
            print(("compare: MISMATCH %s / %s: %s"):format(f.name, row.name, table.concat(problems, "; ")))
        end
        row.checks = summary
        row.guarantees = guarantees
    end

    local sets = {
        { label = "valid inputs", inputs = f.inputs, key = "valid" },
        { label = "invalid inputs, " .. scn.earlyLabel, inputs = scn.early, key = "early" },
    }
    for _, set in ipairs(sets) do
        local benches = {}
        for i, row in ipairs(rows) do
            local key = scn.id .. "." .. set.key .. "." .. row.id
            benches[i] = { name = row.name, fn = row.fn, key = key }
            meta[key] = row
        end
        b.scenario(f.name .. " - " .. set.label, benches, { inputs = set.inputs })
    end
end

local stats = b.runAll()

local function escape(s) return (s:gsub("|", "\\|")) end

local function render()
    local lines = {}
    local function emit(s) lines[#lines + 1] = s or "" end

    emit("# zigo comparison bench - `" .. stats.meta.label .. "`")
    emit()
    emit("**Runtime** : " .. stats.meta.runtime)
    emit("**Generated** : " .. stats.meta.generated)
    emit(string.format("**Config** : %d samples, %d warmup, %.0fms calibration target%s",
        stats.meta.samples, stats.meta.warmup, stats.meta.targetMs,
        FAST and " (fast run, not authoritative)" or ""))
    emit("**Libraries** : zigo " .. tostring(z._VERSION) .. (#versions > 0 and ", " or "") .. table.concat(versions, ", "))
    if #skipped > 0 then
        emit("**Skipped** : " .. escape(table.concat(skipped, "; ")))
    end
    emit()
    emit("> [!IMPORTANT]")
    emit("> Generated file, not committed. Read `COMPARE.md` for the method and the guarantees caveats before quoting a number.")
    emit()
    emit("The `agrees with baseline` column counts how many fixture inputs each row classified as the hand-written baseline does. A row marked MISMATCH does not enforce every guarantee of the fixture, so its timing is not a like-for-like comparison.")
    emit()

    for _, g in ipairs(stats.groups) do
        emit("## " .. g.name)
        emit()
        emit("| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |")
        emit("|---|---:|---:|---:|---:|---:|---|---|")
        local baseline = g.benches[1].avg
        for i, r in ipairs(g.benches) do
            local row = meta[r.key]
            local rel = i == 1 and "_(base)_" or b.fmtRel(r.avg / baseline)
            emit(string.format("| `%s` | %s | %s | %s | %s | %s | %s | %s |",
                escape(r.name), b.fmtTime(r.avg), b.fmtTime(r.p50), b.fmtTime(r.p99),
                b.fmtBytes(r.alloc), rel, escape(row.checks), escape(row.guarantees)))
        end
        emit()
    end

    if #mismatches > 0 then
        emit("## Acceptance mismatches")
        emit()
        for _, m in ipairs(mismatches) do emit("- " .. escape(m)) end
        emit()
    end

    return table.concat(lines, "\n") .. "\n"
end

local function ensureDir(path)
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        local winPath = path:gsub("/", "\\")
        os.execute(string.format([[if not exist "%s" mkdir "%s"]], winPath, winPath))
    else
        os.execute(string.format([[mkdir -p "%s"]], path))
    end
end

local resultsDir = "bench/results"
ensureDir(resultsDir)
local mdPath = string.format("%s/compare-%s.md", resultsDir, b.runtimeLabel())
local f = assert(io.open(mdPath, "wb"), "Cannot write " .. mdPath)
f:write(render())
f:close()

print()
if #mismatches > 0 then
    print(("compare: %d acceptance mismatch(es), listed above and in the report"):format(#mismatches))
end
print("Wrote " .. mdPath)
