# zigo bench — `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-11-08 14:13
**Config** : 30 samples, 200 warmup, 50ms calibration target

> [!IMPORTANT]
> **Reading these numbers in context.** Microbenches measure the
> *abstraction's* per-call overhead in tight loops with cycling
> inputs — that's the point, not a flaw.
>
> In most production code, Lua compute runs in **nanoseconds**
> while the work around it (a SQL query, an HTTP call, a file
> read, a queue pop) runs in **milliseconds**. A `2× slower` row
> here is ~50–200 ns extra per call — orders of magnitude
> below the noise floor of any external IO.
>
> **Where it does matter** : real-time framing contexts (game
> engines like LÖVE/Defold, ~16 ms frame budget at 60 Hz),
> high-frequency event loops (OpenResty under load), or any tight
> inner loop with no IO. In those, **the alloc column matters
> more than the ns column** — sustained per-call allocation
> causes GC pauses that *will* eat your frame budget. Hot paths
> with `alloc = 0 B` are GC-safe regardless of which implementation
> you pick.
>
> Pick on readability + maintainability + your runtime's actual
> allocation pressure. The bench tells you what a call costs ;
> only your profiler tells you whether it matters for *your* app.

Each scenario cycles through varying inputs to defeat JIT constant
folding ; the cycling cost is uniform across all benches in a
scenario, so ratios stay accurate even on LuaJIT.

## Union of 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 7 ns | 0 B | 0/30 | 138.44 M/s | 7 ns..8 ns | 7 ns/7 ns | _(base)_ |
| `U1 closures, sequential` | 33 ns | 0 B | 0/30 | 30.71 M/s | 31 ns..39 ns | 32 ns/39 ns | 4.51× slower |
| `U2 codegen + hash on kind` | 15 ns | 0 B | 0/30 | 67.37 M/s | 12 ns..19 ns | 14 ns/18 ns | 2.05× slower |
| `U3 matchigo compile (shapes)` | 90 ns | 0 B | 0/30 | 11.13 M/s | 77 ns..119 ns | 87 ns/118 ns | 12.44× slower |
| `U4 matchigo fast-path + codegen` | 29 ns | 0 B | 0/30 | 34.98 M/s | 22 ns..49 ns | 27 ns/44 ns | 3.96× slower |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 18 ns | 0 B | 0/30 | 55.13 M/s | 17 ns..21 ns | 18 ns/20 ns | _(base)_ |
| `U1 closures, sequential` | 49 ns | 0 B | 0/30 | 20.31 M/s | 46 ns..58 ns | 48 ns/57 ns | 2.71× slower |
| `U2 codegen + hash on kind` | 16 ns | 0 B | 0/30 | 60.73 M/s | 14 ns..19 ns | 16 ns/19 ns | 1.10× faster |
| `U3 matchigo compile (shapes)` | 114 ns | 0 B | 0/30 | 8.78 M/s | 96 ns..128 ns | 115 ns/126 ns | 6.28× slower |
| `U4 matchigo fast-path + codegen` | 24 ns | 0 B | 0/30 | 41.25 M/s | 22 ns..30 ns | 24 ns/29 ns | 1.34× slower |

