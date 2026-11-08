# zigo bench — `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-11-08 21:33
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
| `hand-written if-chain` | 1 ns | 0 B | 0/30 | 785.55 M/s | 1 ns..1 ns | 1 ns/1 ns | _(base)_ |
| `zigo codegen` | 1 ns | 0 B | 0/30 | 767.66 M/s | 1 ns..1 ns | 1 ns/1 ns | tie |
| `zigo closures` | 2 ns | 0 B | 0/30 | 648.23 M/s | 2 ns..2 ns | 2 ns/2 ns | 1.21× slower |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 43 ns | 0 B | 0/30 | 23.04 M/s | 42 ns..49 ns | 43 ns/45 ns | _(base)_ |
| `zigo codegen` | 47 ns | 0 B | 0/30 | 21.23 M/s | 45 ns..54 ns | 47 ns/49 ns | 1.09× slower |
| `zigo closures` | 188 ns | 0 B | 0/30 | 5.31 M/s | 184 ns..195 ns | 188 ns/195 ns | 4.34× slower |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 55 ns | 0 B | 0/30 | 18.02 M/s | 53 ns..67 ns | 55 ns/63 ns | _(base)_ |
| `zigo codegen` | 52 ns | 1 B | 0/30 | 19.05 M/s | 50 ns..56 ns | 52 ns/55 ns | 1.06× faster |
| `zigo closures` | 493 ns | 0 B | 0/30 | 2.03 M/s | 483 ns..518 ns | 490 ns/508 ns | 8.88× slower |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 4.80 µs | 2 B | 0/30 | 208.19 K/s | 4.20 µs..6.40 µs | 4.75 µs/5.40 µs | _(base)_ |
| `zigo codegen` | 4.71 µs | 2 B | 0/30 | 212.27 K/s | 4.45 µs..5.65 µs | 4.63 µs/5.41 µs | tie |
| `zigo closures` | 93.93 µs | 2 B | 0/30 | 10.65 K/s | 86.00 µs..132.00 µs | 93.00 µs/107.00 µs | 19.56× slower |

## S5 discriminatedUnion, 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 33 ns | 0 B | 0/30 | 30.36 M/s | 31 ns..36 ns | 33 ns/36 ns | _(base)_ |
| `zigo codegen` | 36 ns | 0 B | 0/30 | 27.46 M/s | 36 ns..38 ns | 36 ns/38 ns | 1.11× slower |
| `zigo closures` | 137 ns | 0 B | 0/30 | 7.30 M/s | 130 ns..149 ns | 135 ns/145 ns | 4.16× slower |

## S6 invalid early or late (12 fields) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 49 ns | 0 B | 0/30 | 20.24 M/s | 49 ns..51 ns | 49 ns/51 ns | _(base)_ |
| `zigo codegen` | 17 ns | 2 B | 0/30 | 60.24 M/s | 16 ns..18 ns | 17 ns/17 ns | 2.98× faster |
| `zigo closures` | 210 ns | 0 B | 0/30 | 4.77 M/s | 203 ns..218 ns | 209 ns/217 ns | 4.25× slower |
| `zigo safeParse` | 27 ns | 0 B | 0/30 | 37.53 M/s | 26 ns..28 ns | 27 ns/27 ns | 1.85× faster |
| `zigo safeParse, abortEarly` | 27 ns | 0 B | 0/30 | 37.48 M/s | 26 ns..28 ns | 27 ns/28 ns | 1.85× faster |

## S6 invalid early or late (12 fields) - invalid at the first field

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 14 ns | 0 B | 0/30 | 69.86 M/s | 14 ns..15 ns | 14 ns/15 ns | _(base)_ |
| `zigo codegen` | 12 ns | 0 B | 0/30 | 82.51 M/s | 12 ns..13 ns | 12 ns/13 ns | 1.18× faster |
| `zigo closures` | 42 ns | 0 B | 0/30 | 23.64 M/s | 40 ns..47 ns | 42 ns/47 ns | 2.96× slower |
| `zigo safeParse` | 510 ns | 550 B | 0/30 | 1.96 M/s | 460 ns..590 ns | 505 ns/590 ns | 35.65× slower |
| `zigo safeParse, abortEarly` | 293 ns | 545 B | 0/30 | 3.42 M/s | 257 ns..346 ns | 288 ns/330 ns | 20.45× slower |

## S6 invalid early or late (12 fields) - invalid at the last field

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 26 ns | 0 B | 0/30 | 37.77 M/s | 26 ns..27 ns | 26 ns/27 ns | _(base)_ |
| `zigo codegen` | 20 ns | 0 B | 0/30 | 50.92 M/s | 19 ns..20 ns | 20 ns/20 ns | 1.35× faster |
| `zigo closures` | 220 ns | 0 B | 0/30 | 4.56 M/s | 208 ns..254 ns | 214 ns/246 ns | 8.29× slower |
| `zigo safeParse` | 750 ns | 559 B | 0/30 | 1.33 M/s | 620 ns..970 ns | 735 ns/950 ns | 28.34× slower |
| `zigo safeParse, abortEarly` | 687 ns | 559 B | 0/30 | 1.46 M/s | 600 ns..1000 ns | 670 ns/830 ns | 25.93× slower |

