# Round AL / AL2 — endogenous context segmentation

**Verdict: VALID NEGATIVE.** A mutable consequence-earned context record does
better than a global context, random variation, replay, shuffled history,
answer-memory, and literal record ablation in evaluator-private regime-shift
worlds. It is not a foundation positive: both a fixed periodic router and a
generic last-consequence matcher score higher. The observed benefit is therefore
not evidence that the organism has constructed a relevance segmentation beyond
the supplied binary consequence fixture.

## Question and pre-registration

Can an organism detect a change in how its own intervention behaves and split
or merge its retained experience accordingly, without a regime label, router,
change-point value, similarity function, target, decoder, answer cache,
experiment menu, reward feedback, or evaluator feedback?

There are 48 pre-registered anonymous cohorts of 36 finite interactions. Each
cohort has three evaluator-private causal epochs. Raw surface values are
independently sampled, privately recoded, and deliberately unrelated to the
causal law. The policy receives no regime indicator; its only potentially
relevant observation is whether its last intervention produced a consequence.
Evaluation is accumulated by the frozen substrate after each interaction and is
not an input to the policy.

## Candidate

The candidate has two initially empty mutable records. When its previous action
fails, it infers the alternate binary causal response, revises the active
record, and records a witness count plus an append-only provenance lineage.
It selects its next action from the active record. This produces 166 recorded
revisions (83 first splits and 83 later merges/revisions) across cohorts.

That mechanism is intentionally limited. The test fixture supplies binary
alternate-law inference and a two-record container. Neither is presented as
organism-owned ontology.

## Equal-cost controls and attacks

- a single fixed global context;
- a fixed, same-capacity periodic router that knows the epoch schedule;
- a generic last-action/consequence matcher with no context provenance;
- random variation, previous-cohort replay, and shuffled provenance;
- empty answer-memory and literal context-record ablation;
- value recoding, non-overlapping raw-world, and causal-shift attacks.

All policies consume exactly 1,728 interactions. No policy reads the raw
surface channel to choose; doing so would make value recoding a hidden matcher.

## Results

| Policy | Interactions | Hidden material | Correct actions |
|---|---:|---:|---:|
| learned context segments | 1,728 | 17,348 | 1,562 |
| fixed global context | 1,728 | 13,128 | 1,140 |
| fixed periodic router | 1,728 | **19,008** | **1,728** |
| generic last-consequence matcher | 1,728 | **17,578** | **1,585** |
| random / answer-memory / ablated | 1,728 | 10,038 | 831 |
| replay | 1,728 | 11,928 | 1,020 |
| shuffled history | 1,728 | 10,728 | 900 |

The candidate passes the private raw-value recoding and non-overlap attacks
unchanged because it does not use surface content. It also revises under the
three hidden causal shifts. Its records are necessary against ablation, but the
generic matcher achieves a higher score without those records, while the fixed
router gives the fixture optimum. The acceptance standard requires a learned
segmentation to beat both; it fails.

## Interpretation

This rules out a narrow mistaken conclusion: “reacting to a failed action” is
not enough to establish endogenous context discovery. In this binary world it
is cheaper to retain the last observed response, and a supplied phase router
solves the schedule. A future positive needs a learned contextual causal
structure that contributes beyond generic consequence following, under a world
where the context structure itself is not reducible to the provided record
capacity or binary alternation.

This is a bounded frozen-substrate result only. It does not establish full
autonomy, open-ended invention, organism ownership of computation, or hostile
containment.

## Reproduce

```bash
mkdir -p /tmp/zig-al2-cache /tmp/zig-al2-global
zig build-exe sparse_poly_discovery/context_segmentation_round_al.zig \
  -femit-bin=/tmp/context-segmentation-al2 \
  --cache-dir /tmp/zig-al2-cache --global-cache-dir /tmp/zig-al2-global
/tmp/context-segmentation-al2 selftest
/tmp/context-segmentation-al2 run results/context_segmentation_round_al.csv
```

Expected:

```text
round_al_al2 selftest PASS verdict=VALID_NEGATIVE deterministic=true generic_match_stronger=true routed_stronger=true
```

## Artifacts

- `sparse_poly_discovery/context_segmentation_round_al.zig`
- `results/context_segmentation_round_al.csv`
