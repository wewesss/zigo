# zigo bench — `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-11-08 20:21
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
| `hand-written if-chain` | 1 ns | 0 B | 0/30 | 779.83 M/s | 1 ns..1 ns | 1 ns/1 ns | _(base)_ |
| `zigo codegen` | 1 ns | 0 B | 0/30 | 781.66 M/s | 1 ns..1 ns | 1 ns/1 ns | tie |
| `zigo closures` | 2 ns | 0 B | 0/30 | 643.50 M/s | 2 ns..2 ns | 2 ns/2 ns | 1.21× slower |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 45 ns | 0 B | 0/30 | 22.35 M/s | 41 ns..55 ns | 44 ns/50 ns | _(base)_ |
| `zigo codegen` | 45 ns | 0 B | 0/30 | 21.98 M/s | 44 ns..51 ns | 45 ns/47 ns | tie |
| `zigo closures` | 331 ns | 1 B | 0/30 | 3.02 M/s | 315 ns..362 ns | 328 ns/356 ns | 7.39× slower |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 55 ns | 0 B | 0/30 | 18.05 M/s | 52 ns..62 ns | 55 ns/60 ns | _(base)_ |
| `zigo codegen` | 55 ns | 1 B | 0/30 | 18.30 M/s | 51 ns..61 ns | 54 ns/58 ns | tie |
| `zigo closures` | 261 ns | 0 B | 0/30 | 3.83 M/s | 253 ns..317 ns | 259 ns/264 ns | 4.71× slower |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 4.45 µs | 2 B | 0/30 | 224.74 K/s | 4.23 µs..4.90 µs | 4.42 µs/4.74 µs | _(base)_ |
| `zigo codegen` | 5.40 µs | 3 B | 0/30 | 185.31 K/s | 5.10 µs..5.89 µs | 5.36 µs/5.86 µs | 1.21× slower |
| `zigo closures` | 49.60 µs | 2 B | 0/30 | 20.16 K/s | 46.00 µs..55.00 µs | 49.00 µs/55.00 µs | 11.15× slower |

## S5 discriminatedUnion, 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 9 ns | 0 B | 0/30 | 105.93 M/s | 9 ns..10 ns | 9 ns/10 ns | _(base)_ |
| `zigo codegen` | 14 ns | 0 B | 0/30 | 69.91 M/s | 14 ns..16 ns | 14 ns/15 ns | 1.52× slower |
| `zigo closures` | 80 ns | 0 B | 0/30 | 12.46 M/s | 78 ns..87 ns | 80 ns/84 ns | 8.50× slower |

## S6 invalid early or late (12 fields) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 29 ns | 0 B | 0/30 | 34.58 M/s | 28 ns..30 ns | 29 ns/30 ns | _(base)_ |
| `zigo codegen` | 33 ns | 0 B | 0/30 | 30.33 M/s | 31 ns..40 ns | 32 ns/39 ns | 1.14× slower |
| `zigo closures` | 228 ns | 0 B | 0/30 | 4.38 M/s | 219 ns..247 ns | 228 ns/235 ns | 7.89× slower |
| `zigo safeParse` | 40 ns | 0 B | 0/30 | 24.80 M/s | 39 ns..42 ns | 40 ns/41 ns | 1.39× slower |
| `zigo safeParse, abortEarly` | 42 ns | 0 B | 0/30 | 23.67 M/s | 40 ns..52 ns | 41 ns/52 ns | 1.46× slower |

## S6 invalid early or late (12 fields) - invalid at the first field

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 23 ns | 0 B | 0/30 | 43.32 M/s | 22 ns..26 ns | 23 ns/26 ns | _(base)_ |
| `zigo codegen` | 29 ns | 0 B | 0/30 | 34.24 M/s | 24 ns..42 ns | 25 ns/39 ns | 1.27× slower |
| `zigo closures` | 56 ns | 0 B | 0/30 | 18.01 M/s | 53 ns..63 ns | 55 ns/58 ns | 2.41× slower |
| `zigo safeParse` | 504 ns | 550 B | 0/30 | 1.98 M/s | 470 ns..550 ns | 500 ns/540 ns | 21.83× slower |
| `zigo safeParse, abortEarly` | 265 ns | 545 B | 0/30 | 3.78 M/s | 251 ns..291 ns | 262 ns/287 ns | 11.47× slower |

## S6 invalid early or late (12 fields) - invalid at the last field

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 29 ns | 0 B | 0/30 | 34.46 M/s | 28 ns..30 ns | 29 ns/30 ns | _(base)_ |
| `zigo codegen` | 32 ns | 0 B | 0/30 | 30.94 M/s | 31 ns..35 ns | 32 ns/34 ns | 1.11× slower |
| `zigo closures` | 232 ns | 0 B | 0/30 | 4.32 M/s | 222 ns..251 ns | 232 ns/247 ns | 7.99× slower |
| `zigo safeParse` | 637 ns | 559 B | 0/30 | 1.57 M/s | 590 ns..790 ns | 620 ns/750 ns | 21.96× slower |
| `zigo safeParse, abortEarly` | 650 ns | 559 B | 0/30 | 1.54 M/s | 600 ns..770 ns | 640 ns/740 ns | 22.41× slower |

