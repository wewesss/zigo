# zigo bench — `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-11-08 16:52
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
| `zigo codegen` | 1 ns | 0 B | 0/30 | 779.02 M/s | 1 ns..1 ns | 1 ns/1 ns | tie |
| `zigo closures` | 2 ns | 0 B | 0/30 | 647.53 M/s | 1 ns..2 ns | 2 ns/2 ns | 1.19× slower |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 43 ns | 0 B | 0/30 | 23.31 M/s | 42 ns..45 ns | 43 ns/45 ns | _(base)_ |
| `zigo codegen` | 45 ns | 0 B | 0/30 | 22.33 M/s | 44 ns..47 ns | 45 ns/46 ns | tie |
| `zigo closures` | 291 ns | 0 B | 0/30 | 3.44 M/s | 283 ns..305 ns | 290 ns/302 ns | 6.78× slower |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 56 ns | 0 B | 0/30 | 17.88 M/s | 51 ns..77 ns | 52 ns/76 ns | _(base)_ |
| `zigo codegen` | 57 ns | 0 B | 0/30 | 17.67 M/s | 49 ns..72 ns | 53 ns/71 ns | tie |
| `zigo closures` | 367 ns | 0 B | 0/30 | 2.73 M/s | 316 ns..470 ns | 345 ns/468 ns | 6.56× slower |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 7.23 µs | 2 B | 0/30 | 138.25 K/s | 5.30 µs..9.80 µs | 6.90 µs/9.40 µs | _(base)_ |
| `zigo codegen` | 4.97 µs | 2 B | 0/30 | 201.29 K/s | 4.51 µs..7.24 µs | 4.69 µs/7.08 µs | 1.46× faster |
| `zigo closures` | 69.60 µs | 2 B | 0/30 | 14.37 K/s | 63.00 µs..101.00 µs | 67.00 µs/89.00 µs | 9.62× slower |

## Union of 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 38 ns | 0 B | 0/30 | 26.52 M/s | 32 ns..56 ns | 34 ns/55 ns | _(base)_ |
| `U1 closures, sequential` | 59 ns | 0 B | 0/30 | 16.84 M/s | 56 ns..64 ns | 59 ns/63 ns | 1.58× slower |
| `U2 codegen + hash on kind` | 40 ns | 0 B | 0/30 | 25.28 M/s | 38 ns..42 ns | 40 ns/41 ns | tie |
| `U3 matchigo compile (shapes)` | 281 ns | 0 B | 0/30 | 3.55 M/s | 274 ns..294 ns | 280 ns/291 ns | 7.46× slower |
| `U4 matchigo fast-path + codegen` | 48 ns | 0 B | 0/30 | 20.67 M/s | 47 ns..50 ns | 48 ns/49 ns | 1.28× slower |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 33 ns | 0 B | 0/30 | 30.21 M/s | 32 ns..35 ns | 33 ns/34 ns | _(base)_ |
| `U1 closures, sequential` | 69 ns | 0 B | 0/30 | 14.44 M/s | 60 ns..94 ns | 65 ns/86 ns | 2.09× slower |
| `U2 codegen + hash on kind` | 39 ns | 0 B | 0/30 | 25.34 M/s | 39 ns..40 ns | 39 ns/40 ns | 1.19× slower |
| `U3 matchigo compile (shapes)` | 333 ns | 0 B | 0/30 | 3.00 M/s | 317 ns..421 ns | 326 ns/387 ns | 10.07× slower |
| `U4 matchigo fast-path + codegen` | 49 ns | 0 B | 0/30 | 20.59 M/s | 47 ns..51 ns | 48 ns/50 ns | 1.47× slower |

## S8 impure schema (default, transform, strip) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written copy` | 214 ns | 349 B | 0/30 | 4.67 M/s | 203 ns..231 ns | 213 ns/222 ns | _(base)_ |
| `zigo safeParse (_parse)` | 460 ns | 428 B | 0/30 | 2.18 M/s | 445 ns..486 ns | 458 ns/477 ns | 2.15× slower |
| `zigo is (_parse, no result kept)` | 472 ns | 428 B | 0/30 | 2.12 M/s | 453 ns..502 ns | 471 ns/499 ns | 2.21× slower |

