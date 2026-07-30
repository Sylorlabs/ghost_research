# Round V / V3 — Evolution-development ecology

**Verdict: CONTROLLED EVODEVO ECOLOGY FOUNDATION.** This experiment builds and
replays a bounded two-timescale ecology. It does **not** establish intelligence,
open-ended evolution, accumulating capability, or earned causal inheritance.

## Question

Can genotype, development, lifetime adaptation, reproduction, mutation
strategy, and independently growing worlds coexist without mixing lifetime
state into heredity or exposing evaluator material?

## Construction

Sixteen organisms begin from deterministic raw genotype and mutation-strategy
bytes. Genotype develops into an eight-byte somatic body. During interaction,
raw outcomes may change only that somatic body. Reproduction receives the
previous Sigil-style committed genotype and mutation strategy, never the
adapted body.

Each generation follows:

1. freeze all inherited bytes and compute a commit digest;
2. derive evaluator-owned worlds from that digest using an eleven-byte
   recurrence structurally separate from organism development;
3. measure lifetime interaction and resource cost;
4. create scratch descendants by encoded mutation strategy;
5. commit or roll back the descendant batch; and
6. snapshot aggregate lineage measurements.

World depth grows from 3 to 5 over twelve generations and is constructed only
after the organism population freezes. No prose, LLM, embedding, named task,
semantic feature, supplied curriculum, Rune seed, answer trace, or Ghost
solution mechanism enters the organism.

## Result

The normal ecology retained all 16 distinct genotype lineages and all 16
observed first-byte mutation strategies at generation 12. Across twelve
generations it recorded:

- 5,837 bits of lifetime somatic change;
- 1,565 bits of inherited genotype change;
- 19,584 charged interaction units;
- raw mismatch score range 82.375–93.813 as world depth grew; this score is an
  observation, not evidence of improvement; and
- direct mutation-strategy interventions changed developed descendant bodies
  by 249 bits at generation 0 and 154 bits at generation 11.

The strategy result is measured on developed bodies, not hashed identifiers.
It establishes that an encoded strategy byte changes descendant phenotype
distributions. It does not establish that the change is adaptive.

## Hostile controls

Fresh selftest runs inject and verify ten controls:

| Control | Required observation |
|---|---|
| collapsed lineage | inherited change collapses rather than being promoted |
| shuffled heredity | strategy ancestry is deliberately broken and labelled |
| bloat | an extra 300 units per organism per generation are charged |
| replay | parent replay collapses strategy diversity |
| favorable birth | birth ordering is not an evaluator-score selection surface |
| shared generator | deliberate organism/world structural contamination is detected |
| answer leakage | policy CSV contains no answer, hidden seed, target, or per-target score |
| post-freeze mutation | the entire descendant batch rolls back |
| duplicate evidence | unchanged descendants are rejected rather than promoted |
| deterministic replay | two fresh normal runs are byte-identical |

The immutable evaluator/resource/provenance boundary remains outside mutable
organism bytes. The CSV exposes aggregate measurements and commit digests, not
world fields or private evaluator state.

## Interpretation and boundary

V3 answers a plumbing question positively: lifetime change and inherited change
can remain distinct while mutation strategy evolves, diversity persists, worlds
grow independently after freeze, and lineage replays exactly.

It deliberately does not use outcome-based reproductive selection. Therefore
it does not show that descendants become more capable, inherit earned causal
mechanisms, or improve their own mutation strategy. Those are V4/V5 questions
and still require V1/V2 plus a separate earned-inheritance experiment. A stable
population of different mutants is ecology machinery, not intelligence.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/evodevo_ecology_round_v.zig \
  -femit-bin=/tmp/evodevo_v3 \
  --cache-dir /tmp/zig-cache-v3 \
  --global-cache-dir /tmp/zig-global-v3
/tmp/evodevo_v3 selftest
/tmp/evodevo_v3 run results/evodevo_ecology_round_v.csv
```

Canonical artifacts:

- `sparse_poly_discovery/evodevo_ecology_round_v.zig`
- `results/evodevo_ecology_round_v.csv`
- `docs/research/evodevo_ecology_round_v.md`
