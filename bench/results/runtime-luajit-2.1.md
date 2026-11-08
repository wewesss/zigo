# zigo bench — `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-11-08 23:04
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
| `hand-written if-chain` | 1 ns | 0 B | 0/30 | 762.20 M/s | 1 ns..1 ns | 1 ns/1 ns | _(base)_ |
| `zigo codegen` | 1 ns | 0 B | 0/30 | 787.19 M/s | 1 ns..1 ns | 1 ns/1 ns | tie |
| `zigo closures` | 2 ns | 0 B | 0/30 | 660.36 M/s | 1 ns..2 ns | 2 ns/2 ns | 1.15× slower |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 42 ns | 0 B | 0/30 | 23.89 M/s | 40 ns..55 ns | 41 ns/45 ns | _(base)_ |
| `zigo codegen` | 47 ns | 0 B | 0/30 | 21.45 M/s | 44 ns..52 ns | 46 ns/50 ns | 1.11× slower |
| `zigo closures` | 227 ns | 0 B | 0/30 | 4.41 M/s | 211 ns..251 ns | 224 ns/249 ns | 5.42× slower |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 53 ns | 0 B | 0/30 | 18.74 M/s | 50 ns..57 ns | 53 ns/56 ns | _(base)_ |
| `zigo codegen` | 51 ns | 1 B | 0/30 | 19.58 M/s | 49 ns..54 ns | 51 ns/53 ns | tie |
| `zigo closures` | 567 ns | 0 B | 0/30 | 1.76 M/s | 540 ns..610 ns | 570 ns/590 ns | 10.62× slower |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 5.09 µs | 2 B | 0/30 | 196.46 K/s | 4.50 µs..6.40 µs | 5.00 µs/5.70 µs | _(base)_ |
| `zigo codegen` | 8.35 µs | 2 B | 0/30 | 119.81 K/s | 4.80 µs..11.50 µs | 8.55 µs/11.00 µs | 1.64× slower |
| `zigo closures` | 111.83 µs | 2 B | 0/30 | 8.94 K/s | 100.00 µs..143.00 µs | 110.50 µs/135.00 µs | 21.97× slower |

## S5 discriminatedUnion, 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 40 ns | 0 B | 0/30 | 25.21 M/s | 33 ns..55 ns | 37 ns/54 ns | _(base)_ |
| `zigo codegen` | 40 ns | 0 B | 0/30 | 24.87 M/s | 38 ns..43 ns | 40 ns/43 ns | tie |
| `zigo closures` | 160 ns | 0 B | 0/30 | 6.27 M/s | 145 ns..179 ns | 160 ns/173 ns | 4.02× slower |

## S6 invalid early or late (12 fields) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 51 ns | 2 B | 0/30 | 19.46 M/s | 48 ns..55 ns | 51 ns/55 ns | _(base)_ |
| `zigo codegen` | 17 ns | 0 B | 0/30 | 60.23 M/s | 16 ns..18 ns | 17 ns/18 ns | 3.10× faster |
| `zigo closures` | 198 ns | 0 B | 0/30 | 5.04 M/s | 179 ns..239 ns | 192 ns/238 ns | 3.86× slower |
| `zigo safeParse` | 33 ns | 0 B | 0/30 | 30.23 M/s | 30 ns..36 ns | 33 ns/35 ns | 1.55× faster |
| `zigo safeParse, abortEarly` | 34 ns | 0 B | 0/30 | 29.76 M/s | 28 ns..40 ns | 34 ns/39 ns | 1.53× faster |

## S6 invalid early or late (12 fields) - invalid at the first field

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 16 ns | 0 B | 0/30 | 64.39 M/s | 14 ns..19 ns | 15 ns/18 ns | _(base)_ |
| `zigo codegen` | 14 ns | 0 B | 0/30 | 73.55 M/s | 12 ns..16 ns | 13 ns/16 ns | 1.14× faster |
| `zigo closures` | 48 ns | 0 B | 0/30 | 20.78 M/s | 43 ns..59 ns | 47 ns/55 ns | 3.10× slower |
| `zigo safeParse` | 658 ns | 551 B | 0/30 | 1.52 M/s | 490 ns..880 ns | 645 ns/860 ns | 42.37× slower |
| `zigo safeParse, abortEarly` | 378 ns | 545 B | 0/30 | 2.65 M/s | 265 ns..522 ns | 368 ns/493 ns | 24.33× slower |

## S6 invalid early or late (12 fields) - invalid at the last field

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 29 ns | 0 B | 0/30 | 34.35 M/s | 26 ns..32 ns | 29 ns/31 ns | _(base)_ |
| `zigo codegen` | 21 ns | 0 B | 0/30 | 47.89 M/s | 18 ns..23 ns | 21 ns/22 ns | 1.39× faster |
| `zigo closures` | 240 ns | 0 B | 0/30 | 4.17 M/s | 214 ns..277 ns | 239 ns/275 ns | 8.23× slower |
| `zigo safeParse` | 819 ns | 559 B | 0/30 | 1.22 M/s | 610 ns..940 ns | 835 ns/930 ns | 28.14× slower |
| `zigo safeParse, abortEarly` | 808 ns | 559 B | 0/30 | 1.24 M/s | 610 ns..1.01 µs | 785 ns/1.01 µs | 27.77× slower |

