# zigo against other Lua validators

English · [Français](./COMPARE.fr.md)

`bench/compare.lua` times zigo next to three third-party Lua validation libraries on the same fixtures. This page documents the method, the pinned versions, how to install the libraries and what each library can and cannot express. **No measured numbers are committed yet**: they are published after the core performance work lands, from a full run. A run writes `bench/results/compare-<runtime>.md` locally; that file is git-ignored.

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
