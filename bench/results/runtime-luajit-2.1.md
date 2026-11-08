# zigo bench — `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-11-08 19:14
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
| `hand-written if-chain` | 1 ns | 0 B | 0/30 | 742.21 M/s | 1 ns..2 ns | 1 ns/2 ns | _(base)_ |
| `zigo codegen` | 1 ns | 0 B | 0/30 | 692.20 M/s | 1 ns..2 ns | 1 ns/2 ns | 1.07× slower |
| `zigo closures` | 2 ns | 0 B | 0/30 | 555.66 M/s | 2 ns..2 ns | 2 ns/2 ns | 1.34× slower |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 61 ns | 1 B | 0/30 | 16.48 M/s | 43 ns..90 ns | 59 ns/82 ns | _(base)_ |
| `zigo codegen` | 63 ns | 1 B | 0/30 | 15.86 M/s | 44 ns..74 ns | 64 ns/73 ns | tie |
| `zigo closures` | 272 ns | 0 B | 0/30 | 3.68 M/s | 229 ns..334 ns | 268 ns/323 ns | 4.48× slower |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 92 ns | 0 B | 0/30 | 10.89 M/s | 81 ns..106 ns | 91 ns/102 ns | _(base)_ |
| `zigo codegen` | 80 ns | 1 B | 0/30 | 12.47 M/s | 69 ns..96 ns | 79 ns/93 ns | 1.15× faster |
| `zigo closures` | 601 ns | 0 B | 0/30 | 1.66 M/s | 510 ns..740 ns | 595 ns/690 ns | 6.54× slower |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 5.54 µs | 2 B | 0/30 | 180.61 K/s | 4.40 µs..7.00 µs | 5.55 µs/6.80 µs | _(base)_ |
| `zigo codegen` | 5.73 µs | 2 B | 0/30 | 174.60 K/s | 4.67 µs..9.23 µs | 5.33 µs/7.07 µs | tie |
| `zigo closures` | 121.67 µs | 2 B | 0/30 | 8.22 K/s | 94.00 µs..146.00 µs | 123.50 µs/144.00 µs | 21.97× slower |

## S5 discriminatedUnion, 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 34 ns | 0 B | 0/30 | 29.04 M/s | 32 ns..40 ns | 34 ns/39 ns | _(base)_ |
| `zigo codegen` | 39 ns | 0 B | 0/30 | 25.56 M/s | 36 ns..47 ns | 39 ns/46 ns | 1.14× slower |
| `zigo closures` | 144 ns | 0 B | 0/30 | 6.94 M/s | 133 ns..170 ns | 141 ns/168 ns | 4.19× slower |

## Union of 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 46 ns | 0 B | 0/30 | 21.80 M/s | 40 ns..56 ns | 43 ns/55 ns | _(base)_ |
| `U1 closures, sequential` | 93 ns | 0 B | 0/30 | 10.75 M/s | 74 ns..112 ns | 93 ns/108 ns | 2.03× slower |
| `U2 codegen + hash on kind` | 63 ns | 2 B | 0/30 | 15.86 M/s | 46 ns..76 ns | 65 ns/75 ns | 1.37× slower |
| `U3 matchigo compile (shapes)` | 323 ns | 0 B | 0/30 | 3.09 M/s | 283 ns..399 ns | 313 ns/363 ns | 7.05× slower |
| `U4 matchigo fast-path + codegen` | 69 ns | 2 B | 0/30 | 14.40 M/s | 56 ns..83 ns | 70 ns/78 ns | 1.51× slower |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 49 ns | 0 B | 0/30 | 20.46 M/s | 42 ns..63 ns | 46 ns/60 ns | _(base)_ |
| `U1 closures, sequential` | 104 ns | 0 B | 0/30 | 9.62 M/s | 88 ns..120 ns | 104 ns/120 ns | 2.13× slower |
| `U2 codegen + hash on kind` | 62 ns | 0 B | 0/30 | 16.12 M/s | 52 ns..74 ns | 60 ns/71 ns | 1.27× slower |
| `U3 matchigo compile (shapes)` | 378 ns | 0 B | 0/30 | 2.65 M/s | 333 ns..430 ns | 376 ns/429 ns | 7.73× slower |
| `U4 matchigo fast-path + codegen` | 71 ns | 0 B | 0/30 | 14.17 M/s | 61 ns..90 ns | 69 ns/83 ns | 1.44× slower |

## S8 impure schema (default, transform, strip) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written copy` | 311 ns | 348 B | 0/30 | 3.22 M/s | 237 ns..451 ns | 290 ns/437 ns | _(base)_ |
| `zigo safeParse (_parse)` | 788 ns | 432 B | 0/30 | 1.27 M/s | 580 ns..1.02 µs | 795 ns/910 ns | 2.54× slower |
| `zigo is (_parse, no result kept)` | 675 ns | 476 B | 0/30 | 1.48 M/s | 470 ns..880 ns | 685 ns/850 ns | 2.17× slower |

