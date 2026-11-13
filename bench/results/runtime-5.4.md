# zigo bench — `5.4`

**Runtime** : Lua 5.4 (no JIT)
**Generated** : 2026-11-13 01:45
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
| `hand-written if-chain` | 50 ns | 0 B | 0/30 | 19.82 M/s | 47 ns..56 ns | 50 ns/55 ns | _(base)_ |
| `zigo codegen` | 55 ns | 0 B | 0/30 | 18.16 M/s | 47 ns..72 ns | 52 ns/70 ns | 1.09× slower |
| `zigo closures` | 76 ns | 0 B | 0/30 | 13.17 M/s | 60 ns..91 ns | 77 ns/87 ns | 1.50× slower |
| `zigo :is (public)` | 83 ns | 0 B | 0/30 | 12.06 M/s | 70 ns..99 ns | 83 ns/97 ns | 1.64× slower |
| `zigo :safeParse (public)` | 81 ns | 0 B | 0/30 | 12.36 M/s | 67 ns..124 ns | 77 ns/115 ns | 1.60× slower |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 602 ns | 0 B | 0/30 | 1.66 M/s | 517 ns..689 ns | 606 ns/687 ns | _(base)_ |
| `zigo codegen` | 607 ns | 0 B | 0/30 | 1.65 M/s | 540 ns..740 ns | 600 ns/710 ns | tie |
| `zigo closures` | 1.53 µs | 0 B | 0/30 | 653.88 K/s | 1.18 µs..2.15 µs | 1.50 µs/1.84 µs | 2.54× slower |
| `zigo :is (public)` | 783 ns | 0 B | 0/30 | 1.28 M/s | 640 ns..1.48 µs | 735 ns/910 ns | 1.30× slower |
| `zigo :safeParse (public)` | 829 ns | 0 B | 0/30 | 1.21 M/s | 570 ns..1.25 µs | 855 ns/970 ns | 1.38× slower |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 570 ns | 0 B | 0/30 | 1.75 M/s | 438 ns..723 ns | 577 ns/687 ns | _(base)_ |
| `zigo codegen` | 628 ns | 0 B | 0/30 | 1.59 M/s | 490 ns..1.53 µs | 585 ns/780 ns | 1.10× slower |
| `zigo closures` | 1.57 µs | 1 B | 0/30 | 637.21 K/s | 1.21 µs..1.96 µs | 1.52 µs/1.91 µs | 2.75× slower |
| `zigo :is (public)` | 766 ns | 0 B | 0/30 | 1.31 M/s | 570 ns..1.47 µs | 760 ns/900 ns | 1.34× slower |
| `zigo :safeParse (public)` | 790 ns | 0 B | 0/30 | 1.27 M/s | 720 ns..1.21 µs | 780 ns/830 ns | 1.39× slower |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 151.03 µs | 0 B | 0/30 | 6.62 K/s | 119.00 µs..189.00 µs | 153.50 µs/172.00 µs | _(base)_ |
| `zigo codegen` | 177.83 µs | 0 B | 0/30 | 5.62 K/s | 135.00 µs..232.00 µs | 172.00 µs/230.00 µs | 1.18× slower |
| `zigo closures` | 500.00 µs | 0 B | 0/30 | 2.00 K/s | 300.00 µs..670.00 µs | 500.00 µs/610.00 µs | 3.31× slower |
| `zigo :is (public)` | 169.50 µs | 0 B | 0/30 | 5.90 K/s | 120.00 µs..204.00 µs | 174.00 µs/201.00 µs | 1.12× slower |
| `zigo :safeParse (public)` | 172.00 µs | 0 B | 0/30 | 5.81 K/s | 115.00 µs..215.00 µs | 180.00 µs/215.00 µs | 1.14× slower |

## S5 discriminatedUnion, 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 173 ns | 0 B | 0/30 | 5.77 M/s | 156 ns..192 ns | 174 ns/190 ns | _(base)_ |
| `zigo codegen` | 197 ns | 0 B | 0/30 | 5.07 M/s | 174 ns..219 ns | 197 ns/215 ns | 1.14× slower |
| `zigo closures` | 422 ns | 0 B | 0/30 | 2.37 M/s | 370 ns..463 ns | 428 ns/445 ns | 2.43× slower |
| `zigo :is (public)` | 251 ns | 0 B | 0/30 | 3.99 M/s | 217 ns..676 ns | 238 ns/258 ns | 1.45× slower |
| `zigo :safeParse (public)` | 222 ns | 0 B | 0/30 | 4.50 M/s | 169 ns..305 ns | 221 ns/267 ns | 1.28× slower |

