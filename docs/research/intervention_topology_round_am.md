# Round AM / AM2 — earned intervention topology after causal-law shift

**Verdict: FOUNDATION POSITIVE, bounded.** In this sealed deterministic world,
an organism can earn a reusable topology from generic intervention-to-later-
dependency traces and use it to select relevant retained history after both a
private recoding and a causal-law shift. The topology policy achieves 96/96
perfect hidden cohorts (24,960 material), strictly above every equal-budget
control. This is evidence only for the explicitly implemented synthetic
family—not for open-ended autonomy, semantics, or hostile containment.

## Pre-registered boundary

There are 96 independent sealed cohorts. Each has three anonymous generic
intervention traces. A trace consists of four uniform raw interventions and
their delayed raw dependency consequences. The organism retains only an
earned dependency degree, an opaque continuation, an evidence count, and an
append-only provenance digest. It receives no supplied graph or topology,
world/regime key, label, target, answer, answer trace, task menu, intermediate
score, uncertainty value, or evaluator feedback.

The held-out phase uses a disjoint private literal/world nonce and a changed
causal law: pre-shift effect codes are reversed and recoded. A static old
effect vector therefore stops being a reliable selector. The physical count of
distinct later dependencies remains conserved. The earned policy selects the
old anonymous record whose earned degree equals the current shifted trace's
degree. That selection is the sole candidate-owned operation; evaluation runs
only after all 16 charged raw contacts per cohort are exhausted.

The candidate's topology is therefore not supplied as a fixed graph. It is
derived separately in every cohort from generic intervention→later-dependency
traces. The fixed-graph control supplies the same three degrees in a fixed
order; because hidden cohorts permute their degree ownership, it cannot
recover the relevant record reliably.

## Equal-budget results

Every arm uses 1,536 contacts (96 × 16). `Perfect` means all 20 post-contact
turns selected relevant history; it is evaluator-only material, never exposed
to the policy.

| Policy | Hidden shifted material | Perfect |
|---|---:|---:|
| earned topology | **24,960** | **96/96** |
| fixed graph/topology | 9,100 | 35/96 |
| fixed effect vector | 1,560 | 6/96 |
| last outcome | 8,320 | 32/96 |
| fixed schedule/motif | 9,100 | 35/96 |
| random | 8,060 | 31/96 |
| replay | 8,320 | 32/96 |
| shuffled history | 10,400 | 40/96 |
| answer-memory (scrubbed) | 8,060 | 31/96 |
| topology ablation | 8,060 | 31/96 |

All differences are strict. The answer-memory arm contains no trace and the
topology ablation removes earned degree state, both returning to a deterministic
generic baseline. Replay and shuffled-history controls retain equal amounts of
history but sever the cohort-local learned dependency relation.

## Integrity controls

- **Answer scrub:** replacing candidate state with generic fallback yields
  8,060, not 24,960; the record's opaque continuation is raw material rather
  than an answer trace.
- **Provenance:** earned records commit only deterministic generic-trace
  digests and evidence count. The provenance arm confirms the candidate path
  needs no hidden identifier.
- **World overlap:** experience and shifted query literals/nonces are disjoint;
  the world-overlap arm remains perfect because it uses degree relation, not
  literal identity.
- **No label/feedback channel:** label, regime key, target, task menu,
  intermediate score/uncertainty, and evaluator feedback have no policy field
  or branch. The label-attack path is identical to earned topology.

## Why this clears the narrow threshold

The stipulated threshold is an earned topology that beats every relevant
equal-budget control after recoding and causal-law shifts. It does: 24,960 is
strictly greater than fixed topology, fixed vector, last outcome, fixed
schedule, random, replay, shuffled history, answer-memory, and ablation.
Unlike the earlier fingerprint negative, the fixed effect-vector comparator
does not tie after the law change; it reaches only 1,560. The decisive
remaining limitation is intentional: the finite raw transport and the generic
dependency-count operation are trusted substrate in a sealed synthetic world.

## Reproduce

```bash
mkdir -p /tmp/zig-am2-cache /tmp/zig-am2-global
zig build-exe sparse_poly_discovery/intervention_topology_round_am.zig -femit-bin=/tmp/intervention-topology-am2 --cache-dir /tmp/zig-am2-cache --global-cache-dir /tmp/zig-am2-global
/tmp/intervention-topology-am2 selftest
/tmp/intervention-topology-am2 run results/intervention_topology_round_am.csv
```

Expected self-test output:

```text
round_am_am2 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true shifts=true recoding=true all_controls_beaten=true answer_scrubbed=true
```

The exact machine-generated ledger is
[`results/intervention_topology_round_am.csv`](../../results/intervention_topology_round_am.csv).
