# Research Round 2026-07-11 (Round E) — attacking the two real levers: aim × representability

**Status:** LIVE — updated as each experiment lands. 0/6 complete.
**Plan:** `research_round_2026_07_11_PLAN.md`. **Premise (the four-round arc):**
the ceiling is **AIM × REPRESENTABILITY** — not compute (H50), not quantity
(D1/D2), not diversity-alone (D6: conditional), not human-vs-non-human grammar
(D3). Round D's capstone (D5): "more" cannot manufacture the missing generator
or aim; that needs insight, and quantity can't buy insight when it isn't cheap
to stumble into. Round E attacks the two levers directly, plus the
auto-discovery meta-frontier (sharpened by D5's "failure is in generation"),
the honest open-target push (aim not breadth, per D4), the capstone predictor,
and the next instrument audit.

Constraints unchanged: new files only, standalone `zig build-exe`, ≤2 threads /
≤15 min runs, independent verification per claim, negatives are findings,
equal-budget comparisons, leakage guards, main session commits centrally, doc +
commit + TOC + "Belongs to" banner per landing.

---

## Verdict table

| # | Experiment | Lever | Status | Headline | Doc |
|---|-----------|-------|--------|----------|-----|
| E1 | Representability expansion | representability | pending | — | `docs/research/repr_expansion.md` |
| E2 | Learned aim / target router | aim | pending | — | `docs/research/target_router.md` |
| E3 | Smart generation for auto-discovery | meta (generation) | pending | — | `wcore/docs/research/smart_gen.md` |
| E4 | Assembled aimed engine on an OPEN target | the goal | pending | — | `boundary_crossing/docs/research/aimed_open.md` |
| E5 | Aim × representability unified predictor | theory capstone | pending | — | `docs/research/aim_repr_predictor.md` |
| E6 | coevo-side 12×32 matcher audit | instrument trust | pending | — | `wcore/docs/research/coevo_matcher_falsification.md` |

---

## Why these six (adapted to Round D's outcomes)

- **E1 + E2** are the two levers made into direct experiments: grow *what can be
  represented* (E1), and *learn where to aim* (E2). D6 proved diversity pays
  only when it spans the target's closure — E1 makes spanning a deliverable, E2
  makes aiming learned instead of handed-in.
- **E3** is the D5 pivot: D5 proved *blind bulk* generation can't auto-discover
  the decomposition and localized the failure to GENERATION (detection works).
  E3 keeps D5's proven detector and swaps in *smart* generators — the sharpest
  test of whether machine auto-discovery is possible at all, or whether the
  human insight is fundamentally required.
- **E4** is the honest goal attempt, using D4's lesson: aim, not raw breadth.
- **E5** turns the arc's law into a quantitative model with a phase-boundary test.
- **E6** continues the instrument-trust discipline round c named (the coevo-side
  12×32 matcher, potentially undermining the Claim-C 85/86 headline).

**Adaptive branch already resolved:** because D5 failed, E3 is framed as
"smart generation vs the proven-hard generation problem," and a *negative* E3
(smart generation also fails) is the single most important possible finding —
it would bound machine auto-discovery precisely.

*(Verdicts and synthesis added as agents land.)*
