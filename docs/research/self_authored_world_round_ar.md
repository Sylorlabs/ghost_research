# Round AR / AR2 — bounded self-authored synthetic worlds

**Verdict: FOUNDATION POSITIVE, narrowly bounded.** In this deterministic synthetic fixture, a candidate converted raw distinctions from anonymous source worlds into a precommitted compositional world specification. When the evaluator instantiated that specification under a fresh seed and recoding, its resulting world produced **216/384** held-out order-sensitive causal distinctions. This strictly exceeded equal-cost fixed worlds (108), random proposals (98), replay (105), shuffled provenance (109), and answer-scrubbed proposals (81).

This is not a real invention, a real-world world generator, open-ended autonomy, or evidence of scientific novelty. The proposal grammar is supplied and small.

## Question

Can a candidate author a bounded synthetic world specification from raw source distinctions *before* the new world exists, and does the independently instantiated proposal yield a new held-out causal distinction more often than strong non-authored controls?

## Protocol

Each of 384 evaluator-owned source worlds has five anonymously recoded raw observations. The candidate sees those raw values and commits a compact specification:

```text
operator ∈ {cascade, exchange, feedback}
ordered pair of two raw atoms
bounded depth ∈ {1, 2, 3}
opaque provenance digest
```

This grammar is **human supplied**. It is not a source-world serializer: there is no field for a source ID, a hidden template ID, a target, reward, score, answer trace, semantic label, or full observation transcript. The candidate uses observed extrema plus a raw aggregate to select an operator, ordered pair, and depth. The evaluator freezes that record, creates a fresh private seed and recoding, and then checks whether the proposed world has an order-sensitive transition under the committed composition.

Every arm pays 14 contacts per cohort: 8 proposal contacts and 6 independent evaluation contacts. The candidate has no access to fresh world seed, recoding, result, or score while choosing its proposal.

## Validity gates

The evaluator rejects:

- missing provenance or a degenerate no-dynamics spec;
- same-atom pairs and zero depth;
- source-copy fingerprint fixtures;
- direct answer/template/score fields (the fixed grammar cannot encode them);
- proposal changes after fresh-world instantiation.

The source copy check is bounded by the small grammar: it proves this record cannot carry a complete five-observation source trace, not that arbitrary future grammars cannot carry covert information. A larger grammar would need a stronger information-flow audit.

## Results

| Policy | Valid proposals | Held-out causal distinctions | Contacts |
|---|---:|---:|---:|
| Authored compositional spec | **384/384** | **216** | 5,376 |
| Fixed generic world | 384/384 | 108 | 5,376 |
| Random proposal | 317/384 | 98 | 5,376 |
| Replay prior source | 384/384 | 105 | 5,376 |
| Shuffled provenance | 384/384 | 109 | 5,376 |
| Answer-scrubbed proposal | 317/384 | 81 | 5,376 |
| No-dynamics/missing-provenance fixture | 0/384 | 0 | 5,376 |

The result meets the narrow acceptance rule: the authored policy strictly beats every listed equal-cost control, all authored proposals pass the declared structural checks, and independent fresh instantiation is performed after commitment.

## Reproduction

```bash
mkdir -p /tmp/zig-ar2-cache /tmp/zig-ar2-global
zig build-exe sparse_poly_discovery/self_authored_world_round_ar.zig \
  -femit-bin=/tmp/self-authored-ar2 \
  --cache-dir /tmp/zig-ar2-cache --global-cache-dir /tmp/zig-ar2-global
/tmp/self-authored-ar2 selftest
/tmp/self-authored-ar2 run results/self_authored_world_round_ar.csv
```

The self-test writes two independent CSV ledgers and requires byte identity.

Expected receipt:

```text
round_ar_ar2 selftest PASS deterministic=true cohorts=384 authored=216 fixed=108 random=98 replay=105 shuffled=109 contacts_per_arm=14 verdict=FOUNDATION_POSITIVE bounded_self_authored_synthetic_world
```

## Limits

- This is a synthetic fixture, not a “fully open free world.” The source worlds, raw atom alphabet, proposal grammar, transition functions, and evaluation criterion are human implemented.
- The candidate does not invent a new operator family or expand the grammar. It selects within three supplied generic composition operators.
- “New” here means a fresh evaluator instantiation has a held-out causal distinction. It does **not** mean novel to science, to the user, or absent from training data.
- The fixture is deterministic and single-process; it is not an AP-style clean-room process-isolation replay.
- Fast virtual computation is deliberately not treated as intelligence or lived experience. The recorded measure is distinct precommitted causal behavior at equal cost.

## Artifacts

- `sparse_poly_discovery/self_authored_world_round_ar.zig`
- `results/self_authored_world_round_ar.csv`
- `docs/research/self_authored_world_round_ar.md`
