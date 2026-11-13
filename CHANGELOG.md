# Changelog

All notable changes to zigo are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-12

First stable release. Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT 2.1, zero dependency.

### Added

- Core (P0): immutable schema nodes, `parse` / `safeParse` (`ok, value, err`) / `is`, primitives (`string`, `number`, `integer`, `boolean`, `literal`, `enum`, `any`, `unknown`, `never`), `object`, `array`, `:optional()`, `:min()` / `:max()` / `:between()` / `:len()`, structured errors with stable codes, `err:format()` and `err:flatten()`, replaceable English messages (`z.setMessages`, `z.messages`).
- Codegen (P1): the valid-path test is compiled with `load` into one flat function, with an automatic fallback to closures; `z.config({ codegen = false })` forces the closures. Equivalence of both implementations is covered by a fixed-seed fuzz test; pure schemas allocate nothing on a valid call.
- Impure schemas (P2): `:default()`, `:transform()`, `:refine()`, `:pipe()`, `:strip()`, `ctx:addIssue()`, and strict `z.coerce.number`, `integer`, `boolean`, `string`.
- Containers and network limits (P3): `union`, `discriminatedUnion` (hash dispatch), `tuple` with `:rest()`, `record`, `lazy` for recursive schemas, and the limits `maxDepth` (64), `maxKeys` (10000), `maxErrors` (100), `abortEarly`, set with `z.config` or `schema:limits()`.
- Boundary types (P4): `u8`, `u16`, `u32`, `i8`, `i16`, `i32`, `int64` (with `fromString`), `bytes`, `utf8` (strict RFC 3629, lengths in characters), `cdata` and `notNullPtr` (LuaJIT), `null` / `:nullable()` with a configurable NULL sentinel (`z.config({ null = ... })`), `userdata`, `instanceOf`, `func`, and `z.coerce.u8` ... `z.coerce.i32`.
- Release (P5): LuaCATS annotations in `types/zigo.d.lua` (a test checks that every public key is declared), the single-file bundle `dist/zigo.lua` and its minified form, the English and French guides in `docs/`, the matchigo interop covered by `tests/matchigo_test.lua` against the real matchigo-lua, and the `zigo-1.0.0-1` rockspec.

### Fixed

- `transform`, `refine`, `default` functions, `pipe` targets and `ctx:addIssue` callbacks ran twice on invalid input, because the diagnostic pass parsed the value again; every callback now runs at most once per `parse` / `safeParse` call, with codegen on or off (`tests/impure_test.lua`).
- `int64({ fromString = true })` on Lua 5.1 and 5.2 returned `-0` for the string `"-0"`; it now returns `0`.
- The fuzz oracle for `int64` `fromString` now uses the 2^53 bound on runtimes without native 64-bit integers, and compares plain-number results with `%.0f` instead of `tostring`.

### Performance

- `schema:safeParse`, `:parse` and `:is` are cached on the node instance, so a call no longer goes through the `__index` function (about 14% faster on a pure object on Lua 5.4).
- Generated code tests booleans by identity instead of `type()` (140 ns to 76 ns on an object of five booleans, Lua 5.4) and checks the key type of a `record` once (615 ns to 487 ns on a `record(string, number)` of 8 keys, Lua 5.4).
- Generated discriminated unions no longer repeat in the variant the table test and the discriminator check the wrapper already did (147 ns to 105 ns for 4 variants, Lua 5.4).
- Tables with a metatable are validated by a generated raw twin of the schema instead of the closures (an array of 4 metatabled rows: 2300 ns to 1700 ns on Lua 5.4, 280 ns to 60 ns on LuaJIT); `tests/metatable_test.lua` compares both implementations on a fixed-seed fuzz.
- Impure schemas reuse their parse context between calls (a scalar `transform`: 325 ns to 170 ns, an impure object: 2060 ns to 1650 ns on Lua 5.4). The `ctx` passed to callbacks is valid only during the call.
- The error pass of `safeParse` and `parse` skips the valid subtrees of objects, arrays, tuples and records by running their compiled `_test` first; the issues are unchanged (an array of 1000 objects with one invalid row: 409 us to 190 us on Lua 5.4, 102 us to 10 us on LuaJIT; a nesting of depth 8: 3.17 us to 1.99 us on Lua 5.4).

### Documentation

- README in English and French: badges (CI, release, LuaRocks, Lua version, runtime dependencies, license), quickstart with a `discriminatedUnion` example, three install paths (LuaRocks, release archive with LuaLS setup, sources), features, documentation links.
- `.github/release-readme.md` (the README shipped in the release archive) holds a usage example, the LuaLS `Lua.workspace.library` note and full GitHub links.
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1) and `SECURITY.md`.
- The pull request template and the issue templates (bug report, feature request) under `.github/`.

[1.0.0]: https://github.com/wewesss/zigo/releases/tag/v1.0.0
