# Round AN / AN2 — clean-room escape audit

**Verdict: GATE READY for the declared raw-action protocol only.** The
deterministic audit accepts exactly one baseline raw action form and rejects all
15 hostile protocol payloads. This is useful boundary instrumentation, not a
claim that the candidate cannot escape, corrupt the evaluator, or access the
host.

## Executed checks

The tested protocol accepts only the exact five-byte form `ACT:<0..3>`. It
fails closed for target, reward, and score requests; newline and NUL command
smuggling; invalid, truncated, and oversized messages; path traversal;
evaluator mutation; transcript rewriting; inherited-handle probes; process,
IPC, and environment probes; clock feedback; and a resource-exhaustion request.
The generated ledger records every fixture and its observed result.

## What this does and does not establish

This audit establishes that the local Zig parser has no alternate request verbs
for those seeded messages. It does **not** exercise an actual separately
launched evaluator or impose filesystem, environment, inherited-FD, `/proc`,
network, IPC, clock, syscall, resource, kernel, compiler, or hardware barriers.
Those are residual risks until AN1 supplies a real process launcher and an
independent hostile process-level audit runs against it.

The trusted computing base remains the evaluator and launcher, Zig runtime and
compiler, operating system/kernel, and hardware. No result here is an
impossibility proof or a general security claim.

## Reproduce

```bash
mkdir -p /tmp/zig-an2-cache /tmp/zig-an2-global
zig build-exe sparse_poly_discovery/cleanroom_escape_audit_round_an.zig \
  -femit-bin=/tmp/cleanroom-escape-an2 \
  --cache-dir /tmp/zig-an2-cache --global-cache-dir /tmp/zig-an2-global
/tmp/cleanroom-escape-an2 selftest
/tmp/cleanroom-escape-an2 run results/cleanroom_escape_audit_round_an.csv
```
