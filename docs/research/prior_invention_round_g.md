# G4 — prior invention from a failure signature

> Round G experiment G4. Scoped artifacts: `sparse_poly_discovery/prior_invention_round_g.zig` and `results/prior_invention_round_g.csv`.

**Verdict:** **a constrained positive, not full primitive invention.** From a
fixed, target-agnostic instruction alphabet, the proposer selected and
instantiated a directed partition-comparison/residue grammar which exactly
solved a genuinely new binary target on three measurement seeds and a held-out
fourth seed. It beat both the fixed-menu and random-search controls. It has
*not* invented a new primitive: compare/partition/aggregate/modulo were still
provided by the human as the frozen alphabet. This demonstrates grammar-level
prior formation and parameter discovery, not escape from the alphabet-level
human limitation.

## Question and pre-run contract

Can search propose a useful structural-prior grammar after a pre-existing menu
fails, rather than receiving a named family or a hand-selected member?

The fixed protocol is 7,000 iid grids of eight integer cells (values 0–5),
with disjoint train/validation/test slices of 3500/1750/1750. Three measurement
seeds are fixed in the harness and `0xA71C0000000000A4` is the held-out seed.
The target is binary and non-degenerate: `rank(cell 3) mod 3 == 1`, where rank
is the number of other cells lower than cell 3. This target and seed do not
occur in the F2 ORDER2 artifact. The proposer does not take the target's name,
definition, a correct anchor, a family identifier, or a preferred residue as
input; labels are available solely through the common candidate-scoring API.

The alphabet is deliberately small and frozen before runs:

- value-threshold counts (the fixed-menu control);
- directed partition comparisons;
- aggregation to a count;
- residue equality for moduli 2 and 3.

The failure signature is operational rather than semantic: threshold-count
features never reach 0.75 validation accuracy while inexpensive pairwise
orientation probes retain high residual dependence. That selects the generic
`directed_partition_compare_mod` grammar. The grammar is then instantiated
symmetrically over 254 nontrivial masks, both moduli, and every legal residue:
1,270 candidates per seed. No cell mask is privileged. Candidate choice uses
only validation scores; test scores are recorded after choice.

The grammar's directed partition statistic is
`#{(i,j): i in S, j not in S, grid[i] > grid[j]}`. The winning `S={3}` is
therefore discovered as a parameter, not supplied as an “anchor 3” option.

## Results

| split | seed | proposed mask | modulus/residue | fixed-menu validation | random-24 mean validation | selected validation | held-out test | reference reconstruction proxy |
|---|---|---:|---|---:|---:|---:|---:|---:|
| measurement | `...0001` | `0x08` | 3 / 1 | 0.635 | 0.624 | 1.000 | 1.000 | 0.711 |
| measurement | `...0002` | `0x08` | 3 / 1 | 0.640 | 0.625 | 1.000 | 1.000 | 0.689 |
| measurement | `...0003` | `0x08` | 3 / 1 | 0.642 | 0.627 | 1.000 | 1.000 | 0.703 |
| **held-out** | `...00A4` | `0x08` | 3 / 1 | 0.647 | 0.604 | **1.000** | **1.000** | 0.723 |

`0x08` is selected by scoring, and happens to be singleton cell 3. The
proposed statistic equals rank(cell 3); residue 1 exactly matches the binary
oracle. Base rates are 0.284–0.295, so the binary/non-degeneracy gate passes.
The fixed menu is its best member among threshold-count/residue features;
random is the mean best validation result of twenty independent 24-candidate
uniform grammar draws. Both use the same validation slice and candidate budget
discipline stated in the harness.

The CSV contains the full 5,080-candidate exhaustive ledger plus its four
summary rows. Its `grammar_enumeration` rows include each candidate's
validation and independently measured test accuracy. The test column was not
read by `propose`.

## Validity and certification gates

| gate | threshold | result |
|---|---|---|
| binary/non-degenerate target | base rate strictly 0.10–0.90 | pass: 0.284–0.295 |
| own-prior reachability | validation and test >= 0.90 | pass: 1.000 on all four seeds |
| no fixed-precedence label | exhaustive score selection only | pass: mask/residue unlabelled and symmetric |
| held-out evidence | seed never used to choose grammar parameters | pass: `...00A4`, 1.000 test |
| control separation | exceeds fixed and random arms | pass: 1.000 vs <=0.647 / <=0.627 |
| novelty intent | existing-reference multi-feature reconstruction < 0.90 | pass: 0.689–0.723 proxy |

The final row is deliberately **not called G1 certification**. G1's corrected
multi-feature COVER gate has not yet been accepted or frozen. This harness
uses a conservative, independently implemented two-feature reconstruction
proxy (global threshold count and global inversion-residue, fitted on train)
to exercise the same intent: distinguish a new local directed-comparison
feature from a reconstruction of existing global summaries. Once G1 lands,
its accepted gate must be re-run before G4's candidate is allowed into G5.

## Reproduction

From `sparse_poly_discovery/` with Zig 0.14.1:

```sh
zig build-exe prior_invention_round_g.zig -O ReleaseFast -femit-bin=prior_invention_round_g
./prior_invention_round_g
sed -n '1p;$p' ../results/prior_invention_round_g.csv
```

The run is single-threaded, CPU-only, and completed in about two seconds here.

## Limits

1. This is one clean held-out target within the same small iid-grid substrate,
   not an unseen *structural family*. It cannot establish broad prior invention.
2. The language already contains the primitive that the target needs. The
   human supplied the alphabet and the high-level decision to probe pairwise
   orientation; the machine supplied only grammar instantiation/selection.
3. The target is exact enough that exhaustive search finds a sharp winner. A
   more combinatorial grammar space may need a stronger failure-signature
   learner and separate search-budget controls.
4. The reference reconstruction proxy is not the accepted G1 gate. Do not
   promote this feature into the production library until its G1 re-check.
5. Random control samples only 24 candidates while the proposed arm exhausts
   1,270. That intentionally measures “guided exhaustive grammar search”
   against a bounded blind budget; it is not an equal-evaluation claim. G5
   must normalize evaluation budget when comparing autonomous systems.
