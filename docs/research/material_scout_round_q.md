# Q2 — Failure-driven material scout

**Verdict: CONTROLLED POSITIVE.** Q2 searches an approved typed material
universe using only public material passports and anonymous, answer-free causal
failure summaries. It retrieves the material suitable for each held-out
calibration request without receiving an identity, target formula, family,
individual evaluation result, or target-to-material record.

Harness: `sparse_poly_discovery/material_scout_round_q.zig`. Ledger:
`results/material_scout_round_q.csv`.

## Aggregate closure

| Policy | Held-out retrieval | Charged cost |
|---|---:|---:|
| Failure-driven scout | **12/12** | 2/request |
| Frozen material prior | 4/12 | 2/request |
| Blind cyclic request | 4/12 | 2/request |

The fixture has three approved public passports: a bounded aggregate fold, a
pair-relation fold, and an ordered-transition fold. Each anonymous request
provides a causal residual summary (`cardinality`, `pairwise`, or `transition`)
and the scout ranks a matching passport. This is a deliberately bounded proof
of *material retrieval*, not a claim of open-world discovery: the material
universe and public descriptor vocabulary are supplied.

## Boundary and controls

- **Answer-free:** the CSV uses `anonymous_event` rather than an identity; it
  contains no formula, family, hidden relation, individual fresh score, winner,
  or target-to-material lookup. Only campaign aggregate totals are released.
- **Public provenance:** each candidate carries an approved-source and typed
  capability passport. The policy uses no evaluator source/state or private
  manifest.
- **Equal persistent cost:** every arm receives exactly one passport inspection
  and one pre-evaluation request per anonymous calibration request (72 action
  rows total).
- **Controls:** a frozen aggregate-material prior and a blind cyclic material
  request each obtain 4/12. Arrival reversal leaves the aggregate conclusion
  unchanged; an identical descriptor under a different source ordering cannot
  change the choice.
- **Limits:** residual categories are supplied and aligned to the three public
  capability descriptors. Q2 does not yet search an external corpus, acquire a
  genuinely new primitive, or forge a material. Those are Q1/Q3/Q4/Q5 gates.

## Reproduce

```bash
rm -rf /tmp/zig-q2-cache /tmp/zig-q2-global /tmp/material_scout_q2
zig build-exe sparse_poly_discovery/material_scout_round_q.zig -O ReleaseFast \
  --cache-dir /tmp/zig-q2-cache --global-cache-dir /tmp/zig-q2-global \
  -femit-bin=/tmp/material_scout_q2
/tmp/material_scout_q2 run results/material_scout_round_q.csv
/tmp/material_scout_q2 selftest
```
