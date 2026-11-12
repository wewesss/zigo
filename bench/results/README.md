# zigo benchmark results

English · [Français](./README.fr.md)

Output of `bench/run.lua`, one file per runtime: `runtime-<version>.md` (`5.1`, `5.4`, `luajit-2.1`, ...). `.stats/*.lua` holds the raw sidecars and is not committed.

Scenarios S1-S4 (`bench/core.lua`, fixtures in `bench/fixtures.lua`) compare a hand-written if-chain, zigo codegen and zigo closures. The hand-written baseline has the same guarantees as the schema: its array checks also reject holes and stray keys. `bench/budgets.lua` holds S2 to P50 <= 1.2x that baseline and < 0.5 B/call.

Union scenario: discriminated union of 10 variants (`bench/union.lua`), comparing a hand-written `if/elseif` (U0), sequential closures (U1), codegen with a hash on `kind` (U2), matchigo `compile` on shapes (U3) and matchigo literal fast-path plus codegen (U4).

> [!IMPORTANT]
> Microbenchmarks with cycling inputs measure per-call overhead only. Do not trust absolute numbers from a shared CI runner.

Reproduce from the project root:

```sh
lua build.lua
lua bench/run.lua          # full run
lua bench/run.lua --fast   # smoke run
```

The union scenario reads matchigo-lua from `MATCHIGO_PATH` (default `./matchigo-lua`).

Comparison against other Lua validators (tableshape, lua-resty-ljsonschema, lshape): [COMPARE.md](./COMPARE.md), run with `lua bench/compare.lua`. It reads the libraries from `ZIGO_COMPARE_PATH` and writes `compare-<runtime>.md`, which is not committed.
