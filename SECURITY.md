# Security policy

## Scope

This policy covers the zigo library code (the `zigo/` modules and the bundle built from them, `zigo.lua` and `zigo.min.lua`). zigo is a validator of untrusted input, so these count as security issues:

- a bypass of a schema: an input that a schema should reject but accepts;
- the limits `maxDepth`, `maxKeys` and `maxErrors` not being enforced;
- a crash on crafted input.

The benchmarks and the scripts under `bench/` and `scripts/` are development tools, not part of the shipped library.

## Supported versions

| Version | Supported |
|---|---|
| 1.x (latest) | Yes |
| Older than 1.0.0 | No |

## Reporting a vulnerability

Report a vulnerability through [GitHub's private vulnerability reporting](https://github.com/wewesss/zigo/security/advisories/new). Do not open a public issue for a security report: a public issue exposes the vulnerability before a fix exists.

Include, where you can: the affected version, or the commit hash if you built from the tree; your Lua runtime (5.1, 5.2, 5.3, 5.4 or LuaJIT 2.1); a minimal reproduction; and the impact as you understand it.

## Response targets

These are targets the maintainer intends to meet, not guarantees:

- Acknowledge a new report within 7 days.
- For a confirmed issue, provide a fix or a mitigation plan within 30 days.

A report that turns out not to be a vulnerability, or that needs more information to confirm, may take longer to resolve than these targets.
