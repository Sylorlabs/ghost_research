# Research Round 2026-07-10d — does MORE go further? (breadth, diversity, non-human grammars)

**Status:** LIVE — updated as each experiment lands. 4/6 complete.
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
| 2 | Breadth scaling law | The H50 counterpart: does out-of-closure reach grow with N diverse proposers, or plateau? Diverse-vs-identical control. | **DONE** | **Breadth plateaus like depth — diversity is NOT the lever.** Diverse reach flat at 1 across N=1→32; identical copies reached 2 at N=32. The wall is *representability* (brute-verified: only 4/15 cells representable; C09 provably at chance), not budget. Breadth beats single-shot depth in the needle regime, but neither crosses the closure boundary. | `docs/research/breadth_scaling.md` |
| 3 | Non-human grammar | Do bulk machine-invented (non-human) atoms escape a proven family-level wall that human families can't? | **DONE** | **Refuted both ways:** the engine ALREADY thinks non-human (92.4% of forged atoms genuinely non-human) — so "thinks like humans" is false — but that buys NO reach: bulk machine grammar scores ~chance (0.519), *worse* than raw search (0.713) and human-op search (0.691) at equal budget. **The ceiling is AIM, not grammar.** | `wcore/docs/research/nonhuman_grammar.md` |
| 4 | Parallel swarm on LABS | Does a massively-parallel diverse strategy pool crack an open LABS even-N gap a single method can't? (round-b rematch) | **DONE** | **Diversity beats concentration 9/12 at equal budget** (reverses round-b's blanket claim) — but the edge is *restart-diversification of one arm* (the best arm led all 48/48 pool runs), not diverse strategies each winning; vs best prior number only 2/12 improved, 7/12 regressed. **No record.** Verifier clean (12/12, 2/2 lies caught). | `boundary_crossing/docs/research/labs_swarm.md` |
| 5 | Auto-discover curriculum | Can bulk parallel proposal DISCOVER the conjunction-wall decomposition autonomously (no hand-designed stones)? | pending | — | `wcore/docs/research/auto_curriculum.md` |
| 6 | Diversity predictor | Is out-of-closure reach predicted by generator DIVERSITY (spans-of-closures), not eval count or raw N? (with R²) | **DONE** | **Yes, conditionally:** diversity D predicts reach (R²≈0.4, partial 0.607) — dominant over count (partial −0.058) and budget (0.092); every D=1 row = 0 reach. BUT only when D spans the target's closure (falsification: wrong-direction diversity buys nothing). Resolves with #2 (see synthesis). | `docs/research/diversity_predictor.md` |

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

---

## Completed-experiment detail

### 2. Breadth scaling law — breadth plateaus like depth
- Breadth curve (union reach over 15 out-of-closure cells, diverse pool):
  **flat at 1 across N = 1 → 32**. The N-identical control reached **2** at
  N=32 vs the diverse pool's 1 — on this target set diversity did *not* help.
- The plateau is a **representability** boundary, brute-verified over 255
  masks × 6 lenses: only 4/15 cells are exactly representable; C09
  (inversion-parity) tops out at 0.5343 ≈ chance and returns exactly 0 in
  every arm including the exhaustive attempt. No budget on either axis crosses
  it.
- Breadth *does* beat single-shot depth in the needle regime (N=8–16 reach 1
  where a 475-eval exhaustive single-selection reaches 0 — independent
  re-selection beats one chance-level draw), but ~3 orders worse than
  in-closure escalation. **Caveat:** total reach is tiny (1–3 instances), so
  read as "diversity didn't help here," not a strong "quantity wins" law.
- *Why identical won here:* the reachable targets are all pure XOR/parity —
  one lens wins, so N identical copies of that lens get more draws at it than
  a pool that wastes slots on wrong mechanisms. **This is the key to
  reconciling with D6 (below).**

### 3. Non-human grammar — the engine already thinks non-human, but it doesn't help
- 92.4% (1109/1200) of forged atoms are **genuinely non-human** (joint
  criterion: behaviorally outside every depth-≤3 human-family composition AND
  using load-bearing opcodes outside the 6-of-19 human vocabulary). "It only
  re-derives human families under new names" is empirically false.
