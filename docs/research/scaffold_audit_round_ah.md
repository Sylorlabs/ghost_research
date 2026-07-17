# AH3 — independent human-scaffold audit gate

**Verdict: VALID NEGATIVE (infrastructure pass, not a security or autonomy
certificate).** The deterministic audit gate admits only the declared uniform
local-transport/conservation exterior fixture and rejects all 11 hostile
fixtures. It is useful as a fail-closed release gate for Round AH, but it
cannot itself prove the absence of every scaffold in source, binaries, the
kernel, or side channels.

## What is audited

The auditor consumes an explicit capability and provenance manifest for the
organism-visible surface. It blocks direct and indirect forms of:

- score/reward/target/comparison; decoder or semantic algebra; observation or
  action ports; candidate/mutation grammar;
- component/boundary/tag/genome identity; seed/template/repair;
  viability/fitness; scheduler/copy/reproduction; evaluator writeback; and
  file/process/socket/IPC/network authority.

It permits only a uniformly applied local transport/conservation law plus
bounded time/space, with evaluator measurement recorded as `post_run_only`.
An absent manifest fails closed. Aliases, callbacks and any opaque encoded
capability field fail closed rather than relying on a spelling blacklist.

## Hostile fixtures and result

| Fixture kind | Result |
|---|---|
| Clean uniform exterior | allowed |
| Direct score, decoder callback, sensor/action ports | blocked |
| Alias reward, encoded seed/template, boundary tags | blocked |
| Candidate/mutation menu, repair, viability/scheduler | blocked |
| Evaluator writeback and process/file/socket bypass | blocked |

The canonical CSV reports 11 blocked fixtures and one permitted exterior
fixture, together with a per-row category, reason, provenance and manifest.

## Reproduction

```bash
zig build-exe sparse_poly_discovery/scaffold_audit_round_ah.zig -O ReleaseSafe \
  -femit-bin=/tmp/scaffold-audit-ah3
/tmp/scaffold-audit-ah3 selftest
/tmp/scaffold-audit-ah3 results/scaffold_audit_round_ah.csv
cmp results/scaffold_audit_round_ah.csv /tmp/scaffold_audit_round_ah_a.csv
```

## Boundary

This is an **independent release gate**, not self-certification by the mutant.
It tests a known finite vocabulary and deliberately seeded bypasses. A local
scanner cannot establish full OS isolation, discover arbitrary obfuscation, or
prove that source/binary/runtime behavior outside its manifest matches the
manifest. AH1/AH2 must supply runtime capability enforcement, and a later
independent hostile audit must inspect compiled artifacts, process boundaries,
runtime traces and the trusted computing base.
