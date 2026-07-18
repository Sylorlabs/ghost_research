# Round AJ / AJ4 — self-chosen experiment program

**Verdict: VALID NEGATIVE.** The organism converted an earned causal record
into a non-fixed raw perturbation program and improved over blank,
answer-memory, retained-answer, and literal-ablation policies. It did **not**
beat random, replayed, or shuffled-history experiment programs on
pre-registered evaluator-private worlds. It therefore does not establish that
the organism can choose a useful new causal experiment without a human-selected
bottleneck.

## Pre-registered question

AJ2 supplied an answer-scrubbed signed causal relation and AJ3 supplied the
principle that causal experience can lower a distinct discovery cost. AJ4 asks
whether a current cohort can use such earned information to create an
experiment structure—its perturbation direction, stride, and offset—rather
than select a host-provided experiment from a menu. During a run there is no
world-family label, target, task label, answer trace, score, candidate/tool
library, evaluator feedback, or selected bottleneck. The evaluator observes
only untouched held-out material after the program exits.

The frozen Round AJ substrate remains explicit: finite raw trace transport,
generic reversible perturbation, bounded accounting, append-only provenance,
sealed world generation, and post-run measurement. This is not a claim of
substrate ownership or hostile containment.

## Result

| Policy | Raw interactions | Hidden unseen material | Commits | Non-fixed programs |
|---|---:|---:|---:|---:|
| earned generated program | 960 | 412 | 3 | 45 |
| fixed experiment | 576 | 273 | 1 | 0 |
| random experiment | 576 | **526** | 4 | 45 |
| replayed preceding-cohort program | 960 | **632** | 9 | 45 |
| shuffled causal history | 960 | **604** | 8 | 45 |
| fresh start | 960 | 0 | 0 | 0 |
| answer-memory trace | 960 | 0 | 0 | 0 |
| retained answer table | 960 | 0 | 0 | 0 |
| first-mechanism ablated | 960 | 0 | 0 | 0 |

The generated policy is not a null implementation: it produces non-fixed
programs in 45/48 cohorts and gains 412 material over answer-shaped and
ablated controls. But the strong controls are decisive. Randomized probe
structure earns 526, replay earns 632, and shuffled history earns 604.
Consequently, causal provenance was not used well enough to choose the
experiment geometry; a positive would require the earned program to beat every
equal-cost control and remain necessary under ablation.

## Required attacks and accounting

- **Fixed/random/replay:** recorded directly; all execution and probe contacts
  are charged in the CSV.
- **Fresh, answer-memory, retained-answer, and ablation:** all are zero,
  showing that physical address-shaped memory alone does not provide a result.
- **Shuffled history:** 604 exposes that the implemented causal program is not
  selecting the cohort-specific relation reliably.
- **World overlap and representation:** hidden train/transfer domains are
  disjoint; address/value/period encodings are private per cohort and the
  source selftest records the attack as a required audit row.
- **Causal provenance:** records carry only sign, rhythm, evidence, and a
  provenance hash; no world ID, target, action table, or held-out score enters
  the record.

## Why it is negative

There are two independent reasons not to call this a foundation positive.

1. It loses the decisive equal-cost experiment controls, so it fails the
   self-chosen experiment performance gate.
2. The host still supplies the finite trace window, action arity, and generic
   reversible perturbation primitive. Those are declared trusted substrate,
   but they also mean this cannot prove complete absence of human experimental
   framing.

The useful result is diagnostic: future work needs an organism-owned method
for evaluating *which experiment reduces its own uncertainty*, not merely a
hash-derived way to parameterize a supplied perturbation primitive.

## Reproduce

```bash
mkdir -p /tmp/zig-aj4-cache /tmp/zig-aj4-global
zig build-exe sparse_poly_discovery/self_chosen_experiment_round_aj.zig \
  -femit-bin=/tmp/self-chosen-aj4 \
  --cache-dir /tmp/zig-aj4-cache --global-cache-dir /tmp/zig-aj4-global
/tmp/self-chosen-aj4 selftest
/tmp/self-chosen-aj4 run results/self_chosen_experiment_round_aj.csv
```

Expected:

```text
round_aj_aj4 selftest PASS verdict=VALID_NEGATIVE deterministic=true chosen_program=true controls_beaten=false limitation=host_trace_and_primitive
```
