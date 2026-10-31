# Round AD / AD3 — self-hosted causal compiler/transducer

**Verdict: VALID NEGATIVE.** A mutable raw-matter layer can be constructed
from only aggregate causal resource traces, migrate useful behavior, survive
private relocation/value recoding/resegmentation/instruction permutation, and
be causally necessary. That is a bounded construction capability, not a
machine-created compiler. The alleged transducer is tied by a fixed decoder and
an equal-capacity fixed language, and the host still owns the byte atoms, XOR
physics, trial generator, array boundary, and transaction geometry.

## Question and sealed setup

Each of 18 organisms starts with an opaque 32-cell representation and an empty
32-cell mutable matter layer. It receives only aggregate resource consequences
from seven calibration interactions. The evaluator privately supplies the
world's causal consequences and keeps the target relation, answer values,
relocation map, value mask, segmentation, and instruction permutation hidden.
The organism constructs a raw matter layer whose physical effect mediates the
representation-to-behavior relation. Construction costs every calibration
interaction; candidates freeze before 19 fresh evaluator worlds. A cohort is
committed only when its sealed fresh resource improves, otherwise it rolls
back.

This is intentionally not called an open-ended positive. The source makes the
lower-level host transition explicit: a raw matter byte combines with a raw
representation byte by fixed XOR. It also supplies a bit-flip trial loop and
whole-array commit/rollback. Those are not exterior-only enforcement physics;
they are a mutation and execution ontology.

## Results

| Wholesale transform policy | Charged calls | Old fresh resource | Committed | Commits |
|---|---:|---:|---:|---:|
| self-hosted mutable transducer | 32,256 | 44,089 | **54,957** | 18/18 |
| fixed decoder, equal budget | 32,256 | 44,089 | **54,957 (tie)** | 18/18 |
| equal expressive fixed language | 32,256 | 44,089 | **54,957 (tie)** | 18/18 |
| copied raw bytes | 0 | 44,089 | 44,089 | 0/18 |
| random raw matter, same capacity | 0 | 44,089 | 45,495 | 6/18 |
| prior-cohort replay | 0 | 44,089 | 45,457 | 7/18 |
| shuffled evidence addresses | 32,256 | 44,089 | 54,957 | 18/18 |
| false causal evidence | 32,256 | 44,089 | 44,089 after rollback | 0/18 |
| evaluator-private oracle | 0 | 44,089 | 87,599 ceiling only | 18/18 |

The source emits native, relocation-only, recoding-only, resegmentation-only,
instruction-permutation-only, and all-four-at-once rows. It repeats the run
byte-for-byte and checks that the combined self-hosted construction beats
random, improves over its pre-construction state, ties the fixed decoder, and
loses exactly its gain under causal ablation.

## Controls and interpretation

The fixed-decoder and equal-expressive-language controls are decisive. They
receive the same number of mutable cells, exactly the same bit-trial budget,
and no private answer values. If a named self-hosted compiler had been born,
its semantic construction should have exceeded these human-fixed alternatives.
Instead they tie exactly: search has optimized a host-supplied raw transition
relation.

The transport attacks establish only that behavior is recovered by function,
not by preserving old addresses or byte values. They do not establish that the
organism chose its own atoms, transition algebra, construction operators,
candidate boundaries, or commit semantics. The construction is therefore not
eligible to release AD4–AD6.

## Reproduce

```bash
mkdir -p /tmp/zig-ad3-cache /tmp/zig-ad3-global
zig build-exe sparse_poly_discovery/self_hosted_transducer_round_ad.zig \
  -femit-bin=/tmp/self-hosted-transducer-ad3 \
  --cache-dir /tmp/zig-ad3-cache --global-cache-dir /tmp/zig-ad3-global
/tmp/self-hosted-transducer-ad3 selftest
/tmp/self-hosted-transducer-ad3 run results/self_hosted_transducer_round_ad.csv
```

Expected:

```text
round_ad_ad3 selftest PASS verdict=VALID_NEGATIVE deterministic=true migration=true organism_owned=false
```

Remaining human-owned ontology: raw byte cells; the fixed XOR
representation-to-behavior transition; bit-flip candidate production and
search order; fixed 32-cell boundary; and transaction/rollback mechanism.
