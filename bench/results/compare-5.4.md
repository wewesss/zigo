# zigo comparison bench - `5.4`

**Runtime** : Lua 5.4 (no JIT)
**Generated** : 2026-11-13 02:04
**Config** : 30 samples, 200 warmup, 50ms calibration target
**Libraries** : zigo 1.0.0, tableshape 2.8.0, ljsonschema (version not exposed, see COMPARE.md), lshape 0.3.0

> [!IMPORTANT]
> Generated file. Read `COMPARE.md` for the method and the guarantees caveats before quoting a number.

The `agrees with baseline` column counts how many fixture inputs each row classified as the hand-written baseline does. A row marked MISMATCH does not enforce every guarantee of the fixture, so its timing is not a like-for-like comparison.

## S1 string():min(3) - valid inputs

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 54 ns | 50 ns | 80 ns | 0 B | _(base)_ | valid 64/64, invalid 7/7, first-field invalid 64/64 | reference |
| `zigo :is` | 70 ns | 70 ns | 73 ns | 0 B | 1.29× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string min length |
| `zigo :safeParse` | 80 ns | 78 ns | 94 ns | 0 B | 1.48× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string min length; builds issues on failure |
| `tableshape (interpreted)` | 244 ns | 239 ns | 284 ns | 0 B | 4.50× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by range |
| `tableshape (codegen)` | 138 ns | 129 ns | 174 ns | 0 B | 2.54× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by range |
| `lua-resty-ljsonschema` | 105 ns | 103 ns | 116 ns | 0 B | 1.94× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string length counted in UTF-8 characters |
| `lshape` | 500 ns | 489 ns | 604 ns | 80 B | 9.22× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by min_len |

## S1 string():min(3) - invalid inputs, string shorter than the minimum

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 48 ns | 47 ns | 57 ns | 0 B | _(base)_ | valid 64/64, invalid 7/7, first-field invalid 64/64 | reference |
| `zigo :is` | 70 ns | 70 ns | 76 ns | 0 B | 1.47× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string min length |
| `zigo :safeParse` | 809 ns | 820 ns | 980 ns | 536 B | 16.86× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string min length; builds issues on failure |
| `tableshape (interpreted)` | 806 ns | 750 ns | 1.02 µs | 72 B | 16.79× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by range |
| `tableshape (codegen)` | 150 ns | 149 ns | 161 ns | 0 B | 3.13× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by range |
| `lua-resty-ljsonschema` | 252 ns | 247 ns | 274 ns | 69 B | 5.25× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | string length counted in UTF-8 characters |
| `lshape` | 733 ns | 730 ns | 790 ns | 154 B | 15.27× slower | valid 64/64, invalid 7/7, first-field invalid 64/64 | length by min_len |

## S2 reference schema (7 fields, nested object, array, enum, optional) - valid inputs

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 563 ns | 500 ns | 970 ns | 0 B | _(base)_ | valid 64/64, invalid 13/13, first-field invalid 64/64 | reference |
| `zigo :is` | 622 ns | 595 ns | 780 ns | 0 B | 1.11× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | unknown keys allowed; integer ranges; dense arrays (holes and stray keys rejected) |
| `zigo :safeParse` | 686 ns | 605 ns | 1.52 µs | 0 B | 1.22× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | unknown keys allowed; integer ranges; dense arrays (holes and stray keys rejected); builds issues on failure |
| `tableshape (interpreted)` | 6.57 µs | 6.50 µs | 7.20 µs | 704 B | 11.67× slower | valid 64/64, invalid 10/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#11,#12); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `tableshape (codegen)` | 738 ns | 730 ns | 770 ns | 0 B | 1.31× slower | valid 64/64, invalid 10/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#11,#12); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `lua-resty-ljsonschema` | 1.53 µs | 1.50 µs | 1.73 µs | 0 B | 2.71× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); arrays detected by the shape of the Lua table |
| `lshape` | 6.14 µs | 6.10 µs | 6.60 µs | 354 B | 10.91× slower | valid 64/64, invalid 11/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#12); unknown keys allowed (open shape, default); arrays must be dense |

