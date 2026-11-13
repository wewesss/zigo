# zigo against other Lua validators

English · [Français](./COMPARE.fr.md)

`bench/compare.lua` times zigo next to three third-party Lua validation libraries on the same fixtures. This page documents the method, the pinned versions, how to install the libraries and what each library can and cannot express. A run writes `bench/results/compare-<runtime>.md`; the committed ones come from the full run summarised below.

## What is compared

Fixtures come from `bench/fixtures.lua`, the ones used by `bench/core.lua`:

| id | fixture |
|---|---|
| S1 | `string():min(3)` |
| S2 | reference schema: 7 fields, nested object, array, enum, optional integer range |
| S3 | nesting depth 8 |
| S4 | array of 1000 objects |
| S5 | discriminated union, 10 variants |

For each fixture, two input sets are timed, cycling through 64 inputs (8 for S4) to defeat constant folding on LuaJIT:

- valid inputs;
- invalid inputs, where the first declared field is invalid (S1: string too short, S2: `id` out of range, S3: outermost `n` not an integer, S4: first row invalid, S5: unknown discriminator).

Rows, in this order:

1. hand-written if-chain (the baseline, the same one `bench/core.lua` uses);
2. zigo `:is`;
3. zigo `:safeParse`;
4. each library's public check call. tableshape has two rows, interpreted (`check_value` on the type) and compiled (`tableshape.codegen`, then `check_value`).

Timing, GC settings and allocation tracking are those of `bench/framework.lua` (calibrated batches, P50 and P99 over samples, bytes allocated per call).

## Results

Full run on 2026-11-13 (`lua bench/compare.lua` and `luajit bench/compare.lua`, Windows 11, Lua 5.4.7 and LuaJIT 2.1.1727870382 from MSYS2, same machine). P50 per call, valid inputs / invalid inputs. Full tables, with P99, allocations and the acceptance column: [compare-5.4.md](./compare-5.4.md), [compare-luajit-2.1.md](./compare-luajit-2.1.md).

| row | S2 on 5.4 | S4 on 5.4 | S5 on 5.4 | S2 on LuaJIT | S4 on LuaJIT | S5 on LuaJIT |
|---|---:|---:|---:|---:|---:|---:|
| hand-written | 500 ns / 75 ns | 107 µs / 13.9 µs | 126 ns / 81 ns | 62 ns / 10 ns | 6.3 µs / 1.14 µs | 48 ns / 23 ns |
| zigo `:is` | 595 ns / 255 ns | 110 µs / 14.2 µs | 181 ns / 124 ns | 72 ns / 27 ns | 8.0 µs / 1.15 µs | 48 ns / 54 ns |
| zigo `:safeParse` | 605 ns / 2.09 µs | 113 µs / 210 µs | 164 ns / 1.27 µs | 88 ns / 400 ns | 4.7 µs / 8.1 µs | 60 ns / 600 ns |
| tableshape (codegen) ¹ | 730 ns / 348 ns | 170 µs / 235 ns | 392 ns / 467 ns | 74 ns / 134 ns | 6.5 µs / 110 ns | 105 ns / 104 ns |
| lua-resty-ljsonschema | 1.50 µs / 1.81 µs | 362 µs / 14.1 µs | 1.52 µs / 7.00 µs | 340 ns / 485 ns | 189 µs / 3.51 µs | 1.13 µs / 5.10 µs |
| lshape ¹ | 6.10 µs / 3.80 µs | 1.68 ms / 1.98 µs | 1.68 µs / 3.74 µs | 1.51 µs / 1.03 µs | 423 µs / 670 ns | 575 ns / 1.48 µs |

¹ `MISMATCH` on S2 and S4: accepts arrays with holes or stray keys that the fixture rejects (see the caveats above). tableshape interpreted is 10 to 20× slower than its codegen and is left out of this summary.

Reading the table:

- **Valid inputs**: zigo is the fastest library on every scenario, within 1.0-1.3× of the hand-written check on 5.4 and level with it on LuaJIT.
- **Invalid inputs, `:is`**: as fast as the hand-written check on S4, and within 1.5-3.3× elsewhere.
- **Invalid inputs, `:safeParse`**: slower than `:is` because it collects every issue with its path (up to `maxErrors`, 100 by default), while tableshape and lshape stop at the first failure and return a string. On S4 (first of 1000 rows invalid) zigo still visits the 999 valid rows; set `abortEarly` to stop at the first issue, or call `:is` first when only the verdict matters.
- LuaJIT timings under about 5 ns (S1 in the full tables) are at the timer resolution and not meaningful.

## Acceptance check