## S7 adversarial payload (10 000 potential errors) - invalid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 12.15 µs | 2 B | 0/30 | 82.30 K/s | 11.00 µs..13.90 µs | 11.95 µs/13.70 µs | _(base)_ |
| `zigo codegen` | 11.78 µs | 2 B | 0/30 | 84.89 K/s | 11.20 µs..13.40 µs | 11.65 µs/13.30 µs | tie |
| `zigo closures` | 18.43 µs | 3 B | 0/30 | 54.25 K/s | 17.90 µs..20.20 µs | 18.30 µs/19.40 µs | 1.52× slower |
| `zigo safeParse, maxErrors = inf (10 000 issues)` | 3.28 ms | 3.41 MB | 0/30 | 305 /s | 3.02 ms..5.10 ms | 3.16 ms/3.68 ms | 270.15× slower |
| `zigo safeParse, default maxErrors (100)` | 61.13 µs | 34.82 KB | 0/30 | 16.36 K/s | 52.00 µs..89.00 µs | 60.00 µs/76.00 µs | 5.03× slower |
| `zigo safeParse, abortEarly` | 31.64 µs | 570 B | 0/30 | 31.61 K/s | 29.50 µs..36.00 µs | 31.50 µs/33.70 µs | 2.60× slower |

## S9 200 schemas defined, 10 used - cold start

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `define 200 (no compilation)` | 1.89 ms | 1.94 MB | 0/30 | 530 /s | 1.20 ms..2.89 ms | 1.87 ms/2.37 ms | _(base)_ |
| `define 200, validate with 10 (compiled on first use)` | 2.50 ms | 1.94 MB | 0/30 | 400 /s | 2.01 ms..3.39 ms | 2.42 ms/3.14 ms | 1.32× slower |
| `define 200, compile all 200, validate with 10` | 7.41 ms | 3.38 MB | 0/30 | 135 /s | 6.61 ms..8.78 ms | 7.35 ms/8.72 ms | 3.93× slower |
| `define 200, validate with 10 (closures)` | 2.84 ms | 1.92 MB | 0/30 | 352 /s | 1.84 ms..4.05 ms | 2.61 ms/4.05 ms | 1.50× slower |

## S10 boundary object (u8, i32, int64, utf8) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 79 ns | 0 B | 0/30 | 12.65 M/s | 67 ns..92 ns | 79 ns/88 ns | _(base)_ |
| `zigo codegen` | 73 ns | 0 B | 0/30 | 13.74 M/s | 59 ns..108 ns | 71 ns/94 ns | 1.09× faster |
| `zigo closures` | 143 ns | 0 B | 0/30 | 6.99 M/s | 132 ns..185 ns | 138 ns/184 ns | 1.81× slower |

## Union of 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 24 ns | 0 B | 0/30 | 41.17 M/s | 21 ns..29 ns | 24 ns/27 ns | _(base)_ |
| `U1 closures, sequential` | 54 ns | 0 B | 0/30 | 18.44 M/s | 46 ns..91 ns | 51 ns/76 ns | 2.23× slower |
| `U2 codegen + hash on kind` | 34 ns | 0 B | 0/30 | 29.21 M/s | 30 ns..37 ns | 35 ns/37 ns | 1.41× slower |
| `U3 matchigo compile (shapes)` | 133 ns | 0 B | 0/30 | 7.53 M/s | 125 ns..143 ns | 132 ns/139 ns | 5.47× slower |
| `U4 matchigo fast-path + codegen` | 49 ns | 0 B | 0/30 | 20.50 M/s | 45 ns..51 ns | 49 ns/51 ns | 2.01× slower |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 25 ns | 0 B | 0/30 | 39.29 M/s | 22 ns..27 ns | 26 ns/27 ns | _(base)_ |
| `U1 closures, sequential` | 56 ns | 0 B | 0/30 | 17.96 M/s | 53 ns..58 ns | 56 ns/57 ns | 2.19× slower |
| `U2 codegen + hash on kind` | 38 ns | 0 B | 0/30 | 26.54 M/s | 35 ns..42 ns | 37 ns/40 ns | 1.48× slower |
| `U3 matchigo compile (shapes)` | 133 ns | 0 B | 0/30 | 7.51 M/s | 123 ns..142 ns | 134 ns/140 ns | 5.23× slower |
| `U4 matchigo fast-path + codegen` | 50 ns | 0 B | 0/30 | 19.99 M/s | 48 ns..54 ns | 50 ns/53 ns | 1.97× slower |

## S8 impure schema (default, transform, strip) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written copy` | 630 ns | 353 B | 0/30 | 1.59 M/s | 200 ns..1.10 µs | 650 ns/1.10 µs | _(base)_ |
| `zigo safeParse (_parse)` | 1.23 µs | 431 B | 0/30 | 815.22 K/s | 800 ns..1.60 µs | 1.20 µs/1.60 µs | 1.95× slower |
| `zigo is (_parse, no result kept)` | 507 ns | 431 B | 0/30 | 1.97 M/s | 300 ns..1.60 µs | 400 ns/700 ns | 1.24× faster |

