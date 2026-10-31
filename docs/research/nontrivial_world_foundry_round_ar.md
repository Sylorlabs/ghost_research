# AR1 — nontrivial procedural world foundry

**Verdict: GATE READY infrastructure only.** AR1 builds a deterministic, evaluator-owned source of anonymous dynamic worlds. It does not demonstrate discovery, real-world knowledge, general intelligence, or self-authored worlds.

## What is generated

Each full ledger generates **60,000** worlds across **32** hidden law families; families 24–31 are held out. Every world contains **64** interacting components propagated for **480** steps, with delayed state, family-dependent topology, deterministic noise/distractors, and constrained raw-byte interventions. This is 1,843,200,000 component propagation events per ledger. The candidate-facing surface is a 16-byte opaque raw observation frame and a raw action byte only. It has no family ID, seed, rule, target, score, progress, partition flag, or provenance key.

The held-out family split is evaluator-owned. The CSV records aggregate work and deterministic receipts but never candidate-visible values. The full computation is intentionally substantial propagation work, not `sleep` or a busy-wait; the self-test requires the first full ledger to take at least five seconds and caps it at sixty seconds on this machine.

## Fixtures and checks

- all 32 families must occur, with nonempty train and held-out partitions;
- opaque raw frames deliberately omit rule/family/answer/target/score/progress;
- fixture receipt records denial of rule, family, answer, target, score, progress, train/held-out overlap, and provenance mismatch channels;
- two independent full ledgers must be byte-identical and have equal checksums;
- checkpoints expose aggregate work only, not per-world hidden state.

## Reproduce

```sh
zig build-exe sparse_poly_discovery/nontrivial_world_foundry_round_ar.zig -O ReleaseSafe -femit-bin=/tmp/ar1
/tmp/ar1 selftest
/tmp/ar1 run results/nontrivial_world_foundry_round_ar.csv
```

The printed wall time is intentionally outside the deterministic CSV. It measures actual local propagation work, while the CSV remains replayable byte-for-byte.

## Measured receipt

Fresh `ReleaseSafe` build on this machine completed the first 60,000-world
ledger in **5,573 ms** and then completed a second independent full ledger with
the same 1,843,200,000 propagation events and byte-identical CSV. The final
ledger checksum is `9eb8e4546dfac6e0`; it contains 15,001 held-out worlds and
44,999 train worlds. The timing comes from propagation/generation/opaque-frame
work itself, with no sleeps or artificial delay loop.

## Limits

This is a large synthetic generator, not an open real world. Its components, propagation grammar, action interface, resource ceiling, and evaluator are still human-authored. It is only a foundation on which later candidate-owned exploration and self-authored-world tests can be run.