## S6 invalid early or late (12 fields) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 585 ns | 0 B | 0/30 | 1.71 M/s | 510 ns..740 ns | 570 ns/740 ns | _(base)_ |
| `zigo codegen` | 559 ns | 0 B | 0/30 | 1.79 M/s | 470 ns..650 ns | 555 ns/640 ns | tie |
| `zigo closures` | 1.41 µs | 0 B | 0/30 | 709.72 K/s | 1.15 µs..1.74 µs | 1.38 µs/1.71 µs | 2.41× slower |
| `zigo :is (public)` | 765 ns | 0 B | 0/30 | 1.31 M/s | 580 ns..990 ns | 745 ns/920 ns | 1.31× slower |
| `zigo :safeParse (public)` | 860 ns | 0 B | 0/30 | 1.16 M/s | 620 ns..1.40 µs | 865 ns/1.12 µs | 1.47× slower |
| `zigo safeParse` | 872 ns | 0 B | 0/30 | 1.15 M/s | 690 ns..1.17 µs | 820 ns/1.13 µs | 1.49× slower |
| `zigo safeParse, abortEarly` | 732 ns | 0 B | 0/30 | 1.37 M/s | 510 ns..1.34 µs | 700 ns/1.19 µs | 1.25× slower |

## S6 invalid early or late (12 fields) - invalid at the first field

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 97 ns | 0 B | 0/30 | 10.32 M/s | 83 ns..116 ns | 97 ns/108 ns | _(base)_ |
| `zigo codegen` | 109 ns | 0 B | 0/30 | 9.21 M/s | 79 ns..131 ns | 115 ns/128 ns | 1.12× slower |
| `zigo closures` | 164 ns | 0 B | 0/30 | 6.10 M/s | 130 ns..257 ns | 163 ns/201 ns | 1.69× slower |
| `zigo :is (public)` | 137 ns | 0 B | 0/30 | 7.32 M/s | 118 ns..187 ns | 134 ns/154 ns | 1.41× slower |
| `zigo :safeParse (public)` | 5.61 µs | 568 B | 0/30 | 178.10 K/s | 3.05 µs..8.34 µs | 6.15 µs/8.15 µs | 57.96× slower |
| `zigo safeParse` | 2.79 µs | 568 B | 0/30 | 358.59 K/s | 2.32 µs..3.70 µs | 2.73 µs/3.51 µs | 28.79× slower |
| `zigo safeParse, abortEarly` | 1.17 µs | 568 B | 0/30 | 852.03 K/s | 980 ns..1.65 µs | 1.13 µs/1.58 µs | 12.12× slower |

## S6 invalid early or late (12 fields) - invalid at the last field

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 402 ns | 0 B | 0/30 | 2.49 M/s | 336 ns..498 ns | 404 ns/485 ns | _(base)_ |
| `zigo codegen` | 441 ns | 0 B | 0/30 | 2.27 M/s | 334 ns..512 ns | 445 ns/512 ns | 1.10× slower |
| `zigo closures` | 1.11 µs | 0 B | 0/30 | 898.20 K/s | 910 ns..1.39 µs | 1.11 µs/1.38 µs | 2.77× slower |
| `zigo :is (public)` | 453 ns | 0 B | 0/30 | 2.21 M/s | 366 ns..530 ns | 445 ns/522 ns | 1.13× slower |
| `zigo :safeParse (public)` | 3.63 µs | 568 B | 0/30 | 275.86 K/s | 2.72 µs..4.28 µs | 3.65 µs/4.13 µs | 9.01× slower |
| `zigo safeParse` | 4.06 µs | 568 B | 0/30 | 246.61 K/s | 2.52 µs..5.26 µs | 4.28 µs/5.25 µs | 10.08× slower |
| `zigo safeParse, abortEarly` | 3.16 µs | 568 B | 0/30 | 316.69 K/s | 2.68 µs..4.07 µs | 3.05 µs/3.89 µs | 7.85× slower |

## S7 adversarial payload (10 000 potential errors) - invalid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 161.90 µs | 0 B | 0/30 | 6.18 K/s | 135.00 µs..218.00 µs | 155.50 µs/218.00 µs | _(base)_ |
| `zigo codegen` | 192.70 µs | 0 B | 0/30 | 5.19 K/s | 136.00 µs..242.00 µs | 198.00 µs/221.00 µs | 1.19× slower |
| `zigo closures` | 446.33 µs | 0 B | 0/30 | 2.24 K/s | 400.00 µs..610.00 µs | 430.00 µs/560.00 µs | 2.76× slower |
| `zigo :is (public)` | 163.37 µs | 0 B | 0/30 | 6.12 K/s | 134.00 µs..219.00 µs | 157.50 µs/215.00 µs | tie |
| `zigo :safeParse (public)` | 844.67 µs | 35.06 KB | 0/30 | 1.18 K/s | 670.00 µs..1.06 ms | 830.00 µs/1.02 ms | 5.22× slower |
| `zigo safeParse, maxErrors = inf (10 000 issues)` | 18.90 ms | 3.45 MB | 0/30 | 53 /s | 12.47 ms..37.39 ms | 17.12 ms/32.23 ms | 116.76× slower |
| `zigo safeParse, default maxErrors (100)` | 897.33 µs | 35.06 KB | 0/30 | 1.11 K/s | 700.00 µs..1.00 ms | 930.00 µs/1.00 ms | 5.54× slower |
| `zigo safeParse, abortEarly` | 706.33 µs | 600 B | 0/30 | 1.42 K/s | 550.00 µs..830.00 µs | 705.00 µs/830.00 µs | 4.36× slower |

