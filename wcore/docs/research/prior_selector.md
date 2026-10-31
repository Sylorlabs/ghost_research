# F1 — learned structural-prior selector

**Date:** 2026-07-11  
**Status:** completed as an **instrument failure / no result**  
**Artifact:** `wcore/src/prior_selector.zig`  
**Raw output:** `results/prior_selector_2026_07_11.csv`

## Question

Can a machine infer which generation prior a target needs from a cheap failure
descriptor, rather than having a human choose the prior? This is the E2 router
idea moved one level up, from selecting an aim lens to selecting a
representability-expanding generator.

The resumed implementation tests that question on a fresh, self-contained mini
VM with four hand-defined prior shapes (`rmw`, `cmp`, `mod`, and `run`), five
constructed targets per family, a 12/4/4 target-level train/validation/test
split, and a standardized k-NN selector. It is **not** a run on the production
E1/E3 substrates: those implementations do not expose the machinery needed for
a direct import. Consequently, even a valid positive here would have been a
small-substrate result, not proof that the production generator can infer its
own priors.

## Prespecified validity gates

Before interpreting selector accuracy, the substrate must satisfy all of the
following:

1. Every target is non-degenerate and obeys the claimed binary-output contract.
2. Every target is reachable under its own designated prior.
3. The four prior pools provide meaningful, distinguishable labels; the label
   cannot be assigned by an arbitrary precedence rule when many pools certify
   the same target.
4. Held-out descriptors are not duplicates of training descriptors.
5. The learned selector must beat fixed-best and random controls on held-out
   targets.

## Measured results

Build and both executable paths completed successfully, but the validity gates
did not.

| Check | Measured result | Verdict |
|---|---:|---|
| own-family predicate fires | 20/20 | pass |
| own-family COVER recall | **14/20** | **fail** |
| no-prior COVER recall | 12/20 | control nearly matches own-prior pools |
| own-prior misses | RMW_C, RMW_D, RMW_E, RUN_A, RUN_B, RUN_C | **fail** |
| targets certified by no prior | 6/20 | **fail** |
| exact/complement collision warnings | RMW_A/RMW_B; RMW_C/RMW_E | **fail** |
| minimum standardized train-test distance | **0.0000** (warning threshold 0.05) | **leakage guard fail** |
| held-out solves | router 3/4; fixed-best 3/4; random 3/4 | no learned advantage |
| held-out evaluation count | router 5,549,124; fixed 5,549,124; random 5,343,576 | router is not cheaper |

The binary-output premise is also false for the current targets. The self-test
reports mean “one rates” above one for RUN_A through RUN_E (1.275 to 30.085),
because those reference programs emit counters rather than bits. RMW_C/D/E and
CMP_C are nearly constant on the self-test stream. These are not cosmetic
warnings: the canonical-hash and agreement discussion in the implementation
explicitly relies on binary, non-degenerate outputs.

The empirical-label stage is not usable as ground truth. Several constructed
families certify broadly under other priors (for example CMP_A/B/C certify
under all four pools), while six targets certify under none. The code then
assigns the first certifying family by fixed precedence and substitutes `rmw`
when no family certifies. The resulting k-NN labels therefore conflate target
family, accidental cross-pool reachability, and a fallback value.

For completeness, the invalid pipeline selected k=5 at 0.875 leave-one-out
accuracy and emitted router/fixed/random = 3/4 on the four held-out targets.
Those numbers are recorded as diagnostics only. They are **not an F1 positive**:
the leakage guard fired, all three arms tied, and the router selected `rmw` for
all four test targets.

## Verdict

**F1 is inconclusive, not positive and not a clean negative on learned priors.**
The current experiment cannot answer whether structural priors can be inferred,
because the target/pool construction fails before the learner is evaluated.
The only supported conclusion is that this particular mini-substrate and label
instrument are invalid for the question.

The F6 estimate of roughly 85–90% machine-supplied insight for a successful F1
remains a **projection only**. This run supplies no measurement that upgrades
it.

## What a valid rerun requires

Rebuild the battery so outputs are genuinely binary and non-degenerate; require
20/20 own-prior reachability before fitting; define labels from exclusive or
quantitatively strongest prior benefit rather than first-hit precedence; make
the no-prior arm materially weaker; and freeze a target-level split whose
descriptor distance passes the leakage guard. Only then compare selector,
fixed-best, and random on untouched targets. A production-strength answer
should ultimately run against E1/E3 machinery rather than this proxy VM.

## Reproduction

```sh
cd wcore
mkdir -p bin
zig build-exe -O ReleaseFast src/prior_selector.zig \
  -femit-bin=bin/prior_selector
./bin/prior_selector selftest
rm -f ../results/prior_selector_2026_07_11.csv
./bin/prior_selector run ../results/prior_selector_2026_07_11.csv
```

Both commands exited 0 in the measured run. The self-test currently prints
failures as diagnostics rather than returning nonzero, so exit status alone is
not a validity signal.
