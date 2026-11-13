# zigo bench — `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-11-13 01:58
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
| `hand-written if-chain` | 1 ns | 0 B | 0/30 | 767.66 M/s | 1 ns..1 ns | 1 ns/1 ns | _(base)_ |
| `zigo codegen` | 1 ns | 0 B | 0/30 | 769.03 M/s | 1 ns..1 ns | 1 ns/1 ns | tie |
| `zigo closures` | 2 ns | 0 B | 0/30 | 642.40 M/s | 1 ns..2 ns | 2 ns/2 ns | 1.19× slower |
| `zigo :is (public)` | 11 ns | 0 B | 0/30 | 87.72 M/s | 11 ns..13 ns | 11 ns/13 ns | 8.75× slower |
| `zigo :safeParse (public)` | 17 ns | 0 B | 0/30 | 59.34 M/s | 14 ns..20 ns | 17 ns/20 ns | 12.94× slower |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 83 ns | 2 B | 0/30 | 12.05 M/s | 49 ns..136 ns | 83 ns/103 ns | _(base)_ |
| `zigo codegen` | 55 ns | 1 B | 0/30 | 18.09 M/s | 48 ns..67 ns | 54 ns/66 ns | 1.50× faster |
| `zigo closures` | 262 ns | 0 B | 0/30 | 3.81 M/s | 232 ns..317 ns | 260 ns/301 ns | 3.16× slower |
| `zigo :is (public)` | 75 ns | 1 B | 0/30 | 13.29 M/s | 61 ns..98 ns | 74 ns/91 ns | 1.10× faster |
| `zigo :safeParse (public)` | 68 ns | 2 B | 0/30 | 14.61 M/s | 60 ns..92 ns | 63 ns/85 ns | 1.21× faster |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 68 ns | 0 B | 0/30 | 14.75 M/s | 65 ns..74 ns | 67 ns/71 ns | _(base)_ |
| `zigo codegen` | 65 ns | 1 B | 0/30 | 15.29 M/s | 63 ns..78 ns | 65 ns/69 ns | tie |
| `zigo closures` | 533 ns | 0 B | 0/30 | 1.87 M/s | 500 ns..590 ns | 530 ns/580 ns | 7.87× slower |
| `zigo :is (public)` | 73 ns | 1 B | 0/30 | 13.64 M/s | 68 ns..84 ns | 72 ns/83 ns | 1.08× slower |
| `zigo :safeParse (public)` | 83 ns | 1 B | 0/30 | 12.00 M/s | 73 ns..99 ns | 85 ns/94 ns | 1.23× slower |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 6.44 µs | 2 B | 0/30 | 155.36 K/s | 4.80 µs..7.50 µs | 6.40 µs/7.40 µs | _(base)_ |
| `zigo codegen` | 6.34 µs | 2 B | 0/30 | 157.81 K/s | 4.90 µs..7.70 µs | 6.40 µs/7.30 µs | tie |
| `zigo closures` | 92.23 µs | 2 B | 0/30 | 10.84 K/s | 88.00 µs..108.00 µs | 90.00 µs/102.00 µs | 14.33× slower |
| `zigo :is (public)` | 5.11 µs | 2 B | 0/30 | 195.55 K/s | 4.58 µs..7.27 µs | 4.90 µs/6.22 µs | 1.26× faster |
| `zigo :safeParse (public)` | 6.09 µs | 3 B | 0/30 | 164.29 K/s | 4.50 µs..7.50 µs | 6.15 µs/7.40 µs | 1.06× faster |

## S5 discriminatedUnion, 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 67 ns | 3 B | 0/30 | 14.99 M/s | 54 ns..84 ns | 65 ns/79 ns | _(base)_ |
| `zigo codegen` | 9 ns | 0 B | 0/30 | 108.54 M/s | 8 ns..11 ns | 9 ns/10 ns | 7.24× faster |
| `zigo closures` | 64 ns | 0 B | 0/30 | 15.73 M/s | 59 ns..74 ns | 63 ns/69 ns | tie |
| `zigo :is (public)` | 17 ns | 0 B | 0/30 | 59.89 M/s | 15 ns..21 ns | 16 ns/19 ns | 3.99× faster |
| `zigo :safeParse (public)` | 19 ns | 0 B | 0/30 | 52.67 M/s | 17 ns..23 ns | 19 ns/22 ns | 3.51× faster |

