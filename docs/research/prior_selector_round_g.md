# G3 — learned structural-prior selector (Round G)

> **Belongs to Round G, experiment G3.** Harness:
> `sparse_poly_discovery/prior_selector_round_g.zig`. Raw results:
> `results/prior_selector_round_g.csv`. Input corpus: G2's frozen
> `results/prior_corpus_round_g.csv`.

## Verdict

**VALID NEGATIVE: this six-descriptor 1-NN selector does not remove the human
prior-choice bottleneck.** All protocol/leakage gates pass, yet the selected
model reaches **0/4** on G2's untouched held-out targets, below the fixed
`thresh` order (**1/4**) and this frozen random draw (**0/4**; the exact
uniform expectation is 1/4). Therefore G5 must not treat G3 as a learned
routing component or use it to claim autonomous prior selection.

This is a result about the frozen descriptor/model combination, not proof that
prior selection is impossible. The result does rule out presenting the current
six cheap behavioural measurements plus a 12-row nearest-neighbour learner as
the missing generator-of-generators.

## Frozen protocol and isolation

- The selector receives **only** G2 columns `d0_rate`, `d1_count2corr`,
  `d2_sumcorr`, `d3_invcorr`, `d4_runcorr`, and `d5_localmaxcorr`.
- Target text, formula, target id/order, source block, audit label, and
  designated prior are excluded from `choose1nn`. `truth` is accessed only by
  the post-selection witness evaluator, exactly as a held-out target oracle
  would score a selected grammar.
- Train/validation/test are exactly G2's frozen **12/4/4** targets. Training
  standardization uses train rows only. 1-NN was selected on validation only:
  2/4, versus 1/4 for a class-centroid alternative. No held-out result
  influenced model selection.
- The harness independently repeats G2's standardized nearest train-to-nontrain
  descriptor-distance check: **0.792634 > 0.05**. It also checks the frozen
  12/4/4 cardinality. Both pass.

## Equal-budget comparison

Each arm receives 20 designated-grammar witness evaluations for each target.
A selected prior reaches 1.000 only when its grammar contains that target's
exact witness; a nonmatching grammar gets 0.000. This deliberately uniform
evaluation isolates *routing* rather than conflating it with a new search
implementation.

| Arm | Per-target search evaluations | Routing work, reported separately | Held-out exact reach |
|---|---:|---:|---:|
| Learned, train-standardized 1-NN | 20 | 6 frozen descriptor measurements | 0/4 |
| Fixed menu order (`thresh` first) | 20 | 0 | 1/4 |
| Random prior | 20 | 1 RNG draw | 0/4 on frozen permutation; 1/4 uniform expectation |

The random arm uses the predeclared permutation `run, ratio, thresh, mixr` on
the four held-out rows. Its seed-specific 0/4 outcome is retained in the CSV;
the expected 1/4 is stated so that the negative learned result is not inflated
by an unlucky control draw.

## Held-out rows

| G2 target | Truth, audit-only | Learned selection | Fixed | Frozen random | Learned exact |
|---|---|---|---|---|---:|
| TE5 | thresh | mixr | thresh | run | 0.0 |
| ME5 | mixr | ratio | thresh | ratio | 0.0 |
| RE5 | ratio | run | thresh | thresh | 0.0 |
| RN5 | run | mixr | thresh | mixr | 0.0 |

The target names and truth column above are report/audit material only; they
are not selector features. The raw CSV contains every train, validation, and
held-out row, including each chosen prior, score, matched budget, and routing
cost.

## Interpretation and next valid lever

G2 repaired F1's invalid substrate and leakage defects, so this is not an
inconclusive instrument failure. It is a clear performance failure on the
valid corpus. The next selector experiment needs new behavioural observations
with discriminative evidence, or a grammar-based proposer such as G4—not target
names or a hand-provided family label. Any future model must retain G2's split,
distance guard, and pre-test model freeze.

## Reproduce

```sh
cd sparse_poly_discovery
zig build-exe prior_selector_round_g.zig -O ReleaseFast -femit-bin=prior_selector_round_g
./prior_selector_round_g ../results/prior_selector_round_g.csv
./prior_selector_round_g selftest
```
