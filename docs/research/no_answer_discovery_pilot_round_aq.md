# Round AQ / AQ4 — no-answer-key discovery pilot

**Verdict: FOUNDATION POSITIVE, narrowly bounded.** A deterministic candidate originated an opaque, precommitted causal process record from raw observations, chose a discriminating ordered-pair intervention after a failed self-distinction, predicted its raw contrast before executing it, and passed both held-out recoding and changed-condition replications. This is not evidence of real-world novelty, open-ended invention, or general intelligence.

## Question

Can a candidate make and test a discovery-like claim without comparing against a hidden answer, a human-preferred invention, a semantic label, a reward/progress score, or a memorized trace?

## Protocol

The evaluator owns an anonymous four-action synthetic raw world. The candidate gets raw observations only. It first performs an uninformative self-comparison, then records the first raw pair with a difference, freezes an opaque provenance ID plus a predicted signed raw delta, and only then executes the selected pair. The evaluator later checks the realized result and two independent re-derived replications: a held-out recoding and a changed presentation/scale condition.

Admission also requires tests of both an attacker alternative (static/correlation story) and a simpler same-value alternative. The evaluator does not ask whether the record is a target answer or a useful human invention.

## Result

| Record / control | Result |
|---|---:|
| Candidate-originated precommitted raw causal record | **ADMIT 1/1** |
| Post-hoc claim rewrite | reject |
| Correlation-only story | reject |
| Failed held-out replication | reject |
| Answer-key or memorized-trace channel | reject |
| Missing attacker alternative | reject |
| Missing simplicity alternative | reject |
| Deterministic CSV replays | **2/2 byte-identical** |

The candidate uses 4 raw contacts in each of primary, recoded, and changed conditions: **12 contacts total**. No outcome/score is exposed until after each frozen prediction.

## Reproduction

```bash
mkdir -p /tmp/zig-aq4-cache /tmp/zig-aq4-global
zig build-exe sparse_poly_discovery/no_answer_discovery_pilot_round_aq.zig \
  -femit-bin=/tmp/no-answer-discovery-aq4 \
  --cache-dir /tmp/zig-aq4-cache --global-cache-dir /tmp/zig-aq4-global
/tmp/no-answer-discovery-aq4 selftest
/tmp/no-answer-discovery-aq4 run results/no_answer_discovery_pilot_round_aq.csv
```

Expected self-test receipt:

```text
round_aq_aq4 selftest PASS deterministic=true admits=1 controls_rejected=6 contacts=12 verdict=FOUNDATION_POSITIVE bounded_no_answer_key_process_record
```

## Limits

- The record is **not** a real novel discovery: the raw world, action alphabet, and causal contrast are synthetic and human-implemented.
- It is not an answer-matching benchmark, but it is still evaluator-checked for a precommitted raw prediction; that is how it distinguishes a causal claim from a story written afterward.
- This pilot keeps evaluator and candidate routines in one source/executable for determinism. It is not a process-isolation proof and must later use the AP clean-room boundary.
- The opaque claim ID is provenance only, not a semantic answer or a human invention label.

## Artifacts

- `sparse_poly_discovery/no_answer_discovery_pilot_round_aq.zig`
- `results/no_answer_discovery_pilot_round_aq.csv`
- `docs/research/no_answer_discovery_pilot_round_aq.md`
