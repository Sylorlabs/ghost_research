# Round AC / AC3 — functional re-encoding reconstruction

**Verdict: VALID NEGATIVE.** Fresh causal interaction can rebuild a useful
fixed-width tape after private relocation, bijective value recoding, changed
intervention grouping, or all three together. The combined transform rises
from **91,534** resource to **144,574**, versus **92,874** for equal-budget
random variation, and removal returns exactly **91,534**. This is genuine
functional relearning rather than byte preservation. It is not organism-owned
representation reconstruction: the host still supplies bytes, intervention
iteration, grouping physics, and the candidate-byte procedure.

## Question and isolation

Does learned causal experience recover useful behavior when address, value,
and segment identity are destroyed, without providing the organism an inverse
map, fixed decoder, component table, answer trace, semantic target, candidate
menu, or intermediate correctness score?

Twenty-four independently seeded organisms begin from opaque 48-byte tapes.
The evaluator privately chooses a per-cohort relocation and value mask. The
combined attack additionally changes charged intervention grouping from one
raw location at a time to groups of three. Search sees only ordinary aggregate
resource consequences over eight calibration contexts. Candidates freeze
before twenty disjoint fresh contexts; work is charged equally.

“Reconstruction” here means earning comparable fresh resource again. No byte
hash, address, segment, or selected successor is required to match the native
run.

## Fresh results

| Transform / policy | Charged trials | Old | Committed | Commits |
|---|---:|---:|---:|---:|
| native causal relearning | 110,592 | 91,534 | 143,894 | 24/24 |
| private relocation | 110,592 | 91,534 | 145,114 | 24/24 |
| bijective value recoding | 110,592 | 91,534 | 144,334 | 24/24 |
| changed segmentation | 110,592 | 91,534 | 143,894 | 24/24 |
| **combined destruction** | 110,592 | 91,534 | **144,574** | 24/24 |
| copied bytes | 0 | 91,534 | 91,534 | 0/24 |
| address-first partial search | 110,592 | 91,534 | 98,194 | 24/24 |
| static | 0 | 91,534 | 91,534 | 0/24 |
| random, same proposal source | 110,592 | 91,534 | 92,874 | 13/24 |
| prior-cohort replay | 0 | 91,534 | 94,334 | 15/24 |
| shuffled intervention order | 110,592 | 91,534 | 144,094 | 24/24 |
| false evidence | 110,592 | 91,534 | 91,534 | 0/24 |
| evaluator-private oracle ceiling | 0 | 91,534 | 184,314 | 24/24 |

Causal removal is exact: the combined run falls from 144,574 back to 91,534.
False evidence rolls back every cohort. Deterministic replay is byte-identical.
Copied state, static state, address priority, random variation, and replay do
not reproduce the gain.

The shuffled-order control loses only 480 resource. This is expected for the
current separable world: intervention order carries little causal information.
It is also an important limitation—this experiment does not demonstrate
discovery of relational or temporally bound structure.

## Why the full claim fails

The experiment destroys the identity of an existing representation, but does
not let the organism invent the physics by which representations are changed.
The host still declares:

1. that mutable atoms are bytes;
2. how those atoms are iterated and grouped;
3. a fixed procedure that emits alternative byte values; and
4. that a whole tape is the candidate committed or rolled back.

Those choices are answer-free, yet they are precisely the mutation ontology
and proposal machinery Round AC requires the organism to own. “Resegmentation”
is a hostile transport change selected by the evaluator, not an organism-born
new edit scale. The strong numeric result therefore establishes only a bounded
fact: black-box causal hill-climbing can relearn a separable function after
wholesale representation transport.

AC3 cannot release AC4. A successor test must receive only universal raw
interaction/computation and must make its own executable intervention media,
candidate-production dynamics, boundaries, and grouping. Those structures
must themselves be mutable and causally replaceable, then recover useful
function after hostile re-encoding.

## Reproduce

```bash
mkdir -p /tmp/zig-ac3-cache /tmp/zig-ac3-global
zig build-exe sparse_poly_discovery/functional_reencoding_round_ac.zig \
  -femit-bin=/tmp/functional-reencoding-ac3 \
  --cache-dir /tmp/zig-ac3-cache --global-cache-dir /tmp/zig-ac3-global
/tmp/functional-reencoding-ac3 selftest
/tmp/functional-reencoding-ac3 run results/functional_reencoding_round_ac.csv
```

Expected:

```text
round_ac_ac3 selftest PASS verdict=VALID_NEGATIVE deterministic=true functional_relearning=true ontology_owned=false
```

Artifacts:

- `sparse_poly_discovery/functional_reencoding_round_ac.zig`
- `results/functional_reencoding_round_ac.csv`
- `docs/research/functional_reencoding_round_ac.md`
