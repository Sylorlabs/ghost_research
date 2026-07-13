# L1 — trace-only failure-space atlas

**Verdict: limited positive representation result; not autonomous map-making.**

L1 creates a small, declared, deterministic trace corpus and demonstrates that
an atlas built only from candidate-outcome histograms forms stable regions which
predict a post-freeze held-out property above a majority baseline. It does not
infer a problem family from real unknown targets, invent an operator, or use
the result to improve discovery allocation.

Harness: `sparse_poly_discovery/failure_atlas_round_l.zig`.
Raw ledger: `results/failure_atlas_round_l.csv`.

## Protocol

- Thirty synthetic evaluator episodes, each with 64 pre-254-call score bins;
  18 training and 12 heldout. The only admissible input is the four-bin outcome
  histogram. There are no target IDs/formulas, route labels, candidate IDs,
  masks, grammar fields, or audit fields in the feature record.
- Three predeclared regions: rapid improvement, slow improvement, and flat
  response. Cluster rules use histogram counts only: many score-3 outcomes is
  `rapid`; many score-0 outcomes is `flat`; the remainder is `slow`.
- The held-out property is whether the episode reaches an exact result by 254
  calls. This outcome is not a feature. The training-derived cluster/outcome
  mapping is `rapid/slow -> solve`, `flat -> no solve`.
- Each trace is checked under reversed candidate order; the histogram and
  cluster must be identical. The generator gives every trace a distinct
  multiset, and a duplicate guard rejects any copied trace. Mask/route/formula
  fields are absent by construction; the CSV records this fact.

## Result

The frozen heldout split is **12/12 atlas prediction**, against the
always-solve majority baseline **8/12**. The result satisfies L1's narrow
success condition: stable clusters predict a trace outcome above a simple
baseline. It is intentionally a controlled representational test, not evidence
that a system can discover real semantic territories without supplied scoring
traces.

## Reproduce

```bash
rm -rf /tmp/l1-cache /tmp/l1-global /tmp/failure_atlas_round_l
zig build-exe sparse_poly_discovery/failure_atlas_round_l.zig -O ReleaseFast \
  --cache-dir /tmp/l1-cache --global-cache-dir /tmp/l1-global \
  -femit-bin=/tmp/failure_atlas_round_l
/tmp/failure_atlas_round_l results/failure_atlas_round_l.csv
/tmp/failure_atlas_round_l selftest > /tmp/failure_atlas_round_l.selftest.csv
cmp results/failure_atlas_round_l.csv /tmp/failure_atlas_round_l.selftest.csv
```

## Limits

This is not a target-blind capability. The evaluator still has to generate
meaningful scored outcomes; the three trace regimes are designed rather than
discovered; and the trace property is correlated with score distribution by
construction. The next map experiment must make clusters transfer across a
real, sealed family corpus and test whether an atlas changes a downstream
family-invention choice.