## S2 reference schema (7 fields, nested object, array, enum, optional) - invalid inputs, id out of range

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 79 ns | 75 ns | 88 ns | 0 B | _(base)_ | valid 64/64, invalid 13/13, first-field invalid 64/64 | reference |
| `zigo :is` | 258 ns | 255 ns | 283 ns | 0 B | 3.25× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | unknown keys allowed; integer ranges; dense arrays (holes and stray keys rejected) |
| `zigo :safeParse` | 2.09 µs | 2.09 µs | 2.15 µs | 568 B | 26.38× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | unknown keys allowed; integer ranges; dense arrays (holes and stray keys rejected); builds issues on failure |
| `tableshape (interpreted)` | 4.64 µs | 4.57 µs | 5.32 µs | 660 B | 58.53× slower | valid 64/64, invalid 10/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#11,#12); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `tableshape (codegen)` | 351 ns | 348 ns | 372 ns | 0 B | 4.43× slower | valid 64/64, invalid 10/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#11,#12); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `lua-resty-ljsonschema` | 1.82 µs | 1.81 µs | 1.89 µs | 87 B | 22.97× slower | valid 64/64, invalid 13/13, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); arrays detected by the shape of the Lua table |
| `lshape` | 3.81 µs | 3.80 µs | 3.97 µs | 419 B | 48.06× slower | valid 64/64, invalid 11/13, first-field invalid 64/64 | MISMATCH (accepts invalid #10,#12); unknown keys allowed (open shape, default); arrays must be dense |

## S3 nesting depth 8 - valid inputs

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 427 ns | 423 ns | 450 ns | 0 B | _(base)_ | valid 64/64, invalid 4/4, first-field invalid 64/64 | reference |
| `zigo :is` | 550 ns | 550 ns | 600 ns | 0 B | 1.29× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed; integers checked |
| `zigo :safeParse` | 589 ns | 585 ns | 620 ns | 0 B | 1.38× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed; integers checked; builds issues on failure |
| `tableshape (interpreted)` | 10.18 µs | 10.10 µs | 11.30 µs | 1.63 KB | 23.82× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape) |
| `tableshape (codegen)` | 713 ns | 700 ns | 840 ns | 2 B | 1.67× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape) |
| `lua-resty-ljsonschema` | 1.64 µs | 1.65 µs | 1.69 µs | 1 B | 3.84× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default) |
| `lshape` | 5.88 µs | 5.80 µs | 6.50 µs | 1000 B | 13.77× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed (open shape, default) |

## S3 nesting depth 8 - invalid inputs, outermost n not an integer

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 81 ns | 79 ns | 90 ns | 0 B | _(base)_ | valid 64/64, invalid 4/4, first-field invalid 64/64 | reference |
| `zigo :is` | 583 ns | 575 ns | 660 ns | 0 B | 7.24× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed; integers checked |
| `zigo :safeParse` | 1.95 µs | 1.94 µs | 2.03 µs | 568 B | 24.24× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed; integers checked; builds issues on failure |
| `tableshape (interpreted)` | 10.45 µs | 10.40 µs | 11.50 µs | 1.60 KB | 129.76× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape) |
| `tableshape (codegen)` | 742 ns | 735 ns | 840 ns | 2 B | 9.21× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape) |
| `lua-resty-ljsonschema` | 1.88 µs | 1.88 µs | 2.00 µs | 96 B | 23.40× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default) |
| `lshape` | 6.69 µs | 6.60 µs | 7.40 µs | 1.05 KB | 83.11× slower | valid 64/64, invalid 4/4, first-field invalid 64/64 | unknown keys allowed (open shape, default) |

