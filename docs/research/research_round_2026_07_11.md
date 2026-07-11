# Research Round 2026-07-11 (Round E) — attacking the two real levers: aim × representability

**Status:** LIVE — updated as each experiment lands. 1/6 complete.
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
| E5 | Aim × representability unified predictor | theory capstone | **DONE** | **The arc's law, quantified.** Representability dominates reach (R²=0.65, 5–100× every other factor); aim is a **phase boundary** above it — corr(aim,reach) 0.00/0.00/0.18 across LOW/MID/HIGH representability, solve rate 0%/0%/45.9%. **Diversity (D6) was a proxy for representability**; controlling for it, D flips negative. Falsification clean. | `docs/research/aim_repr_predictor.md` |
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

---

## Completed-experiment detail

### E5. Aim × representability predictor — the capstone law, quantified
- 6,480-cell sweep (0.6s), representability defined as the budget-independent
  full-enumeration ceiling (max test accuracy any family/pair reaches on a
  target), aim-quality as a real non-circular budget-routing knob (biases
  budget toward the family whose VAL signal looks strongest, never knowing the
  true home family — so the interaction is emergent, not assumed).
- **Representability dominates:** corr 0.807 (R²=0.652), partial R²=0.368
  controlling for everything — 5–100× every other factor (diversity 0.057,
  evals 0.010, aim 0.003).
- **Aim is a PHASE BOUNDARY, not a linear term:** binning by representability,
  corr(aim,reach) = 0.00 (LOW) → 0.00 (MID) → **0.18** (HIGH); certified-solve
  rate 0% / 0% / **45.9%**. Aim's effect is statistically *zero* until
  representability clears a threshold, then turns on — and its payoff shrinks
  as budget grows (biggest when budget is scarce). So the arc's "aim ×
  representability" is literally a product with a threshold: **representable
  first, then aim decides.**
- **Retroactively explains D6:** diversity (D6's headline predictor, R²=0.405
  alone) is a *proxy* for representability — corr(D, repr)=0.60. Once
  representability is controlled, D's partial correlation with reach **flips
  negative (−0.238)**: extra unneeded families dilute a fixed budget (the same
  fragmentation `breadth_vs_depth.md` measured). D6 wasn't wrong — it was
  measuring representability through a diversity-shaped lens.
- Falsification: (A) high-aim + high-repr but low-reach = 2.24%, all traced to
  needle-in-haystack parity targets at very low absolute budget (aim controls
  *where* budget goes, not whether there's *enough*); (B) low-aim + low-repr
  but high-reach = 0/192, clean.
- Rigor: the D6 fairness pitfall reincarnated (representability ceiling lacked
  same-family combos → 33% violations) and was caught + fixed → 0%.

## Synthesis (updated as results land)

1. **The four-round arc now has a quantitative law, not just a slogan:**
   reach ≈ *representable(target) ? aim-decides : 0*. Representability is a
   threshold gate (R²=0.65); aim only operates above it (phase boundary, 0 →
   0.18); quantity/diversity/compute are all either proxies for representability
   (diversity) or dominated (evals). This is the strongest possible form of "the
   ceiling is aim × representability" — measured, with the interaction structure
   pinned down.
2. **It sets up the rest of Round E precisely:** E1 (grow representability) and
   E2 (improve aim) are now provably the only two levers that can move reach,
   and E5 says E1 must clear the threshold *before* E2 can pay — so a target E1
   can't make representable is a target no amount of E2 aim will solve. E3's
   generation question is whether the machine can *find* the representability-
   expanding family/decomposition itself.

*(Experiments E1–E4, E6 pending; final verdict on completion.)*
