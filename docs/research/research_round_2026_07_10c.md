# Research Round 2026-07-10c — crossing the conjunction wall

**Status:** LIVE — updated as each experiment lands. 0/6 complete.
**Predecessors:** `research_round_2026_07_10.md` (8/8) and
`research_round_2026_07_10b.md` (6/6). Round b's settled architecture: *inner
loops explore un-aimed and un-gated; aim, taxes, and novelty verdicts act at
selection boundaries.* Round b's named successor problems are this round's
experiment list, plus the integration test nobody has run: all the settled
pieces together.

Constraints unchanged: new files only (single exception: the taxfix agent has
exclusive permission to edit `equivalence_tax.zig`), standalone
`zig build-exe`, ≤2 threads / ≤15 min runs, independent verification per
claim, negatives documented as findings, main session commits centrally.

---

## Verdict table

| # | Experiment | Question | Status | Headline | Doc |
|---|-----------|----------|--------|----------|-----|
| 1 | Conjunction wall (wcore) | Do stepping-stone curricula or mechanism-level descriptors lift the distinct-count climb past the 0.862 plateau to the 0.95 bar? | pending | — | `wcore/docs/research/conjunction_wall.md` |
| 2 | Evidence lenses (battery-C) | Do second-order / conditional / order-statistic lenses beat the (1/3)^k signal decay — reaching degree-5 C11 and family-miss C09? Baseline 8/33. | pending | — | `docs/research/tier8_evidence_lenses.md` |
| 3 | greedyFit z-scoring fix | Fix the raw-vs-z-scored mismatch; do the 5 leaked battery-D candidates reclassify, and do prior verdicts (11/11 battery, gate v5) survive? | pending | — | `docs/research/tier8_taxfix.md` |
| 4 | Matcher falsification (wcore) | Can the 0.95 / 8×28 statistical matcher be made to lie (false-equal, false-different, seed-flips)? What protocol fixes it? | pending | — | `wcore/docs/research/matcher_falsification.md` |
| 5 | Assembled engine | Do revision + aimed proposal + v5-ladder verdict + export-filter tax cohere in ONE pass across batteries B/C/D, or interfere? | pending | — | `docs/research/tier8_assembled.md` |
| 6 | D08/C09 reachability gap | Is the gap family-level (proven)? Does the minimal comparison-aggregate family close it, at what cost signature? | pending | — | `docs/research/tier8_reach_gap.md` |

---

## Design notes

- Exp 1 is the headline: the conjunction wall is the round-b successor problem
  with a measured target (0.862 → ≥0.95). Exps 2 and 6 attack the two other
  named walls (signal decay; family-level reach) from the proposal side.
- Exps 3 and 4 are the instrument-trust pair: the third greedyFit-adjacent
  defect in two days gets fixed with full verdict-migration accounting, and
  the certifier's new thinnest axis (the 0.95 matcher, 0.008 margin) gets the
  I53 treatment.
- Exp 5 is the coherence test: every settled piece has only been measured in
  isolation. Integration regressions are a finding, not a failure.
- Concurrency note: exp 3 edits `equivalence_tax.zig` while exp 5 builds
  against it — exp 5 records which version it ran against; exp 6 avoids the
  tax entirely (pre-tax reach question).

*(Verdicts and synthesis added as agents land.)*
