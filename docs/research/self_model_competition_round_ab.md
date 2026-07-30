# AB2 — Competing executable self-models

## Verdict

**VALID NEGATIVE.** The organism-side mechanism did construct twelve opaque
executable byte-tape models, choose charged self-interventions from their
output disagreement, freeze the choice before each fresh context, and eliminate
models using ordinary resource consequences. That machinery is real and fully
replayable. It does **not** establish self-created causal explanation or useful
autonomous experiment direction.

The decisive claim defect is architectural: the harness still defines a model
as one 16-byte tape, supplies the bytecode decoder, and interprets one signed
integer as a predicted resource consequence. Comparing those signed outputs is
also supplied. Those choices install the form of an explanation and its
disagreement axis. This is another human-built room, even though the tape bytes
and selected interventions are organism-owned.

## Experiment

Twelve model tapes are deterministically grown from raw history digests. Each
tape executes against the same anonymous history and each of eight anonymous
self-interventions. The organism selects the intervention with the widest model
output disagreement. Work is charged as `1 + intervention`, and the selected
experiment is fixed before the evaluator generates the ordinary resource
consequence in each of 48 fresh contexts.

Models receive no answer, correctness distance, uncertainty scalar, named
component, task label, or evaluator map. A model is removed only when its frozen
output disagrees strongly with the observed ordinary consequence. The oracle is
evaluator-private and appears only as a ceiling row.

## Results

Lower resource regret is better.

| Policy | Charged cost | Resource regret | Models eliminated |
|---|---:|---:|---:|
| disagreement | 160 | 612 | 12 |
| random | 206 | 677 | 12 |
| fixed | 192 | 595 | 12 |
| replay | 216 | 576 | 12 |
| cheapest | 48 | 586 | 12 |
| frequency | 48 | 586 | 12 |
| single model | 186 | 627 | 12 |
| equal-size | 160 | 612 | 12 |
| shuffled disagreement | 200 | 806 | 12 |
| false models | 272 | 681 | 12 |
| model/experiment ablation | 206 | 677 | 0 |
| recoded | 202 | 656 | 12 |
| relocated | 160 | 612 | 12 |
| resegmented | 136 | 690 | 12 |
| evaluator-private oracle | 180 | 0 | 12 |

Disagreement beats random by 65 regret and single-model selection by 15, while
shuffling disagreement, falsifying models, or ablating model direction removes
that advantage. This shows the model population affected experiment direction.
It is not a capability win: disagreement loses fixed, replay, cheapest, and
frequency controls and exactly ties the equal-size control.

Relocation is harmless because it only reorders whole supplied tapes.
Resegmentation and raw recoding damage the result (690 and 656 regret), showing
that the apparent self-models bind the supplied decoder/segment geometry rather
than preserve function under a changed raw representation.

All twelve models are eventually eliminated in ordinary runs. That is evidence
that the model grammar did not provide a sufficient causal account; elimination
alone is not model learning.

## Hostile controls

The harness fail-closes fixed model grammar/decoder, human component geometry,
evaluator read or rewrite, answer transcripts, duplicate evidence, favorable
context selection, uncharged bloat, post-test selection, freeze edits,
nondeterminism, and LLM/text/embedding dependence. Two independent selftest
runs are byte-identical.

## What this teaches Round AB

Executable disagreement is a useful source of experimental direction only
after the organism has invented what constitutes an executable account and how
accounts expose incompatible consequences. Mutating bytes inside a supplied
predictor VM merely moves the human room boundary from "component" to
"decoder." AB2 therefore does not release AB4.

The next honest test needs a uniform medium where alternative causal dynamics
compete through their direct downstream behavior, without a privileged
fixed-length model container or signed prediction output. Any comparison
interface must itself be organism-built, replaceable, and tested through fresh
resource consequences.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/self_model_competition_round_ab.zig \
  -femit-bin=/tmp/self_model_competition_round_ab \
  --cache-dir /tmp/zig-cache-ab2 --global-cache-dir /tmp/zig-global-ab2
/tmp/self_model_competition_round_ab selftest
/tmp/self_model_competition_round_ab run results/self_model_competition_round_ab.csv
```

Canonical artifacts:

- `sparse_poly_discovery/self_model_competition_round_ab.zig`
- `results/self_model_competition_round_ab.csv`
- `docs/research/self_model_competition_round_ab.md`
