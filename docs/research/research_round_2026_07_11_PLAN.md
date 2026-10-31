# Research Round 2026-07-11 (Round E) — PLAN: attacking the two real levers

**Status:** PLANNED — launches immediately after Round D (`research_round_2026_07_10d.md`)
closes (experiments #1 breadth-vs-depth and #5 auto-curriculum land + docced).
Not launched yet: Round D's two heaviest experiments are still running and the
machine is saturated; stacking Round E now would thrash both.

## What the four-round arc established (the premise for Round E)

Rounds a–d converged, with measurements, on a single sentence:

> **The ceiling is AIM × REPRESENTABILITY — not quantity, not compute, not
> human-vs-non-human grammar.**

- **Compute** doesn't cross it (H50: 372-eval depth plateau).
- **Breadth/quantity** doesn't cross it (D2: breadth plateaus like depth).
- **Diversity** helps *only* when it spans the target's closure (D6: R²≈0.4,
  conditional; wrong-direction diversity buys nothing).
- **Grammar** isn't the limit — the engine is already 92.4% non-human (D3), but
  unaimed non-human richness underperforms aimed search.
- **Aim** is the scarce resource (b: gate-level aiming; c: conjunction wall
  crossed by aimed curriculum; d: aim beats grammar).
- **Representability** is the hard wall — some targets are provably outside every
  current family's span (c: C09 by Bayes ceilings; d: only 4/15 cells
  representable), and no budget on any axis crosses it.

So Round E attacks the two levers directly, plus the auto-discovery meta-frontier
and the honest open-target push.

## Experiments (6)

| # | Experiment | Lever | Question |
|---|-----------|-------|----------|
| E1 | **Representability expansion** | representability | Systematically grow the family menu under the certifier (modular beyond mod-k, threshold/counting, algebraic, stateful/recursive). Per family added: how many previously-unrepresentable targets (C09-class, D2-unreachable) become representable? The Closure-Principle escape done systematically — each family is a generator, measure the closure expansion, none admitted without earning it. |
| E2 | **Learned aim / target router** | aim | Can the proposer LEARN which family/lens/decomposition cracks an unsolved target from its failure signal, instead of being handed it? A router: unsolved target → predicted family → aim. Beat fixed-aim and random-aim across the battery. Generalizes round-c's exact-GF(2) identification to a learned selector. |
| E3 | **Auto-family discovery** | meta (aim+repr.) | The deepest frontier: given a target outside ALL current families, can the loop propose + certify + promote a NEW primitive family (not just a member) autonomously? Successor to D5 (auto-*decomposition*) one level up. Adaptive: if D5 succeeded, extend it; if it failed, diagnose the barrier. |
| E4 | **Assembled aimed engine on an OPEN target** | the goal | Point the full stack (framework revision + aimed proposer + v5-ladder + E1's new families) at a genuinely open problem with a cheap exact verifier where a certified result would be new-to-humanity: LABS records (with the even-N understanding), un-tabulated addition-chain records, or a small open combinatorial bound. The honest attempt at the actual goal, all levers assembled. Independent verification mandatory; EXTRAORDINARY-NEEDS-SCRUTINY protocol. |
| E5 | **Representability × aim unified predictor** | theory capstone | Build the full model: reach ~ f(representability, aim-quality, diversity). Which dominates? Is there a phase boundary — does aim only matter once representability is satisfied? The quantitative unifying law of the whole 4-round arc, extending D6's diversity predictor. |
| E6 | **coevo-side 12×32 matcher audit** | instrument trust | Round c red-teamed the 0.95/8×28 matcher (4.2% false-equals) and named the coevo-side 12×32 matcher as the next instrument to audit — same horizon/threshold mechanics likely apply. CPU-only, no API. Keeps the instrument-trust discipline going. |

## Adaptivity to Round D's tail

- **E3 depends on D5 (auto-curriculum):** if D5 auto-discovers the decomposition,
  E3 extends it to family-level; if D5 fails, E3's first job is diagnosing why
  (is the barrier proposal, certification, or the payoff test?).
- **E4's target choice** uses D4 (LABS swarm) + labs_even_n findings on which
  lengths are closest, and D1 (breadth-vs-depth) on whether to run E4 as one deep
  aimed attempt or a diversity-spanning pool.
- Finalize E1's family menu and E2's router features after reading D1/D5.

## Optional / user-gated (NOT auto-launched)

- **lm_baseline executed** — the built-but-unrun LLM-as-addition-chain-generator
  head-to-head (`boundary_crossing/docs/research/lm_baseline.md`). Directly
  answers the AlphaEvolve comparison, but makes **live `claude` CLI calls (API
  cost)** — needs an explicit go-ahead or a capped small-sample budget. Held out
  of the auto-launched set for that reason.

## Constraints (unchanged)

New files only, standalone `zig build-exe`, ≤2 threads / ≤15 min runs, independent
verification per claim, equal-budget comparisons, negatives documented as
findings, main session commits centrally, doc + commit + TOC per landing, the
"Belongs to" round banner on every doc.
