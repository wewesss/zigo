# zigo comparison bench - `luajit-2.1`

**Runtime** : Lua 5.1 / LuaJIT 2.1.1727870382
**Generated** : 2026-11-13 02:11
**Config** : 30 samples, 200 warmup, 50ms calibration target
**Libraries** : zigo 1.0.0, tableshape 2.8.0, ljsonschema (version not exposed, see COMPARE.md), lshape 0.3.0

> [!IMPORTANT]
> Generated file. Read `COMPARE.md` for the method and the guarantees caveats before quoting a number.

The `agrees with baseline` column counts how many fixture inputs each row classified as the hand-written baseline does. A row marked MISMATCH does not enforce every guarantee of the fixture, so its timing is not a like-for-like comparison.

## S1 string():min(3) - valid inputs

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 1 ns | 1 ns | 2 ns | 0 B | _(base)_ | valid 64/64, invalid 7/7, first-field invalid 64/64 | reference |
| `zigo :is` | 2 ns | 1 ns | 2 ns | 0 B | 1.10× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string min length |
| `zigo :safeParse` | 2 ns | 2 ns | 2 ns | 0 B | 1.14× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string min length; builds issues on failure |
| `tableshape (interpreted)` | 51 ns | 50 ns | 61 ns | 0 B | 36.88× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by range |
| `tableshape (codegen)` | 20 ns | 20 ns | 22 ns | 0 B | 14.66× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by range |
| `lua-resty-ljsonschema` | 45 ns | 45 ns | 53 ns | 0 B | 33.16× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string length counted in UTF-8 characters |
| `lshape` | 34 ns | 33 ns | 37 ns | 0 B | 24.45× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by min_len |

## S1 string():min(3) - invalid inputs, string shorter than the minimum

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 23 ns | 23 ns | 26 ns | 0 B | _(base)_ | valid 64/64, invalid 7/7, first-field invalid 64/64 | reference |
| `zigo :is` | 29 ns | 29 ns | 34 ns | 0 B | 1.26× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string min length |
| `zigo :safeParse` | 217 ns | 209 ns | 376 ns | 409 B | 9.51× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string min length; builds issues on failure |
| `tableshape (interpreted)` | 129 ns | 127 ns | 141 ns | 0 B | 5.65× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by range |
| `tableshape (codegen)` | 74 ns | 73 ns | 80 ns | 0 B | 3.23× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by range |
| `lua-resty-ljsonschema` | 35 ns | 32 ns | 47 ns | 0 B | 1.53× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string length counted in UTF-8 characters |
| `lshape` | 52 ns | 45 ns | 88 ns | 0 B | 2.27× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by min_len |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 66 ns | 62 ns | 90 ns | 1 B | _(base)_ | valid 64/64, invalid 13/13, first-field invalid 64/64 | reference |
| `zigo :is` | 75 ns | 72 ns | 99 ns | 2 B | 1.13× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | unknown keys allowed; integer ranges; dense arrays (holes and stray keys rejected) |
| `zigo :safeParse` | 99 ns | 88 ns | 135 ns | 2 B | 1.50× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | unknown keys allowed; integer ranges; dense arrays (holes and stray keys rejected); builds issues on failure |
| `tableshape (interpreted)` | 1.76 µs | 1.69 µs | 2.23 µs | 741 B | 26.57× slower | valid 64/64, invalid 10/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#11,#12); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `tableshape (codegen)` | 88 ns | 74 ns | 159 ns | 10 B | 1.33× slower | valid 64/64, invalid 10/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#11,#12); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `lua-resty-ljsonschema` | 393 ns | 340 ns | 770 ns | 17 B | 5.94× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); arrays detected by the shape of the Lua table |
| `lshape` | 1.55 µs | 1.51 µs | 1.91 µs | 360 B | 23.46× slower | valid 64/64, invalid 11/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#11); unknown keys allowed (open shape, default); arrays must be dense |

