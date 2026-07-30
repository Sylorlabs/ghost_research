# P1 — score-private campaign vault

**Verdict: IMPLEMENTATION FOUNDATION VERIFIED.** P1 supplies an evaluator-owned
campaign boundary for Round P. The policy may retain permitted anonymous
calibration observations and its own generic commitments, but it never receives
or stores a target identity, target-to-tool link, hidden formula/family/parameter,
per-target fresh-test score/label, or winner. Individual fresh outcomes remain
inside the evaluator; only unjoinable aggregate campaign totals are released
after all sessions close.

Harness: `sparse_poly_discovery/score_private_vault_round_p.zig`. Public
policy-memory/campaign-closure artifact: `results/score_private_vault_round_p.csv`.

## Boundary

The evaluator privately holds eight opaque records and a persistent three-call
budget per record. For each anonymous session, policy memory can receive a
generic context, one permitted calibration reply (`calibration_low` or
`calibration_high`), and a commitment record. It cannot serialize a session
token, target ID, hidden relation, tool name, or fresh outcome. The evaluator
checks the commitment against its hidden record but retains that individual
result. After all eight sessions close, it releases only `exact_total_8_of_8`
and total charged calls.

This design intentionally permits useful *experience* (a calibration response
and a causal note) while preventing memory from becoming a per-target answer
table. The public CSV contains no row key capable of joining a calibration
reply or commitment to an evaluator record.

## Verification

- canonical schema rejects identity, target, formula/family/parameter, fresh
  score/label, winner, tool-link, manifest, and secret fields;
- adversarial recovery fixture reports zero identity joins and zero fresh-outcome
  recoveries from public exports;
- evaluator-owned persistent counter rejects a restart/over-budget attempt for
  all eight sessions;
- forward and reverse evaluator traversal produce byte-identical public
  artifacts;
- privacy scan rejects private field names in the export.

## Limit

This is **protocol isolation**, not OS/process isolation: the evaluator and
policy model reside in one deterministic harness for reproducibility. A
production-strength campaign should move the evaluator state into a separately
managed process or service. P1 proves the schema and information-flow contract;
it does not by itself prove tool invention.

## Reproduce

```bash
rm -rf /tmp/zig-p1-cache /tmp/zig-p1-global /tmp/score_private_vault_p1
zig build-exe sparse_poly_discovery/score_private_vault_round_p.zig -O ReleaseFast \
  --cache-dir /tmp/zig-p1-cache --global-cache-dir /tmp/zig-p1-global \
  -femit-bin=/tmp/score_private_vault_p1
/tmp/score_private_vault_p1 run results/score_private_vault_round_p.csv
/tmp/score_private_vault_p1 selftest
```