## S7 adversarial payload (10 000 potential errors) - invalid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 11.93 µs | 2 B | 0/30 | 83.82 K/s | 11.00 µs..14.10 µs | 11.80 µs/13.50 µs | _(base)_ |
| `zigo codegen` | 11.56 µs | 2 B | 0/30 | 86.53 K/s | 10.90 µs..13.80 µs | 11.35 µs/12.70 µs | tie |
| `zigo closures` | 18.27 µs | 3 B | 0/30 | 54.74 K/s | 17.60 µs..21.80 µs | 18.05 µs/19.50 µs | 1.53× slower |
| `zigo safeParse, maxErrors = inf (10 000 issues)` | 3.05 ms | 3.41 MB | 0/30 | 328 /s | 2.91 ms..3.60 ms | 3.00 ms/3.32 ms | 255.43× slower |
| `zigo safeParse, default maxErrors (100)` | 58.57 µs | 34.82 KB | 0/30 | 17.07 K/s | 52.00 µs..73.00 µs | 57.00 µs/68.00 µs | 4.91× slower |
| `zigo safeParse, abortEarly` | 31.65 µs | 570 B | 0/30 | 31.60 K/s | 29.50 µs..48.40 µs | 30.95 µs/33.90 µs | 2.65× slower |

## S9 200 schemas defined, 10 used - cold start

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `define 200 (no compilation)` | 1.88 ms | 1.94 MB | 0/30 | 531 /s | 1.20 ms..2.57 ms | 1.86 ms/2.47 ms | _(base)_ |
| `define 200, validate with 10 (compiled on first use)` | 2.79 ms | 1.94 MB | 0/30 | 358 /s | 1.86 ms..5.50 ms | 2.60 ms/4.66 ms | 1.48× slower |
| `define 200, compile all 200, validate with 10` | 7.88 ms | 3.37 MB | 0/30 | 127 /s | 6.89 ms..10.68 ms | 7.64 ms/10.19 ms | 4.18× slower |
| `define 200, validate with 10 (closures)` | 2.58 ms | 1.92 MB | 0/30 | 387 /s | 1.72 ms..3.46 ms | 2.51 ms/3.40 ms | 1.37× slower |

## Union of 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 10 ns | 0 B | 0/30 | 100.94 M/s | 9 ns..12 ns | 10 ns/12 ns | _(base)_ |
| `U1 closures, sequential` | 33 ns | 0 B | 0/30 | 30.61 M/s | 30 ns..35 ns | 33 ns/35 ns | 3.30× slower |
| `U2 codegen + hash on kind` | 17 ns | 0 B | 0/30 | 59.54 M/s | 15 ns..22 ns | 16 ns/21 ns | 1.70× slower |
| `U3 matchigo compile (shapes)` | 270 ns | 0 B | 0/30 | 3.71 M/s | 252 ns..316 ns | 267 ns/301 ns | 27.21× slower |
| `U4 matchigo fast-path + codegen` | 27 ns | 0 B | 0/30 | 36.57 M/s | 26 ns..30 ns | 27 ns/29 ns | 2.76× slower |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 10 ns | 0 B | 0/30 | 100.64 M/s | 8 ns..12 ns | 10 ns/12 ns | _(base)_ |
| `U1 closures, sequential` | 38 ns | 0 B | 0/30 | 26.02 M/s | 36 ns..40 ns | 38 ns/40 ns | 3.87× slower |
| `U2 codegen + hash on kind` | 19 ns | 0 B | 0/30 | 51.53 M/s | 16 ns..22 ns | 20 ns/21 ns | 1.95× slower |
| `U3 matchigo compile (shapes)` | 342 ns | 0 B | 0/30 | 2.93 M/s | 316 ns..369 ns | 340 ns/363 ns | 34.37× slower |
| `U4 matchigo fast-path + codegen` | 30 ns | 0 B | 0/30 | 33.18 M/s | 26 ns..33 ns | 30 ns/33 ns | 3.03× slower |

## S8 impure schema (default, transform, strip) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written copy` | 330 ns | 366 B | 0/30 | 3.03 M/s | 0 ns..700 ns | 300 ns/600 ns | _(base)_ |
| `zigo safeParse (_parse)` | 390 ns | 438 B | 0/30 | 2.56 M/s | 200 ns..600 ns | 400 ns/600 ns | 1.18× slower |
| `zigo is (_parse, no result kept)` | 460 ns | 429 B | 0/30 | 2.17 M/s | 363 ns..605 ns | 451 ns/574 ns | 1.40× slower |

