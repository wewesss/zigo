## Summary

<!-- What does this change do, and why. -->

## Linked issue

Closes #

## Type of change

<!-- Pick the conventional commit type this PR matches. -->

- [ ] feat
- [ ] fix
- [ ] perf
- [ ] docs
- [ ] refactor
- [ ] test
- [ ] chore
- [ ] ci

## User-facing change

<!-- One sentence on what changes for a consumer of the library, or "internal only". -->

## Checklist

- [ ] A test covers every behaviour change, and `lua tests/run.lua` is green on Lua 5.1, 5.4 and LuaJIT.
- [ ] `lua tests/run.lua --no-codegen` is green too.
- [ ] `lua build.lua` then `lua tests/run.lua dist` (bundle tests) are green.
- [ ] `types/zigo.d.lua` updated if the public API changed.
- [ ] `docs/fr` mirror updated if `docs/en` changed (and `README.fr.md` if `README.md` changed).
- [ ] `CHANGELOG.md` entry added under `## [Unreleased]`.
- [ ] No documentation claim without proof (a test, a measurement with its command, or a source URL).
- [ ] English only in code, comments, commit messages and any `.md` file touched.
- [ ] No AI co-author trailer in the commit message.
