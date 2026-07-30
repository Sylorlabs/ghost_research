# Round AC / AC1 — endogenous mutation ontology

**Verdict: VALID NEGATIVE.** Mutable executable words learned useful variable
edit scales without a supplied component table, but the host still supplied
the interpreter that says how a word becomes an edit and how words rewrite one
another. This is self-parameterizing mutation physics, not organism-created
mutation physics.

## Experiment

Twenty-four independently seeded organisms began with eight unlabelled mutable
16-bit words over a uniform 48-cell substrate. No hidden causal set, answer
trace, named feature, component boundary, room, target score, correctness score,
operator menu, language model, token model, embedding, neural model, or imported
algorithm was exposed. Evaluator-private worlds converted raw interventions to
ordinary resource returns.

Each word executes into a process with a start, stride, extent, and phase. The
combined processes can overlap and cancel, thereby producing variable edit
scales. Mutations can change a word or cause one word to replace another. Only
resource consequences select frozen successors. This permits effective
creation, overlap, dissolution, replacement, and scale change, but those verbs
are consequences of a fixed interpreter rather than new semantics invented by
the organism.

## Fresh results

All learned and search controls received 18,432 charged proposal evaluations
(768 per cohort). Frozen evaluation totals were:

| condition | resource |
|---|---:|
| mutable executable-word ontology | **52,735** |
| raw-bit control | 42,612 |
| empty ablation | 42,712 |
| raw-byte control | 41,691 |
| fixed static structure | 38,580 |
| false evidence | 37,941 |
| shuffled evidence | 37,195 |
| prior-cohort replay | 36,101 |
| random | 35,227 |
| evaluator-private oracle ceiling | 65,952 |

Removal erased 10,023 resource units. Shuffled and false evidence also erased
most of the gain, showing that evidence binding—not age or raw variation—does
real work. A relocated/value-reseeded run reached 52,683 and a resegmented run
52,378. Those close aggregate totals show relearning robustness, but do not
prove functional identity: the successors differ and the attack changes search
seeds rather than implementing a genuinely independent universal encoding.

## Why the ownership claim fails

The organism owns every evolving word and no human-origin word is privileged.
But humans still wrote three decisive laws:

1. a word is decoded as start/stride/extent;
2. a bit flip is a legal mutation primitive;
3. one decoded word may overwrite another at a host-defined cadence.

Consequently the experiment supplies an answer-free but expressive mutation
language. The organism searches that language; it does not construct or replace
the language or interpreter. Raw host bits alone are allowed by the Round AC
contract, but the fixed semantic mapping above bits is organism-internal
scaffolding and therefore disqualifying. Wholesale encoding reconstruction is
also not established. AC1 must not release AC4.

## Exact accounting and controls

The CSV records cohort count, charged proposal-context trials, and frozen
resource for raw bit, raw byte, fixed, random, replay, ablation, shuffled/false
evidence, relocation/value reseeding, resegmentation, and the private oracle.
The program regenerates the ledger twice in memory and requires byte-identical
output. Evaluation truth is used only by universe resource physics and the
oracle audit; selection sees only scalar resource.

The strongest hidden-human-residue finding is
`fixed_seed_stride_extent_interpreter_and_bitflip_rewrite_physics`.

## Reproduce

```bash
mkdir -p /tmp/zig-ac1-cache /tmp/zig-ac1-global
zig build-exe sparse_poly_discovery/endogenous_mutation_ontology_round_ac.zig \
  -femit-bin=/tmp/endogenous-ac1 \
  --cache-dir /tmp/zig-ac1-cache --global-cache-dir /tmp/zig-ac1-global
/tmp/endogenous-ac1 selftest
/tmp/endogenous-ac1 run results/endogenous_mutation_ontology_round_ac.csv
```

Expected self-test:

```text
round_ac_ac1 selftest PASS deterministic=true verdict=VALID_NEGATIVE born=52735 recode=52683
```

## Next evidence edge

Do not add more opcodes. The next substrate must permit executable matter to
construct a second interpreter from raw transition traces, causally retire the
first, and reconstruct useful behavior after an independently specified
encoding changes every boundary and instruction identity. The comparison must
charge interpreter construction and must include a fixed expressive-language
control; otherwise it only rewards a larger human grammar.
