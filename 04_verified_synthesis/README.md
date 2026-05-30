# 04 — Program Synthesis + DomainSpec

The milestone: a single comptime-generic invention engine that produces strict
INVENTION across three structurally different domains (u64 mixer, sort-net N=8,
boolean), plus the real Z3 verification pipeline (`verify_cli`). See `docs/` and
../RESEARCH_INDEX.md.

```sh
zig build      # 9 executables; verify_cli + verify_qflia_smoke link system libz3
```
Depends on `../core`.