Before timing, every row is run on all valid inputs, on the fixture's invalid list and on the first-field-invalid set. The hand-written baseline is the oracle: a row that classifies an input differently is reported on the console, in the `agrees with baseline` column, in the `guarantees` column (prefixed `MISMATCH`) and in a final "Acceptance mismatches" section. A mismatch does not stop the run and the row is still timed, but it is not a like-for-like comparison: that library does not enforce the whole guarantee set of the fixture.

## Guarantees caveats

The schemas express the same guarantees as zigo wherever the library can: string lengths, integer ranges, enums, optional fields, nested objects with unknown keys allowed (zigo's default), arrays of a given length.

- **Array holes and stray keys.** zigo arrays reject holes and non-sequence keys, and so does the baseline. tableshape walks arrays with `ipairs` and does not check this; lshape accepts some of these inputs depending on the runtime's table border. Both show up as `MISMATCH` rows in S2 and S4. lua-resty-ljsonschema rejects them (it classifies a Lua table as an array from the shape of its keys).
- **Integers.** tableshape has no integer range type; the schemas use `types.range` plus a `types.custom` predicate (`v % 1 == 0`). lshape and lua-resty-ljsonschema have native integer types.
- **String length.** lua-resty-ljsonschema counts UTF-8 characters, the others count bytes. The fixtures are ASCII, so results agree.
- **Discriminated union (S5).** Only lshape has a native one. tableshape (`one_of`) and lua-resty-ljsonschema (`anyOf`) try variants in order, which is how a JSON Schema validator expresses it. This is a difference in what the library offers, not a bug of the schema.
- **Error reporting.** Rows measure the library's normal check call. Invalid-input rows therefore include whatever the library does to build its failure result (zigo `:safeParse` builds issues, tableshape builds a message).
- **Fast runs.** `--fast` uses 5 samples and short warmup. Its output is a smoke test, not a benchmark.

## Pinned versions

| library | version | source |
|---|---|---|
| tableshape | 2.8.0-1 | `luarocks install tableshape` |
| lua-resty-ljsonschema | 1.2.0-2 (with net-url 1.2-1) | `luarocks install lua-resty-ljsonschema` |
| lua-cjson | 2.1.0.10-1 (needed by lua-resty-ljsonschema for its metaschema) | `luarocks install lua-cjson` |
| lshape | 0.3.0, commit `135946790268d51ebbe6f86507722054a8c6ed69` | `git clone https://github.com/ynishi/lshape` |

Dropped after a smoke test:

- `jsonschema` (api7) 0.9.13-0: depends on `lrexlib-pcre`, a C module that needs the PCRE headers; it did not install on the test machine (Windows, MinGW). lua-resty-ljsonschema is the maintained fork that avoids that dependency.
- chotto (aiya000, commit `3f1a22eed5c6344344e7df4e2af101ca3de81cbc`): no minimum length, no numeric range, no strict mode, so it cannot express S1 or S2.

## Install the libraries

The libraries are never vendored in the repository. Install them in a scratch folder (here `$TREE`) and point the benchmark at it:

```sh
TREE=/path/to/scratch/rocks
luarocks --tree "$TREE" install tableshape
luarocks --tree "$TREE" install lua-resty-ljsonschema
luarocks --tree "$TREE" install lua-cjson          # C module, needs a C compiler
git clone https://github.com/ynishi/lshape /path/to/scratch/lshape
git -C /path/to/scratch/lshape checkout 135946790268d51ebbe6f86507722054a8c6ed69
```

`lua-cjson` is compiled for the Lua version `luarocks` targets. To run under LuaJIT, build `cjson` against LuaJIT's headers and import library and keep that `cjson.dll` / `cjson.so` in a separate folder used for the LuaJIT run only. Without `cjson`, lua-resty-ljsonschema rows are skipped with a notice.

## Run

Build zigo, then point the benchmark at the libraries. `ZIGO_COMPARE_PATH` is appended to `package.path` and `ZIGO_COMPARE_CPATH` to `package.cpath` (both optional, standard `?` templates separated by `;`):

```sh
lua build.lua

export ZIGO_COMPARE_PATH="$TREE/share/lua/5.4/?.lua;$TREE/share/lua/5.4/?/init.lua;/path/to/scratch/lshape/?.lua;/path/to/scratch/lshape/?/init.lua"
export ZIGO_COMPARE_CPATH="$TREE/lib/lua/5.4/?.so"   # ?.dll on Windows

lua bench/compare.lua --fast      # smoke run, not authoritative
lua bench/compare.lua             # full run
luajit bench/compare.lua          # full run on LuaJIT (use the LuaJIT-built cjson in ZIGO_COMPARE_CPATH)
```

A library that cannot be loaded is skipped with a printed notice and never fails the run. `bench/run.lua` and `bench/budgets.lua` do not read these variables and are unaffected; the comparison is not part of the performance budgets.

Output goes to `bench/results/compare-<runtime>.md` (`compare-5.4.md`, `compare-luajit-2.1.md`, ...), one file per runtime.
