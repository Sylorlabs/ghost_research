# Round AM / AM1 — delayed temporal-motif relevance

**Verdict: VALID NEGATIVE.** The learned mechanism derives a delayed three-step response motif from generic intervention-to-transition traces and beats static effect-vector, last-outcome, random, replay, shuffled-history, answer-memory, and motif-ablation controls on privately recoded sealed worlds. It ties the pre-registered equal-budget fixed temporal motif/schedule exactly (8,448 each), and its frozen record collapses under causal-law shift (924). It therefore does not establish that an organism constructs relevance beyond an installed temporal matcher.

## Question and pre-registration

Can a non-LLM organism construct relevance from delayed multi-step response trajectories to generic interventions, beyond static effect vectors or a last outcome?

Before comparison, the deterministic evaluator generates 64 sealed cohorts. Each has two anonymous regimes. A generic three-contact intervention trace produces raw transitions. The raw values are hidden behind an evaluator-private bijection and nonce; literal values from the earned trace never occur in the comparison trace. Regime zero has an equal-first/last delayed response and regime one has three changes. Each regime also has an independently sampled three-bit causal action law. Evaluation only begins after every policy spends the same nine contacts per cohort: six to earn the two traces and three for the private query. No execution path receives an intermediate score or evaluator feedback.

The pre-registered test worlds are a normal private-recoding world (query encoding 211 and nonce 73 versus earned encoding 3 and nonce 9); a causal-law-shift world (both regime identity and causal law change after frozen learning, with no shift-training contact); and an overlap audit (query contacts, nonce, and encoding are disjoint from earned contacts).

## Candidate and prohibited channels

The candidate retains only `{first_eq_last, middle_changes, schedule, provenance_hash}` produced from its own three delayed raw responses. It selects the record whose two temporal relations match the private query, then applies the earned schedule. This is not supplied a task target, answer trace, labels, semantic decoder, task menu, matcher/router, intermediate score, or evaluator feedback. The answer-memory arm has its causal motif and schedule removed; the source-level answer scrub additionally verifies no target or answer-trace field exists in the record.

That narrow claim needs an important qualification: although the organism derives the motif values, the substrate supplies a three-step window, equality and change comparisons, a record schedule field, and the selector. The fixed temporal control makes that installed structure explicit.

## Equal-budget results

| Policy | Charged contacts | Private recoded material | Perfect cohorts |
|---|---:|---:|---:|
| learned motif | 576 | **8,448** | **64/64** |
| fixed effect-vector | 576 | 2,409 | 14/64 |
| last-outcome matcher | 576 | 2,409 | 14/64 |
| fixed temporal motif/schedule | 576 | **8,448** | **64/64** |
| random | 576 | 1,089 | 0/64 |
| replay | 576 | 660 | 5/64 |
| shuffled history | 576 | 1,188 | 9/64 |
| answer-memory | 576 | 1,089 | 0/64 |
| motif ablation | 576 | 1,089 | 0/64 |

The candidate makes 64 provenance commits. Private value recoding retains 8,448/64. The causal-law-shift attack scores 924/7: it is deliberately a frozen-transfer failure, because no new causal contacts are provided after the law change. It cannot meet the stricter positive criterion across both recoding and shifts.

## Why this is a negative

A foundation positive required strict wins over every relevant pre-registered fixed/baseline control after recoding and causal shifts. The learned arm fails twice: the fixed temporal motif/schedule ties exactly in the primary private recoding comparison, and frozen temporal evidence does not transfer through the changed causal law. The gains over static and last-outcome controls show only that delayed information matters in this synthetic fixture, not that the organism created the temporal relevance machinery.

This is a bounded local Zig simulation with finite regimes, a host-defined three-step representation, equality relation, and reward conversion. It says nothing about open-ended organism learning, semantic relevance, autonomous experiment design, or hostile containment.

## Reproduce

```bash
mkdir -p /tmp/zig-am1-cache /tmp/zig-am1-global
zig build-exe sparse_poly_discovery/temporal_motif_round_am.zig \
  -femit-bin=/tmp/temporal-motif-am1 \
  --cache-dir /tmp/zig-am1-cache --global-cache-dir /tmp/zig-am1-global
/tmp/temporal-motif-am1 selftest
/tmp/temporal-motif-am1 run results/temporal_motif_round_am.csv
```

Expected selftest output:

```text
round_am_am1 selftest PASS verdict=VALID-NEGATIVE deterministic=true fixed_temporal_tie=true recode_and_shift=true
```

## Artifacts

- `sparse_poly_discovery/temporal_motif_round_am.zig`
- `results/temporal_motif_round_am.csv`