## S7 adversarial payload (10 000 potential errors) - invalid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 19.03 µs | 2 B | 0/30 | 52.55 K/s | 12.30 µs..26.20 µs | 18.75 µs/25.00 µs | _(base)_ |
| `zigo codegen` | 16.41 µs | 2 B | 0/30 | 60.94 K/s | 11.80 µs..23.90 µs | 15.15 µs/22.10 µs | 1.16× faster |
| `zigo closures` | 26.91 µs | 3 B | 0/30 | 37.16 K/s | 19.10 µs..34.20 µs | 27.25 µs/32.30 µs | 1.41× slower |
| `zigo safeParse, maxErrors = inf (10 000 issues)` | 4.23 ms | 3.41 MB | 0/30 | 237 /s | 3.19 ms..5.79 ms | 4.14 ms/5.75 ms | 222.18× slower |
| `zigo safeParse, default maxErrors (100)` | 84.83 µs | 34.82 KB | 0/30 | 11.79 K/s | 53.00 µs..115.00 µs | 83.00 µs/110.00 µs | 4.46× slower |
| `zigo safeParse, abortEarly` | 33.42 µs | 570 B | 0/30 | 29.93 K/s | 29.40 µs..46.60 µs | 32.45 µs/37.80 µs | 1.76× slower |

## S9 200 schemas defined, 10 used - cold start

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `define 200 (no compilation)` | 1.84 ms | 1.94 MB | 0/30 | 545 /s | 1.29 ms..2.68 ms | 1.79 ms/2.67 ms | _(base)_ |
| `define 200, validate with 10 (compiled on first use)` | 2.58 ms | 1.94 MB | 0/30 | 387 /s | 2.13 ms..3.11 ms | 2.55 ms/3.06 ms | 1.41× slower |
| `define 200, compile all 200, validate with 10` | 8.58 ms | 3.37 MB | 0/30 | 117 /s | 7.21 ms..9.81 ms | 8.56 ms/9.46 ms | 4.67× slower |
| `define 200, validate with 10 (closures)` | 2.77 ms | 1.92 MB | 0/30 | 361 /s | 2.03 ms..3.43 ms | 2.71 ms/3.37 ms | 1.51× slower |

## S10 boundary object (u8, i32, int64, utf8) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 88 ns | 0 B | 0/30 | 11.32 M/s | 78 ns..98 ns | 88 ns/96 ns | _(base)_ |
| `zigo codegen` | 87 ns | 1 B | 0/30 | 11.47 M/s | 72 ns..101 ns | 89 ns/99 ns | tie |
| `zigo closures` | 221 ns | 0 B | 0/30 | 4.52 M/s | 193 ns..263 ns | 216 ns/252 ns | 2.50× slower |

## Union of 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 11 ns | 0 B | 0/30 | 90.55 M/s | 10 ns..13 ns | 11 ns/12 ns | _(base)_ |
| `U1 closures, sequential` | 36 ns | 0 B | 0/30 | 27.88 M/s | 32 ns..38 ns | 36 ns/38 ns | 3.25× slower |
| `U2 codegen + hash on kind` | 19 ns | 0 B | 0/30 | 52.16 M/s | 15 ns..22 ns | 19 ns/21 ns | 1.74× slower |
| `U3 matchigo compile (shapes)` | 123 ns | 0 B | 0/30 | 8.12 M/s | 113 ns..130 ns | 123 ns/129 ns | 11.16× slower |
| `U4 matchigo fast-path + codegen` | 36 ns | 0 B | 0/30 | 28.06 M/s | 34 ns..40 ns | 35 ns/39 ns | 3.23× slower |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 12 ns | 0 B | 0/30 | 85.11 M/s | 11 ns..13 ns | 12 ns/13 ns | _(base)_ |
| `U1 closures, sequential` | 42 ns | 0 B | 0/30 | 23.83 M/s | 37 ns..45 ns | 42 ns/44 ns | 3.57× slower |
| `U2 codegen + hash on kind` | 21 ns | 0 B | 0/30 | 46.67 M/s | 18 ns..23 ns | 22 ns/23 ns | 1.82× slower |
| `U3 matchigo compile (shapes)` | 125 ns | 0 B | 0/30 | 7.97 M/s | 115 ns..131 ns | 126 ns/129 ns | 10.68× slower |
| `U4 matchigo fast-path + codegen` | 32 ns | 0 B | 0/30 | 31.24 M/s | 28 ns..35 ns | 32 ns/35 ns | 2.72× slower |

## S8 impure schema (default, transform, strip) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written copy` | 221 ns | 351 B | 0/30 | 4.52 M/s | 168 ns..379 ns | 205 ns/331 ns | _(base)_ |
| `zigo safeParse (_parse)` | 531 ns | 447 B | 0/30 | 1.88 M/s | 374 ns..708 ns | 548 ns/672 ns | 2.40× slower |
| `zigo is (_parse, no result kept)` | 561 ns | 445 B | 0/30 | 1.78 M/s | 377 ns..727 ns | 568 ns/677 ns | 2.54× slower |