## S4 array of 1000 objects - valid inputs

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 108.27 µs | 107.00 µs | 126.00 µs | 0 B | _(base)_ | valid 8/8, invalid 7/7, first-field invalid 8/8 | reference |
| `zigo :is` | 110.90 µs | 110.00 µs | 118.00 µs | 0 B | tie | valid 8/8, invalid 7/7, first-field invalid 8/8 | unknown keys allowed; integers checked; dense arrays (holes and stray keys rejected) |
| `zigo :safeParse` | 115.67 µs | 113.00 µs | 133.00 µs | 0 B | 1.07× slower | valid 8/8, invalid 7/7, first-field invalid 8/8 | unknown keys allowed; integers checked; dense arrays (holes and stray keys rejected); builds issues on failure |
| `tableshape (interpreted)` | 2.12 ms | 2.10 ms | 2.46 ms | 296.88 KB | 19.62× slower | valid 8/8, invalid 4/7, first-field invalid 8/8 | MISMATCH (accepts invalid #2,#3,#4); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `tableshape (codegen)` | 175.17 µs | 169.50 µs | 198.00 µs | 0 B | 1.62× slower | valid 8/8, invalid 4/7, first-field invalid 8/8 | MISMATCH (accepts invalid #2,#3,#4); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `lua-resty-ljsonschema` | 361.13 µs | 361.50 µs | 383.00 µs | 0 B | 3.34× slower | valid 8/8, invalid 7/7, first-field invalid 8/8 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); arrays detected by the shape of the Lua table |
| `lshape` | 1.69 ms | 1.68 ms | 1.90 ms | 117.43 KB | 15.61× slower | valid 8/8, invalid 5/7, first-field invalid 8/8 | MISMATCH (accepts invalid #3,#4); unknown keys allowed (open shape, default); arrays must be dense |

## S4 array of 1000 objects - invalid inputs, first row invalid

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 14.33 µs | 13.95 µs | 16.30 µs | 0 B | _(base)_ | valid 8/8, invalid 7/7, first-field invalid 8/8 | reference |
| `zigo :is` | 14.42 µs | 14.20 µs | 16.10 µs | 0 B | tie | valid 8/8, invalid 7/7, first-field invalid 8/8 | unknown keys allowed; integers checked; dense arrays (holes and stray keys rejected) |
| `zigo :safeParse` | 213.93 µs | 210.50 µs | 237.00 µs | 600 B | 14.93× slower | valid 8/8, invalid 7/7, first-field invalid 8/8 | unknown keys allowed; integers checked; dense arrays (holes and stray keys rejected); builds issues on failure |
| `tableshape (interpreted)` | 2.74 µs | 2.73 µs | 2.85 µs | 310 B | 5.23× faster | valid 8/8, invalid 4/7, first-field invalid 8/8 | MISMATCH (accepts invalid #2,#3,#4); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `tableshape (codegen)` | 237 ns | 235 ns | 257 ns | 0 B | 60.35× faster | valid 8/8, invalid 4/7, first-field invalid 8/8 | MISMATCH (accepts invalid #2,#3,#4); integers by predicate; unknown keys allowed (open shape); array holes and stray keys not checked |
| `lua-resty-ljsonschema` | 14.48 µs | 14.10 µs | 16.20 µs | 203 B | tie | valid 8/8, invalid 7/7, first-field invalid 8/8 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); arrays detected by the shape of the Lua table |
| `lshape` | 2.00 µs | 1.98 µs | 2.29 µs | 271 B | 7.16× faster | valid 8/8, invalid 5/7, first-field invalid 8/8 | MISMATCH (accepts invalid #3,#4); unknown keys allowed (open shape, default); arrays must be dense |

## S5 discriminatedUnion, 10 variants - valid inputs

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 126 ns | 126 ns | 134 ns | 0 B | _(base)_ | valid 64/64, invalid 14/14, first-field invalid 64/64 | reference |
| `zigo :is` | 182 ns | 181 ns | 192 ns | 0 B | 1.44× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed; integers checked; discriminated union |
| `zigo :safeParse` | 168 ns | 164 ns | 183 ns | 0 B | 1.33× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed; integers checked; discriminated union; builds issues on failure |
| `tableshape (interpreted)` | 9.11 µs | 9.10 µs | 9.70 µs | 1.19 KB | 72.24× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape); no discriminator, variants tried in order |
| `tableshape (codegen)` | 394 ns | 392 ns | 417 ns | 0 B | 3.13× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape); no discriminator, variants tried in order |
| `lua-resty-ljsonschema` | 1.55 µs | 1.52 µs | 1.70 µs | 390 B | 12.27× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); no discriminator, anyOf tried in order |
| `lshape` | 1.69 µs | 1.68 µs | 1.74 µs | 201 B | 13.39× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed (open shape, default); native discriminated union |

## S5 discriminatedUnion, 10 variants - invalid inputs, unknown discriminator

| benchmark | mean | p50 | p99 | alloc | vs hand | agrees with baseline | guarantees |
|---|---:|---:|---:|---:|---:|---|---|
| `hand-written if-chain` | 82 ns | 81 ns | 89 ns | 0 B | _(base)_ | valid 64/64, invalid 14/14, first-field invalid 64/64 | reference |
| `zigo :is` | 124 ns | 124 ns | 128 ns | 0 B | 1.51× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed; integers checked; discriminated union |
| `zigo :safeParse` | 1.28 µs | 1.27 µs | 1.42 µs | 880 B | 15.64× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed; integers checked; discriminated union; builds issues on failure |
| `tableshape (interpreted)` | 62.57 µs | 62.50 µs | 65.00 µs | 16.37 KB | 763.63× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape); no discriminator, variants tried in order |
| `tableshape (codegen)` | 466 ns | 467 ns | 478 ns | 0 B | 5.69× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | integers by predicate; unknown keys allowed (open shape); no discriminator, variants tried in order |
| `lua-resty-ljsonschema` | 7.06 µs | 7.00 µs | 7.80 µs | 9.67 KB | 86.17× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | string length counted in UTF-8 characters; unknown keys allowed (JSON Schema default); no discriminator, anyOf tried in order |
| `lshape` | 3.75 µs | 3.74 µs | 3.99 µs | 930 B | 45.73× slower | valid 64/64, invalid 14/14, first-field invalid 64/64 | unknown keys allowed (open shape, default); native discriminated union |

## Acceptance mismatches

- S2 reference schema (7 fields, nested object, array, enum, optional) / tableshape (interpreted): accepts invalid #10,#11,#12
- S2 reference schema (7 fields, nested object, array, enum, optional) / tableshape (codegen): accepts invalid #10,#11,#12
- S2 reference schema (7 fields, nested object, array, enum, optional) / lshape: accepts invalid #10,#12
- S4 array of 1000 objects / tableshape (interpreted): accepts invalid #2,#3,#4
- S4 array of 1000 objects / tableshape (codegen): accepts invalid #2,#3,#4
- S4 array of 1000 objects / lshape: accepts invalid #3,#4