## S6 invalid early or late (12 fields) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 31 ns | 0 B | 0/30 | 32.50 M/s | 27 ns..41 ns | 31 ns/35 ns | _(base)_ |
| `zigo codegen` | 46 ns | 0 B | 0/30 | 21.64 M/s | 31 ns..69 ns | 46 ns/68 ns | 1.50× slower |
| `zigo closures` | 232 ns | 0 B | 0/30 | 4.30 M/s | 217 ns..274 ns | 227 ns/264 ns | 7.56× slower |
| `zigo :is (public)` | 41 ns | 0 B | 0/30 | 24.48 M/s | 38 ns..47 ns | 41 ns/44 ns | 1.33× slower |
| `zigo :safeParse (public)` | 48 ns | 0 B | 0/30 | 20.92 M/s | 42 ns..52 ns | 48 ns/52 ns | 1.55× slower |
| `zigo safeParse` | 42 ns | 0 B | 0/30 | 23.90 M/s | 40 ns..47 ns | 41 ns/46 ns | 1.36× slower |
| `zigo safeParse, abortEarly` | 66 ns | 0 B | 0/30 | 15.24 M/s | 45 ns..104 ns | 58 ns/100 ns | 2.13× slower |

## S6 invalid early or late (12 fields) - invalid at the first field

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 27 ns | 0 B | 0/30 | 36.88 M/s | 24 ns..32 ns | 27 ns/32 ns | _(base)_ |
| `zigo codegen` | 28 ns | 0 B | 0/30 | 35.48 M/s | 26 ns..34 ns | 28 ns/32 ns | tie |
| `zigo closures` | 60 ns | 0 B | 0/30 | 16.62 M/s | 54 ns..91 ns | 59 ns/71 ns | 2.22× slower |
| `zigo :is (public)` | 36 ns | 0 B | 0/30 | 28.13 M/s | 33 ns..45 ns | 34 ns/44 ns | 1.31× slower |
| `zigo :safeParse (public)` | 658 ns | 550 B | 0/30 | 1.52 M/s | 500 ns..890 ns | 620 ns/880 ns | 24.26× slower |
| `zigo safeParse` | 1.08 µs | 549 B | 0/30 | 929.37 K/s | 830 ns..1.41 µs | 1.03 µs/1.41 µs | 39.69× slower |
| `zigo safeParse, abortEarly` | 372 ns | 545 B | 0/30 | 2.69 M/s | 320 ns..525 ns | 342 ns/518 ns | 13.72× slower |

## S6 invalid early or late (12 fields) - invalid at the last field

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 41 ns | 0 B | 0/30 | 24.44 M/s | 34 ns..55 ns | 39 ns/52 ns | _(base)_ |
| `zigo codegen` | 60 ns | 0 B | 0/30 | 16.70 M/s | 39 ns..101 ns | 54 ns/96 ns | 1.46× slower |
| `zigo closures` | 246 ns | 0 B | 0/30 | 4.07 M/s | 219 ns..290 ns | 242 ns/290 ns | 6.01× slower |
| `zigo :is (public)` | 88 ns | 0 B | 0/30 | 11.34 M/s | 82 ns..108 ns | 85 ns/105 ns | 2.15× slower |
| `zigo :safeParse (public)` | 806 ns | 546 B | 0/30 | 1.24 M/s | 660 ns..1.21 µs | 700 ns/1.15 µs | 19.71× slower |
| `zigo safeParse` | 1.16 µs | 545 B | 0/30 | 861.33 K/s | 860 ns..1.64 µs | 1.14 µs/1.55 µs | 28.37× slower |
| `zigo safeParse, abortEarly` | 1.18 µs | 545 B | 0/30 | 848.90 K/s | 830 ns..1.50 µs | 1.18 µs/1.48 µs | 28.79× slower |

## S7 adversarial payload (10 000 potential errors) - invalid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 15.96 µs | 1 B | 0/30 | 62.67 K/s | 11.60 µs..21.50 µs | 15.20 µs/21.40 µs | _(base)_ |
| `zigo codegen` | 13.81 µs | 1 B | 0/30 | 72.43 K/s | 11.40 µs..19.40 µs | 13.40 µs/17.00 µs | 1.16× faster |
| `zigo closures` | 24.64 µs | 1 B | 0/30 | 40.58 K/s | 18.50 µs..35.20 µs | 24.25 µs/29.50 µs | 1.54× slower |
| `zigo :is (public)` | 16.45 µs | 0 B | 0/30 | 60.80 K/s | 11.70 µs..24.50 µs | 14.30 µs/23.10 µs | tie |
| `zigo :safeParse (public)` | 78.33 µs | 34.82 KB | 0/30 | 12.77 K/s | 54.00 µs..130.00 µs | 78.00 µs/105.00 µs | 4.91× slower |
| `zigo safeParse, maxErrors = inf (10 000 issues)` | 4.08 ms | 3.41 MB | 0/30 | 245 /s | 3.37 ms..5.43 ms | 3.95 ms/4.73 ms | 255.92× slower |
| `zigo safeParse, default maxErrors (100)` | 73.77 µs | 34.82 KB | 0/30 | 13.56 K/s | 54.00 µs..104.00 µs | 71.50 µs/103.00 µs | 4.62× slower |
| `zigo safeParse, abortEarly` | 36.68 µs | 569 B | 0/30 | 27.26 K/s | 30.20 µs..49.60 µs | 36.40 µs/45.30 µs | 2.30× slower |

