# zigo bench — `5.4`

**Runtime** : Lua 5.4 (no JIT)
**Generated** : 2026-11-08 14:12
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
| `U0 hand-written if/elseif` | 131 ns | 0 B | 0/30 | 7.65 M/s | 127 ns..151 ns | 129 ns/139 ns | _(base)_ |
| `U1 closures, sequential` | 285 ns | 0 B | 0/30 | 3.51 M/s | 275 ns..305 ns | 284 ns/298 ns | 2.18× slower |
| `U2 codegen + hash on kind` | 119 ns | 0 B | 0/30 | 8.39 M/s | 114 ns..136 ns | 118 ns/132 ns | 1.10× faster |
| `U3 matchigo compile (shapes)` | 1.04 µs | 0 B | 0/30 | 959.39 K/s | 950 ns..1.56 µs | 990 ns/1.32 µs | 7.98× slower |
| `U4 matchigo fast-path + codegen` | 152 ns | 0 B | 0/30 | 6.56 M/s | 124 ns..284 ns | 135 ns/241 ns | 1.17× slower |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 127 ns | 0 B | 0/30 | 7.86 M/s | 118 ns..153 ns | 126 ns/148 ns | _(base)_ |
| `U1 closures, sequential` | 364 ns | 0 B | 0/30 | 2.75 M/s | 323 ns..514 ns | 342 ns/475 ns | 2.86× slower |
| `U2 codegen + hash on kind` | 158 ns | 0 B | 0/30 | 6.33 M/s | 106 ns..315 ns | 144 ns/295 ns | 1.24× slower |
| `U3 matchigo compile (shapes)` | 1.24 µs | 0 B | 0/30 | 809.50 K/s | 1.11 µs..1.63 µs | 1.20 µs/1.41 µs | 9.71× slower |
| `U4 matchigo fast-path + codegen` | 143 ns | 0 B | 0/30 | 6.99 M/s | 119 ns..191 ns | 136 ns/190 ns | 1.12× slower |

