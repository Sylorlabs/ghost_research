# I1 — search-response descriptor atlas (Round I)

> **Belongs to Round I, experiment I1.** Harness:
> `sparse_poly_discovery/search_response_atlas_round_i.zig`. Raw target-level
> output: `results/search_response_atlas_round_i.csv`.

## Verdict

**LIMITED POSITIVE FOR AN ATLAS; NOT AN ALLOCATOR RESULT.** A frozen
search-response descriptor contract, chosen on validation, separates all four
route types on its four validation targets (**4/4**).  Its untouched holdout
classification is **2/4**: global and singleton-directed are correct;
multi-cell partition-directed and no-grammar are confused.  This is above the
Round H static-descriptor result (1/4), but too small and too incomplete to
claim that a response-guided allocator works.

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

I1 supplies a predeclared response representation for I2/I3-style work.  It
does **not** establish a learned allocator, because the exact frozen holdout
score is only 2/4 and has the critical symmetric error: it neither admits the
held-out partition nor rejects the negative control.  A downstream allocator
must improve this on new held-out targets under the same 30-per-route budget,
and must report fixed/random allocation controls.  It may not select a
different contract after inspecting these holdout rows.

## Reproduce

```sh
cd sparse_poly_discovery
zig build-exe search_response_atlas_round_i.zig -O ReleaseFast -femit-bin=search_response_atlas_round_i
./search_response_atlas_round_i ../results/search_response_atlas_round_i.csv
./search_response_atlas_round_i selftest
```
