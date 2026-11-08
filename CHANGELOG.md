# Changelog

All notable changes to zigo are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-09

First stable release. Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT 2.1, zero dependency.

### Added

- Core (P0): immutable schema nodes, `parse` / `safeParse` (`ok, value, err`) / `is`, primitives (`string`, `number`, `integer`, `boolean`, `literal`, `enum`, `any`, `unknown`, `never`), `object`, `array`, `:optional()`, `:min()` / `:max()` / `:between()` / `:len()`, structured errors with stable codes, `err:format()` and `err:flatten()`, replaceable English messages (`z.setMessages`, `z.messages`).
- Codegen (P1): the valid-path test is compiled with `load` into one flat function, with an automatic fallback to closures; `z.config({ codegen = false })` forces the closures. Equivalence of both implementations is covered by a fixed-seed fuzz test; pure schemas allocate nothing on a valid call.
- Impure schemas (P2): `:default()`, `:transform()`, `:refine()`, `:pipe()`, `:strip()`, `ctx:addIssue()`, and strict `z.coerce.number`, `integer`, `boolean`, `string`.
- Containers and network limits (P3): `union`, `discriminatedUnion` (hash dispatch), `tuple` with `:rest()`, `record`, `lazy` for recursive schemas, and the limits `maxDepth` (64), `maxKeys` (10000), `maxErrors` (100), `abortEarly`, set with `z.config` or `schema:limits()`.
- Boundary types (P4): `u8`, `u16`, `u32`, `i8`, `i16`, `i32`, `int64` (with `fromString`), `bytes`, `utf8` (strict RFC 3629, lengths in characters), `cdata` and `notNullPtr` (LuaJIT), `null` / `:nullable()` with a configurable NULL sentinel (`z.config({ null = ... })`), `userdata`, `instanceOf`, `func`, and `z.coerce.u8` ... `z.coerce.i32`.
- Release (P5): LuaCATS annotations in `types/zigo.d.lua` (a test checks that every public key is declared), the single-file bundle `dist/zigo.lua` and its minified form, the English and French guides in `docs/`, the matchigo interop covered by `tests/matchigo_test.lua` against the real matchigo-lua, and the `zigo-1.0.0-1` rockspec.

### Fixed

- `int64({ fromString = true })` on Lua 5.1 and 5.2 returned `-0` for the string `"-0"`; it now returns `0`.
- The fuzz oracle for `int64` `fromString` now uses the 2^53 bound on runtimes without native 64-bit integers, and compares plain-number results with `%.0f` instead of `tostring`.

[1.0.0]: https://github.com/wewesss/zigo/releases/tag/v1.0.0
