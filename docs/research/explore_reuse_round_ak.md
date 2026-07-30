# Round AK / AK3 — Provenance-bound explore–reuse arbitration

**Verdict: FOUNDATION POSITIVE (bounded frozen-substrate tier).** An organism
uses its own earned causal record to decide whether to reuse a prior raw
intervention or spend the same generic raw variation cost rediscovering one.
It wins pre-registered anonymous changing regimes against fixed alternation,
always replay, random allocation, shuffled provenance, answer-memory, fresh,
and literal-record-ablation controls.

## Question and pre-registration

Before execution, 64 hidden cohorts and eight epochs per cohort are fixed.
Private physical regimes change after epochs 1, 3, 5, and 6. The policy never
receives regime IDs, a change flag, a task label, a target, a reward,
uncertainty/novelty scalar, an experiment menu, or evaluator feedback. It sees
only signed consequences of unlabelled raw displacements. Evaluation happens
after the run on disjoint contacts.

The record contains a compressed raw-effect signature, a discovered direction
and phase, aggregate evidence, and an append-only provenance hash. It contains
no world identifier, answer trace, score, regime schedule, or action table.

## Mechanism

At each epoch the organism earns a fresh four-contact effect signature. It
reuses the preceding record only if that new raw signature agrees with the
record’s signature. A disagreement causes generic raw variation to rebuild the
record. Thus the decision is a comparison between two causal artifacts—not a
host-supplied router, regime key, or scalar uncertainty score.

The evaluator’s hidden material is never observed by the policy. All policies
receive the same evaluation contacts. Charged raw interactions include every
signature contact and every exploration contact.

## Controls and acceptance

The CSV reports equal-cost fixed alternation, always replay, deterministic
random explore/reuse, shuffled provenance, raw answer-memory, fresh start, and
literal record ablation. The candidate can count only if it beats each on both
hidden aggregate material and the subset after private changes; the causal
record must also be necessary and answer-scrubbed. The deterministic selftest
enforces those inequalities and exact CSV replay.

## Result and limit

This is the first bounded **experiment-allocation** positive: current earned
provenance binds to current raw consequences well enough to decide when replay
is useful and when exploration is needed in hidden changing worlds. It is
strictly a foundation result inside the Round AJ frozen substrate. The finite
raw displacement range, trace compression operation, resource accounting, and
sealed synthetic world generator remain trusted substrate. It does not show
open-ended invention, general scientific method, full autonomy, organism-owned
physics, or hostile process containment.

| Policy | Charged interactions | Hidden material | Post-change material |
|---|---:|---:|---:|
| Earned arbitration | 5,928 | 15,360 | 5,610 |
| Fixed explore/reuse alternation | 6,144 | 14,355 | 4,605 |
| Always replay | 4,608 | 8,625 | 1,980 |
| Random allocation | 6,456 | 13,575 | 4,185 |
| Shuffled provenance | 12,288 | 4,290 | 1,590 |
| Answer memory / fresh / ablated record | 8,192 | 4,095 | 1,485 |

The earned policy has the highest total material **and** the highest material
per charged interaction. It makes all 512 appropriate explore/reuse decisions
and commits 229 causal record rebuilds; its performance advantage is strongest
after the hidden shifts.

## Reproduce

```bash
mkdir -p /tmp/zig-ak3-cache /tmp/zig-ak3-global
zig build-exe sparse_poly_discovery/explore_reuse_round_ak.zig \
  -femit-bin=/tmp/explore-reuse-ak3 \
  --cache-dir /tmp/zig-ak3-cache --global-cache-dir /tmp/zig-ak3-global
/tmp/explore-reuse-ak3 selftest
/tmp/explore-reuse-ak3 run results/explore_reuse_round_ak.csv
```

Expected:

```text
round_ak_ak3 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true provenance_bound=true answer_scrubbed=true
```

## Artifacts

- `sparse_poly_discovery/explore_reuse_round_ak.zig`
- `results/explore_reuse_round_ak.csv`
- `docs/research/explore_reuse_round_ak.md`
