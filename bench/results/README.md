# zigo benchmark results

English · [Français](./README.fr.md)

Output of `bench/run.lua`, one file per runtime: `runtime-<version>.md` (`5.1`, `5.4`, `luajit-2.1`, ...). `.stats/*.lua` holds the raw sidecars and is not committed.

Current scenario: discriminated union of 10 variants (`bench/union.lua`), comparing a hand-written `if/elseif` (U0), sequential closures (U1), codegen with a hash on `kind` (U2), matchigo `compile` on shapes (U3) and matchigo literal fast-path plus codegen (U4).

> [!IMPORTANT]
> Microbenchmarks with cycling inputs measure per-call overhead only. Do not trust absolute numbers from a shared CI runner.

Reproduce from the project root:

```sh
lua build.lua
lua bench/run.lua          # full run
lua bench/run.lua --fast   # smoke run
```

The union scenario reads matchigo-lua from `MATCHIGO_PATH` (default `./matchigo-lua`).