## S9 200 schemas defined, 10 used - cold start

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `define 200 (no compilation)` | 2.71 ms | 1.94 MB | 0/30 | 370 /s | 2.03 ms..3.85 ms | 2.58 ms/3.55 ms | _(base)_ |
| `define 200, validate with 10 (compiled on first use)` | 2.61 ms | 1.94 MB | 0/30 | 383 /s | 1.93 ms..3.89 ms | 2.41 ms/3.74 ms | tie |
| `define 200, compile all 200, validate with 10` | 9.77 ms | 3.40 MB | 0/30 | 102 /s | 7.99 ms..11.60 ms | 9.73 ms/10.97 ms | 3.61× slower |
| `define 200, validate with 10 (closures)` | 2.82 ms | 1.92 MB | 0/30 | 355 /s | 1.72 ms..3.64 ms | 2.88 ms/3.53 ms | tie |

## S10 boundary object (u8, i32, int64, utf8) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 76 ns | 0 B | 0/30 | 13.18 M/s | 66 ns..98 ns | 74 ns/90 ns | _(base)_ |
| `zigo codegen` | 89 ns | 1 B | 0/30 | 11.28 M/s | 69 ns..103 ns | 91 ns/99 ns | 1.17× slower |
| `zigo closures` | 169 ns | 0 B | 0/30 | 5.92 M/s | 137 ns..193 ns | 173 ns/186 ns | 2.23× slower |
| `zigo :is (public)` | 79 ns | 1 B | 0/30 | 12.72 M/s | 66 ns..109 ns | 74 ns/108 ns | tie |
| `zigo :safeParse (public)` | 84 ns | 1 B | 0/30 | 11.97 M/s | 65 ns..109 ns | 79 ns/105 ns | 1.10× slower |

## Union of 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 10 ns | 0 B | 0/30 | 100.91 M/s | 9 ns..11 ns | 10 ns/11 ns | _(base)_ |
| `U1 closures, sequential` | 34 ns | 0 B | 0/30 | 29.39 M/s | 31 ns..38 ns | 34 ns/38 ns | 3.43× slower |
| `U2 codegen + hash on kind` | 17 ns | 0 B | 0/30 | 57.77 M/s | 15 ns..23 ns | 17 ns/22 ns | 1.75× slower |
| `U3 matchigo compile (shapes)` | 309 ns | 0 B | 0/30 | 3.24 M/s | 269 ns..355 ns | 305 ns/353 ns | 31.14× slower |
| `U4 matchigo fast-path + codegen` | 31 ns | 0 B | 0/30 | 31.78 M/s | 25 ns..35 ns | 32 ns/35 ns | 3.18× slower |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 11 ns | 0 B | 0/30 | 92.76 M/s | 9 ns..12 ns | 11 ns/12 ns | _(base)_ |
| `U1 closures, sequential` | 37 ns | 0 B | 0/30 | 27.01 M/s | 33 ns..42 ns | 36 ns/41 ns | 3.43× slower |
| `U2 codegen + hash on kind` | 19 ns | 0 B | 0/30 | 53.37 M/s | 15 ns..23 ns | 19 ns/22 ns | 1.74× slower |
| `U3 matchigo compile (shapes)` | 356 ns | 0 B | 0/30 | 2.81 M/s | 305 ns..579 ns | 353 ns/424 ns | 32.99× slower |
| `U4 matchigo fast-path + codegen` | 29 ns | 0 B | 0/30 | 34.68 M/s | 24 ns..57 ns | 27 ns/42 ns | 2.68× slower |

## S8 impure schema (default, transform, strip) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written copy` | 202 ns | 349 B | 0/30 | 4.94 M/s | 176 ns..264 ns | 190 ns/261 ns | _(base)_ |
| `zigo safeParse (_parse)` | 337 ns | 272 B | 0/30 | 2.96 M/s | 280 ns..470 ns | 320 ns/460 ns | 1.67× slower |
| `zigo is (_parse, no result kept)` | 383 ns | 432 B | 0/30 | 2.61 M/s | 200 ns..600 ns | 400 ns/600 ns | 1.90× slower |

