# zigo bench — `5.4`

**Runtime** : Lua 5.4 (no JIT)
**Generated** : 2026-11-08 15:34
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
| `hand-written if-chain` | 49 ns | 0 B | 0/30 | 20.34 M/s | 47 ns..52 ns | 49 ns/52 ns | _(base)_ |
| `zigo codegen` | 54 ns | 0 B | 0/30 | 18.55 M/s | 48 ns..67 ns | 54 ns/61 ns | 1.10× slower |
| `zigo closures` | 64 ns | 0 B | 0/30 | 15.57 M/s | 58 ns..73 ns | 63 ns/72 ns | 1.31× slower |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 514 ns | 0 B | 0/30 | 1.95 M/s | 500 ns..590 ns | 510 ns/540 ns | _(base)_ |
| `zigo codegen` | 573 ns | 0 B | 0/30 | 1.74 M/s | 550 ns..660 ns | 570 ns/620 ns | 1.12× slower |
| `zigo closures` | 1.27 µs | 0 B | 0/30 | 786.58 K/s | 1.14 µs..1.46 µs | 1.24 µs/1.41 µs | 2.47× slower |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 448 ns | 0 B | 0/30 | 2.23 M/s | 421 ns..511 ns | 442 ns/476 ns | _(base)_ |
| `zigo codegen` | 622 ns | 0 B | 0/30 | 1.61 M/s | 540 ns..710 ns | 615 ns/710 ns | 1.39× slower |
| `zigo closures` | 1.26 µs | 1 B | 0/30 | 794.28 K/s | 1.18 µs..1.45 µs | 1.23 µs/1.39 µs | 2.81× slower |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `hand-written if-chain` | 109.57 µs | 0 B | 0/30 | 9.13 K/s | 102.00 µs..122.00 µs | 108.00 µs/120.00 µs | _(base)_ |
| `zigo codegen` | 132.47 µs | 0 B | 0/30 | 7.55 K/s | 118.00 µs..157.00 µs | 130.50 µs/153.00 µs | 1.21× slower |
| `zigo closures` | 334.67 µs | 0 B | 0/30 | 2.99 K/s | 296.00 µs..498.00 µs | 323.00 µs/402.00 µs | 3.05× slower |

## Union of 10 variants - valid inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 157 ns | 0 B | 0/30 | 6.35 M/s | 139 ns..181 ns | 155 ns/179 ns | _(base)_ |
| `U1 closures, sequential` | 324 ns | 0 B | 0/30 | 3.08 M/s | 294 ns..480 ns | 310 ns/386 ns | 2.06× slower |
| `U2 codegen + hash on kind` | 140 ns | 0 B | 0/30 | 7.12 M/s | 121 ns..223 ns | 135 ns/169 ns | 1.12× faster |
| `U3 matchigo compile (shapes)` | 1.22 µs | 0 B | 0/30 | 817.88 K/s | 1.13 µs..1.46 µs | 1.21 µs/1.38 µs | 7.76× slower |
| `U4 matchigo fast-path + codegen` | 151 ns | 0 B | 0/30 | 6.63 M/s | 136 ns..178 ns | 147 ns/177 ns | tie |

## Union of 10 variants - mixed inputs

| benchmark | mean | alloc | gc | rate | min..max | p50/p99 | vs base |
|---|---:|---:|---:|---:|---:|---:|---:|
| `U0 hand-written if/elseif` | 137 ns | 0 B | 0/30 | 7.30 M/s | 121 ns..175 ns | 132 ns/167 ns | _(base)_ |
| `U1 closures, sequential` | 480 ns | 0 B | 0/30 | 2.08 M/s | 365 ns..682 ns | 473 ns/667 ns | 3.50× slower |
| `U2 codegen + hash on kind` | 155 ns | 0 B | 0/30 | 6.47 M/s | 114 ns..179 ns | 155 ns/178 ns | 1.13× slower |
| `U3 matchigo compile (shapes)` | 2.00 µs | 0 B | 0/30 | 500.08 K/s | 1.50 µs..2.54 µs | 2.00 µs/2.29 µs | 14.60× slower |
| `U4 matchigo fast-path + codegen` | 168 ns | 0 B | 0/30 | 5.94 M/s | 142 ns..202 ns | 168 ns/196 ns | 1.23× slower |

