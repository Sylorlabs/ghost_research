# Round AG / AG1 — autopoietic loop birth

**Verdict: VALID NEGATIVE.** The material run has a genuine, deterministic
physical persistence effect: a four-unit arrangement is externally observed
for **128** loop-ticks across 32 cohorts, is externally disrupted at tick 70,
and is restored for **64** post-disruption loop-ticks. Removing its material
returns the record to **0**. Equal-material random, replay, static, shuffled,
and false-lineage controls also score **0**. This is not autopoietic birth:
the host wrote the four-cell arrangement, recognizes that exact four-cell
arrangement, and reinstates it after disruption. An equally expressive
host-fixed-loop control ties exactly at **128**.

## Question

Can raw mutable matter self-assemble, maintain and recover a causal loop under
finite-resource lower-level transport, then persist through sealed fresh media
without an organism-visible score, sensor/action API, target, grammar,
controller, boundary, replication template or host loop language?

The answer from this experiment is no. It is a deliberately narrow falsifier:
it demonstrates why a visually convincing persistent pattern is insufficient
when the exterior has smuggled in the pattern and its repair.

## Protocol

Each of 32 evaluator-private cohorts is a ring of 64 anonymous byte cells.
The only admitted running physics streams each raw cell's conserved material
one neighbouring location per deterministic tick. Material sees no callback:
no observation, action, reward, success flag, score, task, candidate, mutation
operation, controller, text, LLM, embedding, neural component, or symbolic
relation is present. The external evaluator only records runs afterwards.

For the active condition, however, the program writes four adjacent units at a
cohort-dependent location. At tick 70, it externally clears the field and
re-writes that same arrangement. This preserves total material exactly but is
plainly a host-defined loop seed and repair template. The evaluator externally
calls a configuration a loop only when precisely those four locations contain
the four material units. This measurement never reaches the matter, but it is
still a host loop grammar and boundary. All 5,120 raw transport ticks per
condition are charged (32 × 160); construction and disruption are listed in
the provenance ledger rather than hidden as free organism steps. The active
and fixed-loop rows therefore charge **5,376** (5,120 transport + 128 seed
units + 128 repair units); other four-unit controls charge 5,248.

Controls have equal time/material: no material (ablation), four units at
deterministic random sites, one replayed lump, static matter, shuffled and
false lineage. The fixed-loop control receives the same fixed host seed and
same host repair, so it directly tests whether any organism-specific discovery
was necessary. Attacks relocate raw addresses, recode values, resegment the
ring, and reverse the private transport direction. CSV generation is repeated
twice byte-for-byte by the self-test.

## Results

| Condition | Charged ticks | Pre-perturb loop ticks | Total loop ticks | Recovery ticks | Cohorts recovered |
|---|---:|---:|---:|---:|---:|
| host-seeded arrangement | 5,376 | 64 | **128** | **64** | 32 / 32 |
| material ablation | 5,120 | 0 | 0 | 0 | 0 / 32 |
| equal-material random | 5,248 | 0 | 0 | 0 | 0 / 32 |
| equal-material replay | 5,248 | 0 | 0 | 0 | 0 / 32 |
| static material | 5,120 | 0 | 0 | 0 | 0 / 32 |
| equal fixed host loop | 5,376 | 64 | **128 (tie)** | **64** | 32 / 32 |
| relocated / resegmented / reversed medium | 5,376 each | 64 | 128 | 64 | 32 / 32 |
| value recoding | 26,240 | 0 | 0 | 0 | 0 / 32 |

The ablation and control gaps are real as properties of this executable
simulation, but they provide no autonomy evidence. The exact fixed-loop tie
and failed value recoding are particularly diagnostic: the exterior's chosen
identity/measurement, not an organism-owned causal construction, carries the
effect.

## Why it is negative

1. `initial` is a human-written four-cell seed: it supplies a loop template
   rather than allowing a configuration to self-assemble.
2. `externalLoop` names four locations and a required arrangement. That is a
   host boundary plus a loop grammar, even though it is not shown to matter.
3. At perturbation, the host reconstructs the seed exactly. Thus restoration
   is neither endogenous nor evidence-dependent.
4. `fixed_loop` ties exactly. No mutable organism construction, selection, or
   self-maintenance mechanism is required.
5. No replication occurs; there is no legitimate lineage claim. The lineage
   hash is only external provenance for deterministic replay.

The irreducible allowed exterior was intended to be just raw transport and
finite material conservation. This trial intentionally violates the stronger
ownership claim through the seed, measurement and repair in order to expose
the failure mode. It does **not** unlock AG4.

## Reproduce

```bash
mkdir -p /tmp/zig-cache-ag1 /tmp/zig-global-ag1
zig build-exe sparse_poly_discovery/autopoietic_loop_round_ag.zig \
  -femit-bin=/tmp/autopoietic-ag1 --cache-dir /tmp/zig-cache-ag1 \
  --global-cache-dir /tmp/zig-global-ag1
/tmp/autopoietic-ag1 selftest
/tmp/autopoietic-ag1 run results/autopoietic_loop_round_ag.csv
```

Expected: `round_ag_ag1 selftest PASS verdict=VALID_NEGATIVE
deterministic=true raw_transport_conserved=true host_template_exposed=true`.

Artifacts: `sparse_poly_discovery/autopoietic_loop_round_ag.zig` and
`results/autopoietic_loop_round_ag.csv`.