## S9 200 schemas defined, 10 used - cold start

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `define 200 (no compilation)` | 5.75 ms | 1.84 MB | 0/30 | 174 /s | 4.33 ms..7.91 ms | 5.53 ms/7.84 ms | _(base)_ |
| `define 200, validate with 10 (compiled on first use)` | 11.31 ms | 1.86 MB | 0/30 | 88 /s | 8.11 ms..21.23 ms | 10.99 ms/17.31 ms | 1.97× slower |
| `define 200, compile all 200, validate with 10` | 24.55 ms | 4.15 MB | 0/30 | 41 /s | 19.60 ms..61.83 ms | 22.45 ms/37.23 ms | 4.27× slower |
| `define 200, validate with 10 (closures)` | 9.12 ms | 1.80 MB | 0/30 | 110 /s | 7.90 ms..14.87 ms | 8.89 ms/10.23 ms | 1.59× slower |

## S10 boundary object (u8, i32, int64, utf8) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 380 ns | 0 B | 0/30 | 2.63 M/s | 368 ns..403 ns | 376 ns/402 ns | _(base)_ |
| `zigo codegen` | 347 ns | 0 B | 0/30 | 2.88 M/s | 337 ns..370 ns | 346 ns/362 ns | 1.10× faster |
| `zigo closures` | 546 ns | 0 B | 0/30 | 1.83 M/s | 530 ns..580 ns | 545 ns/580 ns | 1.44× slower |
| `zigo :is (public)` | 365 ns | 0 B | 0/30 | 2.74 M/s | 353 ns..388 ns | 363 ns/382 ns | tie |
| `zigo :safeParse (public)` | 378 ns | 0 B | 0/30 | 2.64 M/s | 366 ns..391 ns | 377 ns/390 ns | tie |

## Union of 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 132 ns | 0 B | 0/30 | 7.56 M/s | 128 ns..142 ns | 132 ns/138 ns | _(base)_ |
| `U1 closures, sequential` | 298 ns | 0 B | 0/30 | 3.36 M/s | 279 ns..353 ns | 290 ns/324 ns | 2.25× slower |
| `U2 codegen + hash on kind` | 123 ns | 0 B | 0/30 | 8.15 M/s | 115 ns..137 ns | 121 ns/131 ns | 1.08× faster |
| `U3 matchigo compile (shapes)` | 620 ns | 0 B | 0/30 | 1.61 M/s | 580 ns..830 ns | 605 ns/670 ns | 4.69× slower |
| `U4 matchigo fast-path + codegen` | 136 ns | 0 B | 0/30 | 7.33 M/s | 129 ns..147 ns | 137 ns/146 ns | tie |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 124 ns | 0 B | 0/30 | 8.04 M/s | 118 ns..140 ns | 123 ns/138 ns | _(base)_ |
| `U1 closures, sequential` | 357 ns | 0 B | 0/30 | 2.80 M/s | 326 ns..447 ns | 347 ns/418 ns | 2.87× slower |
| `U2 codegen + hash on kind` | 117 ns | 0 B | 0/30 | 8.53 M/s | 109 ns..138 ns | 117 ns/138 ns | 1.06× faster |
| `U3 matchigo compile (shapes)` | 682 ns | 0 B | 0/30 | 1.47 M/s | 620 ns..840 ns | 670 ns/760 ns | 5.48× slower |
| `U4 matchigo fast-path + codegen` | 128 ns | 0 B | 0/30 | 7.82 M/s | 122 ns..151 ns | 125 ns/138 ns | tie |

## S8 impure schema (default, transform, strip) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written copy` | 701 ns | 346 B | 0/30 | 1.43 M/s | 630 ns..910 ns | 670 ns/900 ns | _(base)_ |
| `zigo safeParse (_parse)` | 1.77 µs | 260 B | 0/30 | 563.91 K/s | 1.34 µs..2.67 µs | 1.69 µs/2.36 µs | 2.53× slower |
| `zigo is (_parse, no result kept)` | 1.91 µs | 412 B | 0/30 | 523.93 K/s | 1.43 µs..2.50 µs | 1.91 µs/2.35 µs | 2.72× slower |

