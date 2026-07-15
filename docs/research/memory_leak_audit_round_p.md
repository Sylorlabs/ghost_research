# P3 — memory leakage red-team audit

**Verdict: CONFIRMED, NARROWED.** The canonical policy-visible experience
record contains only attempt, aggregate observation, residual, hypothesis, and
charged cost. Independent fixed attacks recover hidden target identity at its
predeclared 1/12 chance rate and the balanced binary hidden fields at 6/12.
All eight forbidden/injected field names are deterministically quarantined.

Harness: `sparse_poly_discovery/memory_leak_audit_round_p.zig`. Ledger:
`results/memory_leak_audit_round_p.csv`.

## Attacks

- identity fingerprinting, token and record-order permutations, and duplicate
  records: public signatures are deliberately fourfold duplicate and contain no
  target token;
- balanced recovery attempts for hidden family, per-target fresh score, winning
  tool, and target-to-tool association: all are at fixed chance baselines;
- schema/free-text injection: `target_token`, family, final score, winner,
  target-to-tool association, manifest, and answer-bearing free text are
  deleted before a record can enter the memory store;
- answer-side joins and campaign persistence: `PublicRecord` has no target or
  answer foreign key; closed campaigns export aggregate-only information.

## What this does and does not prove

This is a reproducible *fixture and protocol* audit. It shows the supplied
schema has no answer join path and that its stated attacks remain at chance. It
does **not** prove cryptographic secrecy, defend an adversary who can read the
evaluator process/filesystem, or establish that a different future memory
representation is safe. P1 must provide the evaluator-owned score-private
boundary; P3 is the red-team test that prevents policy memory from becoming an
answer sheet.

## Reproduce

```bash
rm -rf /tmp/zig-p3-cache /tmp/zig-p3-global /tmp/memory_leak_audit_round_p
zig build-exe sparse_poly_discovery/memory_leak_audit_round_p.zig -O ReleaseFast \
  --cache-dir /tmp/zig-p3-cache --global-cache-dir /tmp/zig-p3-global \
  -femit-bin=/tmp/memory_leak_audit_round_p
/tmp/memory_leak_audit_round_p run results/memory_leak_audit_round_p.csv
/tmp/memory_leak_audit_round_p selftest
```
