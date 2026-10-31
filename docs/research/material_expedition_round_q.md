# Q5 — autonomous provenance-safe material expedition

**Verdict: CONTROLLED STRICT POSITIVE.** On a post-policy-freeze,
evaluator-owned 24-session suite spanning three independent cohorts, the full
expedition uses only anonymous answer-free residuals, Q1 public passports, and
Q3 admission rules. It scouts a material, verifies its provenance, forges a
lineaged intermediate primitive, makes a generic measurement, and freezes its
tool before sealed scoring. Fresh per-session outcomes never enter the public
ledger or policy-visible state.

Harness: `sparse_poly_discovery/material_expedition_round_q.zig`. Public
aggregate-only ledger: `results/material_expedition_round_q.csv`.

## Aggregate closure

| Equal persistent-cost arm | Aggregate fresh acceptance | Cost |
|---|---:|---:|
| Full material expedition | **24/24** | 6/session |
| Pre-expedition raw/fixed control | 0/24 | 6/session |
| Blind material/forge control | 8/24 | 6/session |
| No-expedition prior | 0/24 | 6/session |

The full arm is 8/8 in each evaluator-owned cohort. This is a strict win over
all controls at identical charged cost, but remains a bounded synthetic result:
the approved material registry, residual vocabulary, generic measurement slot,
and evaluator contract are supplied.

## What the expedition is allowed to use

The policy receives an anonymous residual descriptor and public Q1 passports
only. Its Q2-style scout selects a provenance-qualified source; Q3-style
quarantine verifies lineage, content identity, aliases, and source safety; the
forge constructs the canonical content-addressed combination:

```text
forge(cf4ccde68a0fdf19 + 3a8490803f0413dd + 6c8b9e7a5d2f4301)
```

It cannot read evaluator source/state, private task structure, individual
result, per-session winner, formula, manifest, or an answer join. Each arm
still pays for scout, quarantine, forge, measurement, commitment, and sealed
test (six calls), followed by a rejected seventh call demonstrating persistent
budget enforcement.

## Controls and replay gates

- Every scout/quarantine/forge/measurement/commit/test action is an individual
  ledger row; the score is withheld from those rows and released only as
  campaign aggregate closure.
- Traversal reversal byte-compares exactly. Public residuals are normalized;
  arrival order cannot affect selection.
- The selftest checks private-vocabulary absence, complete 675-row accounting,
  canonical lineage, aggregate outcome, and order independence.
- The content passport, rather than a label, is the identity: alias and
  renamed-material routes resolve to the same fingerprint before admission.
- No post-test candidate selection is possible: the commitment precedes the
  sealed test and no individual answer is emitted.

## Limit

This demonstrates an auditable self-expanding supply-chain loop *within the
approved fixture universe*. It does not establish unrestricted web/corpus/world
exploration, nor prove that an arbitrary external discovery can be quarantined
and transferred. Q6 must independently attack provenance, privacy, aliases,
cost accounting, and this interpretation.

## Reproduce

```bash
rm -rf /tmp/zig-q5-cache /tmp/zig-q5-global /tmp/material_expedition_q5
zig build-exe sparse_poly_discovery/material_expedition_round_q.zig -O ReleaseFast \
  --cache-dir /tmp/zig-q5-cache --global-cache-dir /tmp/zig-q5-global \
  -femit-bin=/tmp/material_expedition_q5
/tmp/material_expedition_q5 run results/material_expedition_round_q.csv
/tmp/material_expedition_q5 selftest
```