## S2 reference schema (7 fields, nested object, array, enum, optional) - invalid inputs, id out of range

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 10 ns | 10 ns | 12 ns | 0 B | _(base)_ | valid 64/64, invalid 13/13, first-field invalid 64/64 | reference |
| `zigo :is` | 28 ns | 27 ns | 33 ns | 0 B | 2.82× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | unknown keys allowed; integer ranges; dense arrays (holes and stray keys rejected) |
| `zigo :safeParse` | 423 ns | 400 ns | 600 ns | 704 B | 42.73× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | unknown keys allowed; integer ranges; dense arrays (holes and stray keys rejected); builds issues on failure |
| `tableshape (interpreted)` | 1.11 µs | 1.04 µs | 1.56 µs | 640 B | 112.39× slower | valid 64/64, invalid 10/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#11,#12); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `tableshape (codegen)` | 141 ns | 134 ns | 170 ns | 0 B | 14.22× slower | valid 64/64, invalid 10/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#11,#12); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `lua-resty-ljsonschema` | 578 ns | 485 ns | 800 ns | 0 B | 58.38× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); arrays detected by the shape of the Lua table |
| `lshape` | 1.05 µs | 1.03 µs | 1.24 µs | 336 B | 106.20× slower | valid 64/64, invalid 11/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#11); unknown keys allowed (open shape, default); arrays must be dense |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 88 ns | 87 ns | 103 ns | 0 B | _(base)_ | valid 64/64, invalid 4/4, first-field invalid 64/64 | reference |
| `zigo :is` | 58 ns | 58 ns | 61 ns | 0 B | 1.51× faster | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed; integers checked |
| `zigo :safeParse` | 57 ns | 57 ns | 63 ns | 0 B | 1.54× faster | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed; integers checked; builds issues on failure |
| `tableshape (interpreted)` | 3.89 µs | 3.98 µs | 5.09 µs | 1.75 KB | 44.08× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape) |
| `tableshape (codegen)` | 106 ns | 107 ns | 112 ns | 0 B | 1.20× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape) |
| `lua-resty-ljsonschema` | 354 ns | 341 ns | 430 ns | 0 B | 4.01× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default) |
| `lshape` | 2.08 µs | 1.91 µs | 2.72 µs | 818 B | 23.55× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed (open shape, default) |

