# Q3 — material quarantine and provenance audit

**Verdict: PASS — protocol/material safety foundation.** Q3 supplies a
deterministic admission boundary for materials discovered by a future scout. It
is intentionally not a solver result: it establishes that a growing material
universe cannot silently become an answer channel or a renamed duplicate rack.

Harness: `sparse_poly_discovery/material_quarantine_round_q.zig`. Public,
answer-safe ledger: `results/material_quarantine_round_q.csv`.

## Admission result

| Outcome | Count |
|---|---:|
| Admitted provenance-qualified materials | **2/11** |
| Rejected candidate materials | 9/11 |
| Charged admission inspections | 11 |

The admitted material fingerprints are structurally distinct and come only
from bounded local-corpus or simulator adapters. The public ledger stores a
material identifier, broad origin class, content fingerprint, decision, reason
code, charged inspection, and provenance-digest state. It never records a
task identity, hidden relationship, per-item evaluation, final winner, or
task-to-material link.

## Attacks required to fail closed

| Attack | Outcome |
|---|---|
| Missing or forged provenance digest | rejected |
| Content alias under a new material name | rejected as `DUPLICATE_CONTENT` |
| Evaluator-private or answer-bearing source | rejected as `FORBIDDEN_ORIGIN` |
| Correlated metadata / private join | rejected |
| Selection after sealed evaluation | rejected |
| Unbounded free-text "material" | rejected |
| Restart or arrival permutation | byte-identical ledger |
| Under-counted admission cost | selftest fails on ledger line count |

The correlation and join checks model a conservative rule: any candidate whose
metadata can be joined to private evaluation state, or whose metadata carries a
nonzero hidden-outcome association, is quarantined rather than heuristically
"corrected." This is stricter than a normal package registry by design.

## Meaning and limit

Q3 makes material discovery auditable: a scout may discover candidates, but it
cannot import an opaque snippet, a post-test-picked component, or evaluator
knowledge and call that discovery. It does **not** show that the scout can find
useful materials—that is Q2/Q4/Q5 territory. It is the supply-chain safety
gate that makes later usefulness claims interpretable.

## Reproduce

```bash
rm -rf /tmp/zig-q3-cache /tmp/zig-q3-global /tmp/material_quarantine_q3
zig build-exe sparse_poly_discovery/material_quarantine_round_q.zig -O ReleaseFast \
  --cache-dir /tmp/zig-q3-cache --global-cache-dir /tmp/zig-q3-global \
  -femit-bin=/tmp/material_quarantine_q3
/tmp/material_quarantine_q3 run results/material_quarantine_round_q.csv
/tmp/material_quarantine_q3 selftest
```
