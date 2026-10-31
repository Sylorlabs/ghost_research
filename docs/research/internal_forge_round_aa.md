# Round AA / AA2 — internal evidence-directed forge

## Verdict

**BLOCKED by AA1; this is not a negative forge result.**

AA2 was required to consume autonomous executable distinguishing-evidence
lineage from AA1. The landed AA1 organism row is explicitly
`VALID_NEGATIVE`: 24 charged experiments leave uncertainty 1 and resource loss
3446, but its VM supplies the experiment byte-field interpretation and
retirement axis. Its trace digest is reproducible, yet it is not evidence that
the organism invented the experiment partition.

Running a forge from that lineage would quietly restore the human-shaped
"drill" forbidden by this round. AA2 therefore abstains before retrieval,
synthesis, transfer evaluation, or candidate installation. No forge candidate
exists and no transfer partition is opened.

## What was implemented

`internal_forge_round_aa.zig` is a fail-closed integration and provenance gate.
It reads the canonical AA1 CSV and requires all of:

- an explicit autonomous-experiment positive marker;
- executable trace lineage;
- no valid-negative marker;
- no hidden-question-grammar failure.

The actual AA1 ledger fails those conditions. The canonical AA2 ledger records
26 upstream rows and zero evidence, retrieval, forge, and transfer charges: the
organism honestly declined to build because admissible evidence was absent.

This is the behavior the desired autonomous forge needs when the world has not
yet supplied enough evidence. Substituting a fixture, request packet, fixed
menu, human implementation, or evaluator-private direction would create a fake
positive.

## Hostile controls

The selftest proves that:

- a positive-looking string cannot override a negative or hidden-grammar row;
- a positive marker without executable lineage is rejected;
- missing upstream evidence cannot be replaced with a fixture;
- evaluator/transfer data is never read while blocked;
- no uncharged candidate trials or post-test selection occur;
- abstention does not create bloat or a mutable frozen candidate;
- transcript answers, LLMs, text models, embeddings, symbolic features, names,
  and semantic ports are absent.

Replay is byte-identical.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/internal_forge_round_aa.zig \
  -O ReleaseSafe \
  --cache-dir /tmp/zig-aa2-cache \
  --global-cache-dir /tmp/zig-aa2-global \
  -femit-bin=/tmp/internal_forge_round_aa
/tmp/internal_forge_round_aa selftest
/tmp/internal_forge_round_aa run \
  results/internal_forge_round_aa.csv \
  results/autonomous_uncertainty_round_aa.csv
```

## What unlocks AA2

AA2 should be rerun only after an upstream experiment-maker produces accepted
lineage without supplied experiment fields, responsibility partitions, or an
intermediate correctness axis. At that point the forge must still beat
request-free broad, fixed/menu, random, replay, existing-only, no-evidence, and
false/shuffled-evidence controls at equal total cost; show frozen fresh-world
gain; lose the gain under candidate ablation; and abstain when uncertainty
remains unresolved.

Artifacts:

- `sparse_poly_discovery/internal_forge_round_aa.zig`
- `results/internal_forge_round_aa.csv`
- `docs/research/internal_forge_round_aa.md`
