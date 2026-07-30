# I2 — symmetric multi-cell partition-response admission (Round I)

**Verdict: constrained positive for admission coverage; negative for a new
efficiency/autonomy claim.** A predeclared, symmetric response over the full
supplied directed-partition grammar admits one-cell, two-cell, and held-out
three-cell directed targets, while rejecting a threshold target and random
labels. It removes H4's *singleton-only* admission defect. It does **not**
discover a grammar, does not make the finite grammar cheap to search, and does
not yet establish a general search-response representation.

## Question

H4 found that a two-cell directed target was exactly representable but rejected
by H3's singleton-orientation admission test. I2 asks whether the admission
test can be made symmetric over partitions, with no access to a target name,
formula, family, anchor, mask, or residue and no preference for singleton
masks.

## Frozen protocol and pre-run gates

The harness uses eight iid cells in `0..5`, 2,000 examples per condition, and
fixed train/validation/test slices of 1,000/500/500. Generator specs label the
data but are never passed into `partitionResponse`, `selectOnValidation`, or
the candidate scorer; those APIs receive only grids and binary labels.

The supplied candidate language is exactly the H3/H4 directed count grammar:
all 254 nonempty proper masks, each crossed with mod-2 residues and mod-3
residues (1,270 candidates). Every mask, including every singleton, two-cell,
and larger mask, gets the same five candidate forms. There is no
cardinality-dependent threshold, no singleton probe, and no family field.

The admission statistic is the **maximum train accuracy** over that frozen,
symmetric candidate bank. The admission threshold was frozen at 0.90 before
execution. Candidate selection happens independently on validation data; test
data are untouched until the final score.

Pre-run acceptance gates:

- every label base rate must be in `(0.10, 0.90)`;
- all directed controls must admit, while threshold and random controls must
  reject;
- an admitted condition must select a `>=0.99` held-out exact member and beat
  the fixed threshold menu;
- all directed, fixed-menu, and blind/random arms receive 1,270 candidate
  evaluations per trial;
- raw ledgers must include every directed candidate score and 128 equal-budget
  blind trials for each condition.

The fixed arm is the predeclared 25-member global threshold menu repeated to
the 1,270-call budget. Blind draws uniformly with replacement from the same
1,270 directed candidates for 128 trials. It is an equal-evaluation control,
not an assertion that random samples a different grammar.

## Results

| condition | partition response | fixed validation | admitted? | chosen test | blind exact hit rate (128×1,270) | result |
|---|---:|---:|---|---:|---:|---|
| singleton `{3}`, mod 3 / residue 1 | 1.000 | 0.626 | yes | 1.000 | 0.6328 | pass |
| two-cell `{1,5}`, mod 2 / residue 0 | 1.000 | 0.536 | yes | 1.000 | 0.7188 | pass |
| held-out three-cell `{0,3,6}`, mod 3 / residue 2 | 1.000 | 0.598 | yes | 1.000 | 0.6953 | pass |
| threshold negative | 0.596 | 1.000 | no | — | 0.0000 | pass |
| random-label negative | 0.548 | 0.546 | no | — | 0.0000 | pass |

All five pre-run gates pass. The two- and three-cell results directly falsify
the claim that the old admission rule must remain singleton-shaped: they are
admitted with the same rule and threshold as the singleton control. The
held-out three-cell condition is a structural holdout, not merely a new seed.

## Raw ledger and reproducibility

The CSV contains 1,270 train/validation candidate rows per condition, 128
equal-budget blind-trial rows per condition, and one summary row per condition.

```bash
cd /home/micah/Desktop/Sylorlabs/ghost_research/sparse_poly_discovery
zig build-exe multicell_admission_round_i.zig -O ReleaseFast -femit-bin=multicell_admission_round_i
./multicell_admission_round_i
awk -F, '$2=="summary" {print}' ../results/multicell_admission_round_i.csv
```

## Ablations and falsification pressure

1. **No singleton privilege:** I2 removes H4's `singleton_probe >= 0.75` rule
   entirely. Larger masks receive the identical candidate forms and admission
   rule. Two independent multi-cell targets are admitted and exact on test.
2. **Unrelated controls remain closed:** threshold labels score 1.000 in the
   fixed menu yet only 0.596 in the partition response; random labels score
   0.548. Both remain below the frozen 0.90 threshold.
3. **Equal-budget blind is competitive:** blind equal-budget sampling reaches
   an exact validation member in 63–72% of trials on directed targets. The
   symmetric response gives reliable deterministic coverage only because it
   exhausts the human-supplied 1,270-candidate grammar. It does not demonstrate
   a large search-efficiency advantage.
4. **The response itself is near-solving inside this grammar:** its maximum
   statistic can be an exact grammar member. Thus calling it a lightweight
   high-level “admission feature” would be misleading. It is a grammar scan
   split across train (admit) and validation (select), not a learned general
   router.

## Certification proxy and live-v6 direction

For an admitted member the proxy requires independent `>=0.99` test accuracy;
the two negative controls are not emitted for promotion. This is compatible
with H5's gate-v6 direction: an exact candidate becomes a **candidate for**
candidate-family-excluded multi-feature COVER reconstruction, not an automatic
promotion. I2 does not invoke live v6 or claim a production promotion; H5's
four-candidate live-loop battery is the existing evidence for that decision
layer.

## Exact conclusion

I2 repairs the specific H4 boundary: the directed grammar can now be admitted
for singleton and multi-cell partitions by one symmetric rule without using
semantic target metadata. The remaining limitation is substantial: the
partition/modulo grammar and exhaustive response bank are still human-supplied,
and blind equal-budget search is often successful. This result supports using
the symmetric rule as an I3/I6 input only under an explicit “finite grammar
scan” label, not as proof that the human structural-language limitation is
removed.

Artifacts:

- `sparse_poly_discovery/multicell_admission_round_i.zig`
- `results/multicell_admission_round_i.csv`
- this report
