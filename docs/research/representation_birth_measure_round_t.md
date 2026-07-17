# Round T T3 — Representation-Birth Measurement Gate

**Verdict: BLOCKED, by design.** This is an executable falsification gate, not
evidence that a representation has emerged. It refuses to promote a candidate
unless T1 supplies a raw-causal lineage and a genuinely substrate-independent
transfer result.

## Contract

T3 accepts an opaque fixed-size mechanism artifact and evaluator-private raw
byte observations. It freezes the artifact before fresh-world evaluation,
charges an equal observation budget, and checks a distinct hidden world
lineage. It rejects lookup tables, replay memory, named features/declared
candidate grammar, text or LLM dependence, hidden-answer access, post-freeze
mutation, and one-world-only success. The included fixture exercises all eight
anti-cheat checks: calibration **64/64**, fresh transfer **128/128**, and
byte/replay control passes.

That does **not** establish representation birth: its two bytes are a test
fixture, its provenance is not a T1 raw-causal trace, and the evaluator still
contains a declared generic byte-transition substrate. The canonical result is
therefore `anti_cheat=8/8; representation_birth=NOT_ESTABLISHED`.

## Scratch → committed → snapshot ledger

The ledger borrows only Ghost Engine's *transactional audit shape*: scratch
records calibration, committed records freeze and safety gates, and snapshot
records hidden transfer plus the verdict. Ghost Engine's Sigil reference
documents `begin scratch`, `commit`, `discard`, and `snapshot`; its Rune engine
has named arithmetic functions and a conventional forge/judge vocabulary.
T3 imports **none** of that code, no Rune values, no Sigil parser, no rank/VSA
representation, and no named mathematical feature. The relationship is
conceptual provenance discipline, not a symbolic substrate.

## Run

```bash
zig run sparse_poly_discovery/representation_birth_measure_round_t.zig -- selftest
zig run sparse_poly_discovery/representation_birth_measure_round_t.zig -- results/representation_birth_measure_round_t.csv
```

## Required next integration

T1 must provide a canonical, answer-free mechanism lineage: raw observations,
mutation history, freeze digest, and no human-semantic primitive declaration.
T2 must provide fresh challenge lineage after the digest is committed. Only
then may this gate evaluate a real candidate; a failed or unavailable criterion
remains **BLOCKED**, never silently credited.