- But on a solvable out-of-family target (descent-parity; hand-written alien
  control = 1.000), the machine-atom pool reaches only **0.519 ≈ chance** at
  equal budget — *worse* than raw search (0.713) and human-op search (0.691).
  No arm crosses 0.95.
- **Verdict: the ceiling is AIM, not grammar.** Unaimed non-human novelty
  scatters in random directions; bulk composition doesn't converge. Grammar
  is not the human-imposed limit the hypothesis supposed.

### 4. LABS swarm — diversity beats concentration, but as restart-diversification
- At equal total budget (50M evals), diverse pools won **9/12** lengths vs a
  single concentrated arm — reversing round b's blanket "concentrate beats
  split." But the best single arm led **all 48/48** pool runs (avg 3.25–3.5/9
  arms contributed): the edge is *restart-diversification of one good
  strategy*, not diverse strategies each winning.
- Vs the best number either prior round already had: 2/12 improved, 3/12 tied,
  7/12 regressed. **No record.** N=44 stays closed (122 = best-known).
  Verifier clean (12/12, 2/2 planted lies caught).

### 6. Diversity predictor — diversity IS the resource, when it spans the target
- Diversity **D** predicts out-of-closure reach: `corr(reach,D)=0.636`
  (R²=0.405), partial (controlling N and evals) **0.607** — dominant over
  count (partial −0.058, collapses to zero) and budget (0.092). Every
  D=1 ("N identical") row across the 285-config sweep is **exactly 0 reach**,
  the count-axis analogue of H50's compute plateau.
- **Conditional, and falsified where it should be:** (1) a target outside
  every family span is never solved at max D/budget — wrong-direction
  diversity buys nothing; (2) a narrow-margin conjunction solved 13.5% vs
  93.4% for a stronger margin — right-direction diversity still needs adequate
  per-family selection signal.
- Rigor: two bugs found and fixed en route — test-split leakage (initially
  made D look *negatively* correlated) and an unequal solo-baseline combo
  budget.

## Synthesis — reconciling #2 and #6 (the round's real finding)

**D2 and D6 look opposite — "diversity is not the lever" vs "diversity predicts
reach R²≈0.4" — but they are the same law measured on two target sets, and
together they are sharper than either alone:**

> **Diversity is the escape resource exactly when — and only when — the pool's
> diversity spans the target's closure. Diversity in the wrong directions is
> wasted, and worse than concentrating on the right mechanism.**

- In **D2**, every reachable target lived in *one* closure (pure XOR/parity).
  The "right" proposer is a single mechanism, so N *identical* copies of it get
  more independent draws than a diverse pool that spends slots on wrong
  mechanisms → identical won, diversity looked useless.
- In **D6**, targets were constructed to span *multiple* families. A pool must
  be diverse to span them; a D=1 pool can never represent a target its one
  mechanism can't → every D=1 row is 0, and D dominates the regression.
- D6's falsification case 1 (wrong-direction diversity buys nothing) *is* D2's
  situation stated from the other side. No contradiction — one law.

This is the precise, measured form of your hypothesis, and it splits the verdict:
- **"Pump more of the same"** (N identical): refuted — flat plateau, both axes
  (H50 depth, D2/D6 count).
- **"Pump more DIFFERENT"** (diverse pool): validated **conditionally** — it
  pays iff the diversity spans the target's closure, and even then needs enough
  per-family selection margin. It is not a free "more goes further"; it is
  "diversity aimed across the right closures goes further."
- **Non-human grammar (D3)** and the LABS swarm (D4) sharpen the boundary: the
  engine is *already* non-human (92.4%) and diversity *does* help modestly on
  open targets — but neither crosses a **representability** boundary, and
  unaimed richness underperforms aimed search. The ceiling is **aim ×
  representability**, not quantity and not human-vs-non-human grammar.

*(Experiments 1 and 5 pending; final verdict on completion.)*
