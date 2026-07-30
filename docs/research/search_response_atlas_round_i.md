# I1 — search-response descriptor atlas (Round I)

> **Belongs to Round I, experiment I1.** Harness:
> `sparse_poly_discovery/search_response_atlas_round_i.zig`. Raw target-level
> output: `results/search_response_atlas_round_i.csv`.

## Verdict

**SUPERSEDED / NOT A VALID DOWNSTREAM ATLAS.** The original run appeared to be
a limited positive (4/4 validation, 2/4 holdout), but Round I I5 independently
found a material enumeration-integrity defect in its partition micro-search:
the harness declares 1,524 candidates for a grammar containing 1,270 and
duplicates 254 mod-3/residue-2 members. The claimed equal/uniform 30-candidate
partition probe is therefore false. Preserve the raw result as a diagnostic,
but do not use it as a frozen descriptor contract or evidence of clean
response-guided routing.

The useful result is narrow: equal-budget searches expose enough observable
response to distinguish some reachable structures without target names or
formula fields.  The important edge remains multi-cell partition admission:
the 30-probe partition micro-search misses the held-out member, and a
no-grammar control can have a superficially similar weak response.

## Frozen protocol

- The corpus has **20** independently regenerated binary targets: three train,
  one validation, and one untouched holdout target for each of global
  threshold, singleton-directed, multi-cell partition-directed, and
  irrelevant/no-grammar routes (**12/4/4**).
- For every target, four generic micro-searches receive exactly **30**
  candidate evaluations: global count/residue, singleton rank/residue,
  partition-crossing/residue, and an irrelevant adjacency/residue route.
  Large menus are deterministically evenly subsampled; no route wins through
  more evaluations.
- The only descriptor fields are each micro-search's observed validation gain,
  residual/error, candidate coverage, and normalized cost.  Target ID, route,
  formulas, pivots, masks, and residues are present only in the data generator
  or audit columns—not in the descriptor/classifier path.
- Route centroids are computed from the 12 train descriptors.  Contract choice
  happens on validation only; heldout is printed after that choice.  The
  train-to-nontrain descriptor-distance guard is **0.038243 >= 0.03**, so no
  target has a copied/identical response row.

## Descriptor ablations

| Contract | Inputs | Validation | Selection |
|---|---:|---:|---|
| `gain4` | one validation gain per route | 2/4 | rejected |
| `gain_residual8` | gain + residual per route | 4/4 | frozen selected contract |
| `full_response16` | gain, residual, coverage, cost per route | 3/4 | rejected |

| Heldout route (audit-only) | Selected prediction | Correct |
|---|---|---:|
| global | global | 1 |
| singleton-directed | singleton-directed | 1 |
| multi-cell partition-directed | no-grammar | 0 |
| no-grammar | partition-directed | 0 |

## What this enables and does not enable

I5 invalidates I1 as a predeclared response representation for I2/I3-style
work. Even before that audit, its 2/4 holdout score had the critical symmetric
error of neither admitting the held-out partition nor rejecting the negative
control. A successor must correct the 1,270-member enumeration, separate the
availability of probe labels from final-evaluation labels, and test residue/mask
permutation controls before any allocation claim.

## Reproduce

```sh
cd sparse_poly_discovery
zig build-exe search_response_atlas_round_i.zig -O ReleaseFast -femit-bin=search_response_atlas_round_i
./search_response_atlas_round_i ../results/search_response_atlas_round_i.csv
./search_response_atlas_round_i selftest
```
