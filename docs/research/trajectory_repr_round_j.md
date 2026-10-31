# J2 — corrected trajectory / near-miss representation

**Verdict: positive, narrowly.** A correctly enumerated cheap prefix-search
trajectory representation separates all four frozen held-out routes
(**4/4**, strictly above I1's invalidated 2/4 diagnostic) while consuming
**216 candidate calls per target**: 204 training-prefix calls and 12
validation calls.  This is 8.5% of I2's 2,540-call train-plus-validation
near-solve scan.  It is a representation result, **not** an allocator or
general-autonomy result.

Harness: `sparse_poly_discovery/trajectory_repr_round_j.zig`.  Raw output:
`results/trajectory_repr_round_j.csv`.

## Question

Can a valid, low-cost response representation distinguish global,
singleton-directed, multi-cell-directed, and no-grammar targets without using
identity or answer metadata?

## Frozen protocol

- Twenty targets retain I1's 12/4/4 train/validation/held-out structure: three
  training, one validation, and one held-out target in each of the four route
  classes.  The class/target definitions are oracle-only; the representation
  consumes neither target name nor formula, family, anchor, mask, residue, nor
  audit label.
- For each target, four fixed prefix banks are evaluated on 450 labeled search
  examples: 30 global candidates, 48 singleton candidates, 120 directed
  candidates, and six adjacency/no-grammar candidates.  The directed prefix
  is a fixed affine permutation `(809*i+113) mod 1270` of the exact grammar.
- Each bank emits only predeclared search observables: quarter-prefix and
  half-prefix validation gain, best gain, best-vs-runner-up near-miss margin,
  held-out-in-bank candidate diversity, and selected-candidate validation gain.
  The nearest-centroid classifier sees the concatenated 24 observables.
- Its cost is explicitly charged as 204 prefix training candidate evaluations
  plus 12 selected-candidate validation evaluations = 216.  Routing,
  selection, and certification are deliberately **not** charged or performed:
  J2 has not allocated a post-response search budget or promoted a discovery.
- The directed enumerator asserts every one of the `254 * (2 + 3) = 1270`
  semantic keys exactly once.  Two coprime affine orderings are checked as
  mask/residue permutation controls: membership stays fixed while ordering is
  bijective.  The harness reruns deterministically (`selftest`) and checks the
  frozen descriptor-distance guard.

## Deployment label availability

The representation uses labels for the target's predeclared search examples to
score candidate hypotheses.  It is deployable only in a setting where a
candidate evaluator / verifier can score such examples *before* routing.  It
does not assume labels are available for an otherwise unlabeled target; no
claim is made for that setting.  Identity-like target metadata remains
forbidden at both training and inference.

## Result

| Held-out route | Prediction | Correct |
|---|---|---|
| global | global | yes |
| singleton | singleton | yes |
| multi-cell | multicell | yes |
| no-grammar | none | yes |

The raw CSV records every non-training target, all eight headline
gain/margin values, cost components, permutation status, and the summary
`4/4`.  The smallest Euclidean descriptor distance from a non-training row to
a training row is `0.117505`, above the predeclared `0.03` copied-row guard.

## Interpretation and limits

This clears J2's narrow acceptance bar: it is uniquely enumerated, cheaper
than the full scan, uses only declared trajectory observables, survives the
implemented order-permutation/integrity checks, and exceeds I1's 2/4.

It does **not** establish that the representation will beat fixed allocation.
The four route banks are deliberately complete/small for global, singleton,
and adjacency features, while only the directed bank is a 120/1270 prefix.
Thus J4 must use the exact frozen features and charge its response plus
selection calls against fixed, random, and target-blind controls.  J5 must
also independently challenge whether the target construction or prefix order
provides answer-shaped access.

### I5 audit update

Round J I5 confirms the sampler keys and fixed prefix membership are valid, but
narrows this result further: the 120-member directed prefix's best response is
order-sensitive across valid affine/identity orders (0.5667, 0.5689, 0.6178),
and the stated `none` class is an explicit adjacency grammar rather than an
arbitrary no-grammar control. Therefore retain this only as a **fixed-order,
labelled-evaluator signature on the supplied four route families**; do not use
it as permutation-robust general routing evidence.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/trajectory_repr_round_j.zig -O ReleaseFast -femit-bin=trajectory_repr_round_j
./trajectory_repr_round_j results/trajectory_repr_round_j.csv
./trajectory_repr_round_j selftest > /tmp/trajectory_repr_round_j.selftest.csv
cmp results/trajectory_repr_round_j.csv /tmp/trajectory_repr_round_j.selftest.csv
```
