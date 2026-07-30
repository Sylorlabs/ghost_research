# AB1 — causal room birth
**Verdict: VALID NEGATIVE.** A uniform-tape organism can grow useful,
overlapping variable-size subsets from ordinary downstream resource returns,
and can relearn them after storage relocation/re-encoding.  It does **not**
invent what a room can be: the host still supplies arbitrary subset membership
as the candidate-room grammar.  No architecture-owning or representation-birth
claim is warranted.

## Question and contract

AB1 removes declared components, fragment widths, action slots, edit addresses,
task names, feature names, request packets, pretrained Runes, language models,
embeddings, neural models, symbolic task rules, and intermediate correctness,
novelty, grounding, or uncertainty rewards.  Each cohort begins with a uniform
16-cell raw self-tape and an empty provisional room.

The organism-owned proposal stream may toggle arbitrary membership, perform
multi-cell edits, and periodically dissolve part of a room.  A proposal is
retained only when its ordinary resource consequence, minus charged structural
cost, improves across six calibration contexts.  The room freezes before 24
disjoint hidden contexts.  Evaluator-private five-cell causal sets are used
only to build the world's resource physics and oracle audit; they never enter
organism evidence.

This is a deliberately exhaustive microscope, not a claim about an unbounded
self.  The raw-cell count, budget, and universe physics remain immutable.

## Fresh result

Across 32 independently seeded cohorts, the born rooms produced **90,416**
held-out resource at 61,440 charged proposal-context trials.  They beat every
ordinary control:

| Policy | Held-out resource | Exact evaluator-private rooms |
|---|---:|---:|
| organism-born subset | **90,416** | 0/32 |
| empty-room ablation | 61,400 | 0/32 |
| best ordinary control (age surrogate) | 59,288 | 0/32 |
| random full-width room | 55,736 | 0/32 |
| fixed size 4 | 56,744 | 0/32 |
| fixed size 8 | 49,928 | 0/32 |
| prior-cohort replay | 57,416 | 0/32 |
| shuffled learned rooms | 52,304 | 0/32 |
| evaluator-private oracle ceiling | 127,448 | 32/32 |

Removal erased the learned gain (**61,400**); restoration returned it exactly
(**90,416**).  A relocated and recoded tape, relearned without the inverse map,
also returned **90,416**.  Thus the gain is not attached to one address layout.
However, no cohort recovered the exact private causal set.  The learner found
resource-useful partial partitions, not complete causal rooms.

## Why this is still a negative

The result beats raw-address, fixed-size, random, replay, frequency, age,
human-origin, and shuffled-partition controls.  That is real evidence that
ordinary resource selection can grow useful temporary groupings.

But a candidate is represented as a host-defined bitset over raw cells.  The
host therefore decides in advance that a room is “some subset of cells” and
provides membership-toggle/split-like operations.  Those operations do not
contain the evaluator-private target, yet they install the ontology in which
the target is expressible.  AB1 moved the walls; it did not invent the material,
dimensionality, or semantics from which walls are made.

The exact audit verdict is consequently **VALID NEGATIVE**, per the Round AB
contract: hidden boundary grammar remains.

## Hostile controls

The executable ledger records checks for disjoint calibration/hidden contexts,
private truth isolation, equal charged proposal work, complexity cost, duplicate
evidence, favorable birth variation, freeze-before-test, post-test edits,
determinism, removal/restoration, shuffled partitions, recoding/relocation, and
absence of LLM/text/token/embedding/neural/neuro-symbolic paths.  The explicit
failing attack is `hidden_boundary_grammar_subset_membership_is_host_supplied`.

## Reproduce

```bash
mkdir -p /tmp/zig-ab1-cache /tmp/zig-ab1-global
zig build-exe sparse_poly_discovery/causal_room_birth_round_ab.zig \
  -femit-bin=/tmp/causal-room-ab1 \
  --cache-dir /tmp/zig-ab1-cache \
  --global-cache-dir /tmp/zig-ab1-global
/tmp/causal-room-ab1 selftest
/tmp/causal-room-ab1 run results/causal_room_birth_round_ab.csv
```

The self-test performs two fresh byte-identical ledger generations and requires
both the hidden-grammar failure and valid-negative closure.

## Next evidence edge

Do not merely enlarge or randomize the subset search.  The next substrate must
allow the organism to construct and compete **different partition media**—for
example temporal processes, causal transformations, executable predictors, and
relational closures—without a privileged universal `cell membership` form.
The universe may trace their raw consequences, but no host-provided candidate
type should be the sole route to credit.