## S3 nesting depth 8 - invalid inputs, outermost n not an integer

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 26 ns | 25 ns | 31 ns | 0 B | _(base)_ | valid 64/64, invalid 4/4, first-field invalid 64/64 | reference |
| `zigo :is` | 67 ns | 62 ns | 90 ns | 0 B | 2.61× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed; integers checked |
| `zigo :safeParse` | 637 ns | 536 ns | 1.13 µs | 656 B | 24.67× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed; integers checked; builds issues on failure |
| `tableshape (interpreted)` | 2.99 µs | 2.92 µs | 3.36 µs | 1.75 KB | 115.93× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape) |
| `tableshape (codegen)` | 134 ns | 133 ns | 145 ns | 0 B | 5.20× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape) |
| `lua-resty-ljsonschema` | 109 ns | 104 ns | 131 ns | 0 B | 4.20× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default) |
| `lshape` | 2.68 µs | 2.16 µs | 3.89 µs | 819 B | 103.82× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed (open shape, default) |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 6.34 µs | 6.30 µs | 8.00 µs | 0 B | _(base)_ | valid 8/8, invalid 7/7, first-field invalid 8/8 | reference |
| `zigo :is` | 8.44 µs | 8.00 µs | 10.60 µs | 0 B | 1.33× slower | valid 8/8, invalid 7/7, first-field invalid 8/8 | unknown keys allowed; integers checked; dense arrays (holes and stray keys rejected) |
| `zigo :safeParse` | 4.89 µs | 4.70 µs | 5.90 µs | 0 B | 1.30× faster | valid 8/8, invalid 7/7, first-field invalid 8/8 | unknown keys allowed; integers checked; dense arrays (holes and stray keys rejected); builds issues on failure |
| `tableshape (interpreted)` | 538.67 µs | 540.00 µs | 560.00 µs | 312.50 KB | 84.92× slower | valid 8/8, invalid 4/7, first-field invalid 8/8 | MISMATCH (accepts invalid #2,#3,#4); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `tableshape (codegen)` | 6.53 µs | 6.50 µs | 6.80 µs | 0 B | tie | valid 8/8, invalid 4/7, first-field invalid 8/8 | MISMATCH (accepts invalid #2,#3,#4); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `lua-resty-ljsonschema` | 190.50 µs | 188.50 µs | 201.00 µs | 0 B | 30.03× slower | valid 8/8, invalid 7/7, first-field invalid 8/8 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); arrays detected by the shape of the Lua table |
| `lshape` | 433.50 µs | 422.50 µs | 514.00 µs | 101.81 KB | 68.34× slower | valid 8/8, invalid 5/7, first-field invalid 8/8 | MISMATCH (accepts invalid #3,#4); unknown keys allowed (open shape, default); arrays must be dense |

## S4 array of 1000 objects - invalid inputs, first row invalid

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 1.16 µs | 1.14 µs | 1.30 µs | 0 B | _(base)_ | valid 8/8, invalid 7/7, first-field invalid 8/8 | reference |
| `zigo :is` | 1.17 µs | 1.15 µs | 1.39 µs | 0 B | tie | valid 8/8, invalid 7/7, first-field invalid 8/8 | unknown keys allowed; integers checked; dense arrays (holes and stray keys rejected) |
| `zigo :safeParse` | 8.51 µs | 8.10 µs | 10.30 µs | 680 B | 7.35× slower | valid 8/8, invalid 7/7, first-field invalid 8/8 | unknown keys allowed; integers checked; dense arrays (holes and stray keys rejected); builds issues on failure |
| `tableshape (interpreted)` | 736 ns | 720 ns | 880 ns | 272 B | 1.57× faster | valid 8/8, invalid 4/7, first-field invalid 8/8 | MISMATCH (accepts invalid #2,#3,#4); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `tableshape (codegen)` | 111 ns | 110 ns | 118 ns | 0 B | 10.40× faster | valid 8/8, invalid 4/7, first-field invalid 8/8 | MISMATCH (accepts invalid #2,#3,#4); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `lua-resty-ljsonschema` | 3.74 µs | 3.51 µs | 4.77 µs | 0 B | 3.23× slower | valid 8/8, invalid 7/7, first-field invalid 8/8 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); arrays detected by the shape of the Lua table |
| `lshape` | 686 ns | 670 ns | 840 ns | 216 B | 1.69× faster | valid 8/8, invalid 5/7, first-field invalid 8/8 | MISMATCH (accepts invalid #3,#4); unknown keys allowed (open shape, default); arrays must be dense |

## S5 discriminatedUnion, 10 variants - valid inputs

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 49 ns | 48 ns | 54 ns | 0 B | _(base)_ | valid 64/64, invalid 14/14, first-field invalid 64/64 | reference |
| `zigo :is` | 49 ns | 48 ns | 53 ns | 0 B | tie | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed; integers checked; discriminated union |
| `zigo :safeParse` | 60 ns | 60 ns | 71 ns | 0 B | 1.23× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed; integers checked; discriminated union; builds issues on failure |
| `tableshape (interpreted)` | 3.30 µs | 3.20 µs | 4.02 µs | 1.27 KB | 67.61× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape); no discriminator, variants tried in order |
| `tableshape (codegen)` | 106 ns | 105 ns | 121 ns | 0 B | 2.17× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape); no discriminator, variants tried in order |
| `lua-resty-ljsonschema` | 1.15 µs | 1.13 µs | 1.36 µs | 0 B | 23.61× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); no discriminator, anyOf tried in order |
| `lshape` | 582 ns | 575 ns | 640 ns | 216 B | 11.90× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed (open shape, default); native discriminated union |

## S5 discriminatedUnion, 10 variants - invalid inputs, unknown discriminator

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 23 ns | 23 ns | 26 ns | 0 B | _(base)_ | valid 64/64, invalid 14/14, first-field invalid 64/64 | reference |
| `zigo :is` | 54 ns | 54 ns | 57 ns | 0 B | 2.34× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed; integers checked; discriminated union |
| `zigo :safeParse` | 603 ns | 600 ns | 720 ns | 856 B | 26.00× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed; integers checked; discriminated union; builds issues on failure |
| `tableshape (interpreted)` | 20.87 µs | 20.30 µs | 24.60 µs | 5.61 KB | 899.17× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape); no discriminator, variants tried in order |
| `tableshape (codegen)` | 106 ns | 104 ns | 123 ns | 0 B | 4.57× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape); no discriminator, variants tried in order |
| `lua-resty-ljsonschema` | 5.19 µs | 5.10 µs | 5.60 µs | 9 B | 223.79× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); no discriminator, anyOf tried in order |
| `lshape` | 1.53 µs | 1.48 µs | 1.75 µs | 513 B | 65.73× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed (open shape, default); native discriminated union |

## Acceptance mismatches

- S2 reference schema (7 fields, nested object, array, enum, optional) / tableshape (interpreted): accepts invalid #10,#11,#12
- S2 reference schema (7 fields, nested object, array, enum, optional) / tableshape (codegen): accepts invalid #10,#11,#12
- S2 reference schema (7 fields, nested object, array, enum, optional) / lshape: accepts invalid #10,#11
- S4 array of 1000 objects / tableshape (interpreted): accepts invalid #2,#3,#4
- S4 array of 1000 objects / tableshape (codegen): accepts invalid #2,#3,#4
- S4 array of 1000 objects / lshape: accepts invalid #3,#4

