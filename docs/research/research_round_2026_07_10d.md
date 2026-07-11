# Research Round 2026-07-10d — does MORE go further? (breadth, diversity, non-human grammars)

**Status:** LIVE — updated as each experiment lands. 2/6 complete.
**Origin:** A user hypothesis, made falsifiable: *"maybe it thinks the same way as
humans — maybe if we pump more out at once it will go further."* This round tests
it rigorously rather than arguing from the H50 prior.

**The hypothesis has a refuted half and an untested half.**
- **Refuted (H50, round 1):** more *depth* on one closure buys nothing — a hard
  372-eval plateau, closure exhaustion. "Pump more of the same" is answered: no.
- **Untested (this round):** two sharper readings H50 never touched —
  1. *"pump more out at once"* = **breadth** of many *diverse* proposers in
     parallel, not depth on one. A pool spanning more closures may reach
     out-of-closure targets a single proposer cannot.
  2. *"thinks like humans"* = the ceiling may be that every primitive **family**
     is human-conceived (XOR/mod/Walsh/comparison). **Machine-invented, non-human
     atom grammars** might escape where human families can't.

The spine (D1, D2, D6) answers "will pumping more go further" as a *curve and a
predictor*, not a vibe. D3 and D5 test the "thinks like humans" reading. D4 pumps
it at a real open target (the only place new-to-humanity can happen).

Constraints unchanged: new files only, standalone `zig build-exe`, ≤2 threads /
≤15 min runs, independent verification per claim, "more doesn't help" is a valid
and important finding, equal-TOTAL-budget comparisons (the crux), main session
commits centrally, doc + commit + TOC per landing.

---

## Verdict table

| # | Experiment | Question | Status | Headline | Doc |
|---|-----------|----------|--------|----------|-----|
| 1 | Breadth vs depth | At equal total budget, does breadth of N diverse proposers reach targets one deep proposer (H50 plateau) can't? | pending | — | `docs/research/breadth_vs_depth.md` |
| 2 | Breadth scaling law | The H50 counterpart: does out-of-closure reach grow with N diverse proposers, or plateau? Diverse-vs-identical control. | pending | — | `docs/research/breadth_scaling.md` |
| 3 | Non-human grammar | Do bulk machine-invented (non-human) atoms escape a proven family-level wall that human families can't? | **DONE** | **Refuted both ways:** the engine ALREADY thinks non-human (92.4% of forged atoms genuinely non-human) — so "thinks like humans" is false — but that buys NO reach: bulk machine grammar scores ~chance (0.519), *worse* than raw search (0.713) and human-op search (0.691) at equal budget. **The ceiling is AIM, not grammar.** | `wcore/docs/research/nonhuman_grammar.md` |
| 4 | Parallel swarm on LABS | Does a massively-parallel diverse strategy pool crack an open LABS even-N gap a single method can't? (round-b rematch) | **DONE** | **Diversity beats concentration 9/12 at equal budget** (reverses round-b's blanket claim) — but the edge is *restart-diversification of one arm* (the best arm led all 48/48 pool runs), not diverse strategies each winning; vs best prior number only 2/12 improved, 7/12 regressed. **No record.** Verifier clean (12/12, 2/2 lies caught). | `boundary_crossing/docs/research/labs_swarm.md` |
| 5 | Auto-discover curriculum | Can bulk parallel proposal DISCOVER the conjunction-wall decomposition autonomously (no hand-designed stones)? | pending | — | `wcore/docs/research/auto_curriculum.md` |
| 6 | Diversity predictor | Is out-of-closure reach predicted by generator DIVERSITY (spans-of-closures), not eval count or raw N? (with R²) | pending | — | `docs/research/diversity_predictor.md` |

---

## Design notes

- **The crux is equal-TOTAL-budget.** "Pump more at once" only means something if
  breadth is compared to depth at the *same* total compute — otherwise it is
  trivially "more compute helps." D1/D2/D6 all hold total budget fixed and vary
  how it is *distributed* (depth vs breadth) and how *diverse* the pool is.
- **The N-identical control is what makes it science.** If N *identical*
  proposers plateau like H50 but N *diverse* proposers keep paying, the escape
  resource is diversity-of-generators, not quantity — the precise validation of
  "pump more DIFFERENT" and refutation of "pump more of the same." D2 and D6 both
  run it.
- **"Parallel" means N independent proposers sharing a budget, not N OS
  threads** — the ≤2-thread rule stands; parallelism is simulated in-process.
- D3 and D5 test whether quantity can *substitute* for the two things the prior
  rounds found to be the real levers: a genuinely new primitive family (D3) and
  an auto-discovered decomposition (D5). If bulk parallel proposal finds them,
  the user is right in a deep way; if not, we've sharply bounded what "more" buys.

*(Verdicts and synthesis added as agents land.)*
