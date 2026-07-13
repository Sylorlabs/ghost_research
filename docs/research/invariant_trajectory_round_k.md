# K2 — permutation-invariant trajectory features

**Verdict: limited positive representation result; not an allocator result.**
The harness constructs an order-invariant score-distribution response vector
from four predeclared grammar banks.  On the frozen four-route held-out split it
separates **4/4** global, singleton, multi-cell-directed, and adjacency routes
at **254 charged candidate calls per target**.  This is below the 2,540-call
full directed train-plus-validation scan, but it is still evaluated only on the
supplied synthetic route families and has not beaten the human fixed policy.

Harness: `sparse_poly_discovery/invariant_trajectory_round_k.zig`.
Raw results: `results/invariant_trajectory_round_k.csv`.

## Question

Can a trajectory representation avoid J2's fixed-useful-prefix dependence by
using only permutation-invariant distributions of candidate outcomes—score
improvements, near-miss margins, validation residual change, diversity, and
charged cost—rather than candidate position or a target's descriptive fields?

## Frozen protocol

- The corpus is the frozen 12/4/4 split: three train, one validation, and one
  held-out target in each of global, singleton, multi-cell-directed, and
  adjacency-route classes.  Route and target fields are oracle-only reporting
  labels.  The feature extractor and classifier receive no target name,
  formula, family, anchor, mask, residue, split, or audit metadata.
- The candidate evaluator receives the target's **predeclared labelled search
  examples**.  Thus this is deployable only where such examples can be scored
  before routing; it makes no claim for an otherwise unlabelled target.
- Banks are sets, never useful prefixes: 25 complete global candidates, 40
  complete singleton candidates, 180 directed candidates from 36 affine-spaced
  mask strata times every one of five legal modulus/residue flavours, and five
  adjacency candidates.  The 180 directed calls are 7.1% of the 2,540-call
  directed near-solve scan.
- For each bank, the extractor records six predeclared set statistics: mean
  gain above majority baseline, score standard deviation, best gain, best minus
  runner-up near-miss margin, deterministic-best validation residual change,
  and fraction scoring at least 0.70.  These form a 24-value vector.
- Candidate tie breaks use a canonical semantic key, never encounter order.
  Every target is recomputed under reversed bank order and exact equality of all
  24 features is asserted.  The full directed grammar's 1,270 canonical keys
  are asserted unique.  Complete five-flavour strata make residue-flavour
  ordering immaterial; the existing mask and residue permutation controls
  assert that those transforms preserve the full key universe.
- Cost is charged as 250 training candidate evaluations plus four validation
  evaluations, total **254**.  No post-routing selection, certification, or
  promotion is performed.

## Results

| Held-out oracle route | Prediction | Correct | Calls |
|---|---|---:|---:|
| global | global | yes | 254 |
| singleton | singleton | yes | 254 |
| multi-cell-directed | multicell | yes | 254 |
| adjacency route | none | yes | 254 |

The raw CSV includes all non-training rows, distributional gain/near-miss
columns, each cost component, exact-enumeration and invariance gates, 4/4
summary, and the copied-row distance guard (`0.097089`, above the frozen 0.03
floor).  `selftest` reproduces the CSV byte-for-byte.

## Ablations and interpretation

| Representation | Order dependence | Held-out separation | Cost |
|---|---|---:|---:|
| J2 fixed affine prefix | yes (audit-narrowed) | 4/4 supplied routes | 216 |
| K2 set-distribution response | reverse-order asserted invariant | 4/4 supplied routes | 254 |
| J3 target-blind cheap prefixes | not sufficient | negative | below full scan |
| I2 full partition coverage | not cheap admission | coverage only | 2,540 |

K2 removes the specific *candidate-order* defect in J2: candidate sequence
cannot alter its features or deterministic selected validation score.  It does
not establish that the chosen bank set is mask-general, that the four supplied
families are broad enough, or that a policy using these features beats fixed
coverage.  K3/K4 must test those claims on fresh randomized hidden structures
with response cost included in every arm; K5 must independently attack bank
membership and label-availability assumptions.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/invariant_trajectory_round_k.zig -O Debug \
  -femit-bin=/tmp/invariant_trajectory_round_k \
  --cache-dir /tmp/k2-cache --global-cache-dir /tmp/k2-global
/tmp/invariant_trajectory_round_k results/invariant_trajectory_round_k.csv
/tmp/invariant_trajectory_round_k selftest > /tmp/invariant_trajectory_round_k.selftest.csv
cmp results/invariant_trajectory_round_k.csv /tmp/invariant_trajectory_round_k.selftest.csv
```

## Limits

This is deliberately not called autonomous prior selection.  It uses labelled
evaluator examples, human-supplied grammar banks, a small frozen corpus, and
oracle route labels during training/evaluation.  Its only accepted claim is
that the **feature values themselves** are set-distribution and reverse-order
invariant under the stated fixed bank and that they separate this corpus at a
cost materially below a full directed scan.
