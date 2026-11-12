# Contributing to zigo

zigo is a Zod-like data validator for Lua 5.1-5.4 and LuaJIT, released as 1.0.0. This document explains how to set up the project, what a pull request must contain, and how to report a bug. Read it before opening a pull request.

## Prerequisites

- A Lua runtime: 5.1, 5.2, 5.3, 5.4 or LuaJIT 2.1. CI runs the suite on all five.
- To install several runtimes side by side, `scripts/install-lua.sh` (Linux, macOS) and `scripts/install-lua.ps1` (Windows) build isolated trees under `./.lua/` with hererocks. They need Python 3 and a C toolchain.

```sh
./scripts/install-lua.sh 5.1 5.4 luajit
```

- zigo has no runtime dependency. The matchigo integration test and the bench need a clone of [matchigo-lua](https://github.com/wewesss/matchigo-lua), read from `MATCHIGO_PATH`.

## Commands

```sh
git clone --depth 1 https://github.com/wewesss/matchigo-lua.git matchigo-lua
export MATCHIGO_PATH=./matchigo-lua

lua tests/run.lua                # tests against the sources
lua tests/run.lua --no-codegen   # same suite with codegen disabled (closures)
lua build.lua                    # bundle into dist/zigo.lua and dist/zigo.min.lua
lua tests/run.lua dist           # tests against the bundle
```

Before opening a pull request, run all four, on at least Lua 5.1, Lua 5.4 and LuaJIT. `lua bench/run.lua` is optional and needs `dist/`.

## Conventional commits

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

Types: `feat`, `fix`, `perf`, `docs`, `refactor`, `test`, `chore`, `ci`. A change confined to `.md` files is `docs`.

### No AI co-author trailer

Never add an AI co-author trailer to a commit message, under any name. Authorship trailers are for human contributors only.

## Rules for a pull request

- **A test for every behaviour change.** There is no exception for an "obvious" fix. Tests live in `tests/` and run through `tests/run.lua`.
- **Both implementations stay equivalent.** The suite must pass with codegen on and with `--no-codegen`.
- **English in code, comments and commits.** No comments by default: write one only for a non-obvious WHY, never to restate WHAT the code does.
- **Public API change.** Update `types/zigo.d.lua` in the same pull request (a test checks that every public key is declared).
- **Documentation.** `docs/en` and `docs/fr` stay in sync: a change to one guide is mirrored in the other. The README has the same mirror (`README.md` and `README.fr.md`).
- **CHANGELOG.** Add an entry under `## [Unreleased]` in `CHANGELOG.md`.
- **No documentation claim without its proof**: a test, a measurement with its command, or a source URL.

## Licensing of contributions

zigo is MIT licensed. By submitting a contribution you agree it is licensed to the project under the same MIT license.

## Reporting a bug

Use the "Bug report" issue template. It asks for the zigo version, your Lua runtime, a minimal Lua reproduction, the expected result against the actual one (including the `err:format()` output), and whether codegen was on. A report without a reproduction may be sent back for it.

For a security problem, do not open an issue: see [SECURITY.md](./SECURITY.md).
