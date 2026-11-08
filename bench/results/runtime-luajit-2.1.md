# zigo bench — `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-11-08 15:32
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

## S1 string():min(3) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 1 ns | 0 B | 0/30 | 762.78 M/s | 1 ns..1 ns | 1 ns/1 ns | _(base)_ |
| `zigo codegen` | 1 ns | 0 B | 0/30 | 787.19 M/s | 1 ns..1 ns | 1 ns/1 ns | tie |
| `zigo closures` | 2 ns | 0 B | 0/30 | 651.75 M/s | 1 ns..2 ns | 2 ns/2 ns | 1.17× slower |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 43 ns | 0 B | 0/30 | 23.06 M/s | 41 ns..49 ns | 43 ns/46 ns | _(base)_ |
| `zigo codegen` | 45 ns | 1 B | 0/30 | 22.17 M/s | 43 ns..54 ns | 45 ns/47 ns | tie |
| `zigo closures` | 214 ns | 0 B | 0/30 | 4.66 M/s | 207 ns..224 ns | 214 ns/223 ns | 4.95× slower |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 54 ns | 0 B | 0/30 | 18.52 M/s | 52 ns..58 ns | 54 ns/56 ns | _(base)_ |
| `zigo codegen` | 51 ns | 0 B | 0/30 | 19.44 M/s | 50 ns..55 ns | 51 ns/55 ns | tie |
| `zigo closures` | 511 ns | 0 B | 0/30 | 1.96 M/s | 495 ns..558 ns | 507 ns/545 ns | 9.46× slower |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 4.62 µs | 2 B | 0/30 | 216.50 K/s | 4.29 µs..4.98 µs | 4.62 µs/4.94 µs | _(base)_ |
| `zigo codegen` | 5.28 µs | 2 B | 0/30 | 189.27 K/s | 4.50 µs..6.50 µs | 5.10 µs/6.50 µs | 1.14× slower |
| `zigo closures` | 97.10 µs | 2 B | 0/30 | 10.30 K/s | 92.00 µs..105.00 µs | 97.00 µs/101.00 µs | 21.02× slower |

## Union of 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 35 ns | 0 B | 0/30 | 28.69 M/s | 32 ns..39 ns | 34 ns/38 ns | _(base)_ |
| `U1 closures, sequential` | 70 ns | 0 B | 0/30 | 14.30 M/s | 67 ns..78 ns | 69 ns/78 ns | 2.01× slower |
| `U2 codegen + hash on kind` | 39 ns | 0 B | 0/30 | 25.58 M/s | 38 ns..42 ns | 39 ns/41 ns | 1.12× slower |
| `U3 matchigo compile (shapes)` | 274 ns | 0 B | 0/30 | 3.64 M/s | 255 ns..316 ns | 273 ns/299 ns | 7.88× slower |
| `U4 matchigo fast-path + codegen` | 49 ns | 2 B | 0/30 | 20.48 M/s | 45 ns..60 ns | 48 ns/54 ns | 1.40× slower |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 33 ns | 0 B | 0/30 | 30.40 M/s | 32 ns..35 ns | 33 ns/35 ns | _(base)_ |
| `U1 closures, sequential` | 78 ns | 0 B | 0/30 | 12.84 M/s | 74 ns..86 ns | 77 ns/83 ns | 2.37× slower |
| `U2 codegen + hash on kind` | 41 ns | 0 B | 0/30 | 24.13 M/s | 39 ns..47 ns | 41 ns/46 ns | 1.26× slower |
| `U3 matchigo compile (shapes)` | 306 ns | 0 B | 0/30 | 3.27 M/s | 295 ns..334 ns | 304 ns/319 ns | 9.29× slower |
| `U4 matchigo fast-path + codegen` | 49 ns | 0 B | 0/30 | 20.38 M/s | 48 ns..53 ns | 49 ns/52 ns | 1.49× slower |

