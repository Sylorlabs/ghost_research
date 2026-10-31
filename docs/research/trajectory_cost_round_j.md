# J3 — target-blind response-trajectory cost lower bound

## Question

Can a low-budget prefix of the exact directed grammar produce a cheap response
signal that separates directed targets from global/no-grammar targets, before
I2's full 2,540 candidate-call scan?  This is a cost measurement only; it does
not claim that an allocator works.

## Method

`sparse_poly_discovery/trajectory_cost_round_j.zig` enumerates the directed
grammar as exactly **1,270 asserted-unique candidates**: all nonempty,
non-full 8-cell masks (254) times the two legal mod-2 and three legal mod-3
residue choices (5).  It asserts both no duplicate and complete coverage for
three target-blind orderings: base, a frozen mask permutation, and a frozen
residue permutation.

For each of three frozen seeds and four target types (`global`, `singleton`,
`multicell`, `no_grammar`), each candidate receives one train and one
validation score.  So a prefix of B grammar members costs **2B candidate
calls**.  The sole response feature is the best train/validation-average
accuracy; it contains no target type, family, mask, or residue metadata.  A
predeclared `>= .999` response means “an exact directed member was found”; it
is scored after the fact only as directed-reach versus directed-absent
separation on the heldout test slice.

The raw CSV also includes four fixed-seed IID-with-replacement target-blind
controls per target/seed/budget.  They can duplicate candidates by design;
only the three grammar-prefix arms make the asserted-unique coverage claim.

## Raw frontier

Across the 9 asserted-unique prefix replications (3 seeds × 3 mask/residue
orders):

| Candidate calls | Singleton reach | Multi-cell reach | Global absent | No-grammar absent | All-type separation |
|---:|---:|---:|---:|---:|---:|
| 16–512 | 0/9 | 0/9 | 9/9 | 9/9 | 18/36 (50%) |
| 1,270 | 0/9 | 6/9 | 9/9 | 9/9 | 24/36 (66.7%) |
| 2,540 | 9/9 | 9/9 | 9/9 | 9/9 | 36/36 (100%) |

The IID control is weaker as expected: at the 2,540-call horizon it reaches
singleton 9/12 and multi-cell 9/12, while negatives remain absent 12/12.  At
1,270 calls it reaches singleton 2/12 and multi-cell 2/12.  It does not create
a cheaper reliable response signal.

## Result

**Negative for cheap response admission.**  No low-budget prefix (up through
512 calls) reaches either directed type in any asserted-unique replication.
At half scan (1,270 calls), multi-cell is only 6/9 and singleton remains 0/9.
The first cost that separates all heldout target classes reliably is the full
**2,540 calls**, exactly I2's full-scan reference—not an efficiency gain.

This is a lower bound for this response family, not a claim that all possible
dynamic search traces fail.  It rules out treating a target-blind prefix best
score from this 1,270-member grammar as the cheap admission representation
Round J needs.

## Reproduction

```bash
cd sparse_poly_discovery
zig build-exe trajectory_cost_round_j.zig -O ReleaseFast -femit-bin=trajectory_cost_round_j
./trajectory_cost_round_j
```

This deterministically writes `results/trajectory_cost_round_j.csv`.
