# Research Round 2026-07-10c — crossing the conjunction wall

**Status:** COMPLETE — all 6 experiments landed 2026-07-10.
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
| 1 | Conjunction wall (wcore) | Do stepping-stone curricula or mechanism-level descriptors lift the distinct-count climb past the 0.862 plateau to the 0.95 bar? | **DONE** | **CROSSED by the curriculum:** frontier reach 0 → 6/9 on both seeds (stones promoted → target composable via `distinct = noveltyflag→g_add`), 0 depth-4 leaks. Mechanism descriptors fail (0/9). The wall is a gradient absence bypassed at the promotion boundary — not climbable under any of 4 lenses. | `wcore/docs/research/conjunction_wall.md` |
| 2 | Evidence lenses (battery-C) | Do second-order / conditional / order-statistic lenses beat the (1/3)^k signal decay — reaching degree-5 C11 and family-miss C09? Baseline 8/33. | **DONE** | **Battery-C SATURATED: 33/33, cheaper than v1** (12,630 vs 13,152 evals). The (1/3)^k wall was an estimator artifact — the GF(2) joint solve is exact and k-independent; C09 fell to pairwise-order evidence primitives + algebraic identification. 30/30 derivation chains byte-exact; asterisk: exactness needs noiseless labels (LPN). | `docs/research/tier8_evidence_lenses.md` |
| 3 | greedyFit z-scoring fix | Fix the raw-vs-z-scored mismatch; do the 5 leaked battery-D candidates reclassify, and do prior verdicts (11/11 battery, gate v5) survive? | **DONE** | Fit and eval now share train-stat scaling. **All 5 leaks flip → DECISIVE (band 3→8); ablation effect 1/9-vs-9/9 → 0/24-vs-22/24; B3 was silently leaking in every prior strict-v3 run** (honest ARM-OFF battery-B = 29/33). Stock production line-identical; gate v5 survives and strengthens (60/60 + 9/9). | `docs/research/tier8_taxfix.md` |
| 4 | Matcher falsification (wcore) | Can the 0.95 / 8×28 statistical matcher be made to lie (false-equal, false-different, seed-flips)? What protocol fixes it? | **DONE** | **CRACKED: 4.2% of production "reducible" verdicts are false-equals** (8/189, all witnessed); the horizon bomb scores 1.000 while truly matching 10.9%. Corrected protocol (exact match, 64×256, 2 seeds) → 0 false-equals AND cheaper (13ms vs 70ms). **All 20/20 promotion identities survive.** | `wcore/docs/research/matcher_falsification.md` |
| 5 | Assembled engine | Do revision + aimed proposal + v5-ladder verdict + export-filter tax cohere in ONE pass across batteries B/C/D, or interfere? | **DONE** | **COHERES: every battery's best number simultaneously** (B 33/33, C 8/33, D 9/9) at revision-only's eval budget; zero decision-level interference across 300 rows; attribution exactly additive; D11 overlap dedupes correctly via the v5 verdict. Recommended as production default. | `docs/research/tier8_assembled.md` |
| 6 | D08/C09 reachability gap | Is the gap family-level (proven)? Does the minimal comparison-aggregate family close it, at what cost signature? | **DONE** | **Two gaps, not one:** C09 proven family-level (Bayes ceilings of every family at chance; inversion basis = 1.000); D08 is a *selection bug* (exact spectral member exists at gridpoint 100 — discoverSpectral picks by DFT power, not accuracy). +CMP/+MENUACC double dissociation: **+11 flips, 0 regressions in 99 cells**, B11's metadata-gated solve now blind. | `docs/research/tier8_reach_gap.md` |

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

---

## Completed-experiment detail

### 1. Conjunction wall (the headline — CROSSED)
- **Probe (the wall is real under every lens):** greedy climb to distinct-count
  plateaus at 0.875 / 0.839 vs the 0.95 bar — reproducing round b's 0.862 —
  and none of three new lenses beats it (curriculum's final stone climbed
  directly 0.875/0.835; mechanism-pure 0.446/0.732; mechanism-blend
  0.772/0.750). A genuine gradient absence, not a weak-lens artifact.
- **Forge control (aimed_promote on the wall family, hashtbl/union excluded):**
  `f_reach` = 0/9 on both seeds. The wall holds — a *harder* control than
  round b's (aimed only at the ungradient family).
- **Forge curriculum (lever A) CROSSES it: f_reach 0 → 6/9 on both seeds.** The
  jump lands at the exact round the `noveltyflag` stone is solved and promoted
  (`stone_solved` → `compose_advance`): `distinct = noveltyflag→g_add` becomes
  a depth-2 composition and 4 of its 6 hidden compositions follow at depth ≤3.
  Since F holds only 2 already-climbable members, ≥4 of the 6 are genuine
  wall-family targets. Promotions clean: 0 depth-4 retro-audit rejects (control
  had 2, 1).
- **Forge mechanism descriptors (lever B):** f_reach = 0/9 both seeds —
  structural credit M at the gate does not identify a promotable stone.
- **Selftest all-PASS:** stone oracles equal brute references, the payoff
  identity holds, S1/S2 are behavioural complements (agreement 0.000 at
  edit-distance 1 — the designed trap), distinct uniquely M = 1.000.
- **Verdict:** the wall is a *gradient* absence, not a *reachability* absence —
  bypassed at the promotion boundary by climbing to a sub-conjunction that has
  gradient, promoting it, and composing. A Closure-Principle escape at the
  curriculum level where the generator is a *discovered intermediate
  abstraction*, not a new primitive. Honest bound: the stones were
  hand-designed from the known mechanism; auto-discovering the decomposition is
  the next frontier.

### 3. greedyFit z-scoring fix (instrument repair with full migration accounting)
- **The bug:** `greedyFit` fit logit weights on raw remainder columns but
  evaluated against z-scored test columns — systematically *understating*
  reconstructibility for multi-valued columns (binary {0,1} remainders
  happened to survive the mismatch). **The fix:** standardize both splits
  with train-set statistics before fitting.
- **Discipline:** the pre-fix control binary reproduced all old results
  byte-identically before the fix was applied, so the fix is the only
  variable. Committed CSVs from prior rounds restored byte-identical so
  existing docs keep matching their data; migrations live in the new files.
- **Regression gates:** (a) stock `--strict-tax` production run
  line-identical (11/11, 372 evals, library 19); (c) gate v5 survives and
  *strengthens* — discrimination pool grows 57→69 and partitions exactly:
  60/60 true remixes blocked, 9/9 certified escapes admitted (3
  newly-exposed B3 escapes recognized engine-novel with zero retuning);
  full-basis variants got worse (22/22 would-block), reinforcing
  never-bind-in-loop.
- **Verdict migrations (the headline):**
  - All five battery-D leaks (D02/D03/D04/D09/D10) flip TOO_EASY →
    DECISIVE: **decisive band 3 → 8 of 11**.
  - **B3 (sum%7) was silently leaking in every prior strict-v3 run** —
    honest ARM-OFF battery-B is 29/33, and B3 is a clean 3/3-seed decisive
    member (a pre-existing production claim corrected by the fix).
  - D07's borderline seed was the artifact: replication now 3/3.
  - Updated two-arm effect on the 8-target decisive set: **ARM-OFF 0/24 vs
    ARM-ON 22/24** (26 ON-only existence proofs, 0 reverse; OFF 4499 evals
    vs ON 2072). New borderline: D09 (1/3 seeds; other two are reachability,
    not tax).
  - Not moved: C08, battery-C (binary-class targets unaffected), B10's 1/3
    marginal, all gate-v5 admission/no-harm keys.

### 2. Evidence lenses (the (1/3)^k wall falls)
- Signal formulas derived first, verified at the true candidate: L2 pairwise
  (1/3)^(k−2) (measured 0.1064 vs predicted 0.1111 at deg-4); L3 Gibbs
  (1/3)^(k−u) per accepted step with a ~37σ held-out endpoint check; LW
  mod2-Walsh coefficient 1.0 at the target; **LG GF(2) joint solve (28
  comparison bits + 8 lb + 8 tb + 1) — exact and k-independent** (noiseless
  linear system, rank 45/45 → unique).
- Hit rates: deg-4 1.3% (L0) → 19.6% (L1) → 100% (L2+). C11 (deg-5,
  baseline 0): Gibbs 85%, LW/LG 100%. **C09: only LG, 60/60** — the family
  miss was lens-fixable, but only by adding pairwise-order *evidence
  primitives* + joint algebraic identification; no correlation lens over
  the same dictionary works (all ≈0).
- Pipeline at 3 seeds: baselines reproduced exactly (3/33; 8/33 with
  identical flip identities and eval counts); **aimed-v2 33/33 at 12,630
  evals — cheaper than v1**. 30/30 derivation chains byte-exact, all 30
  export novel (tax corr 0.025–0.083), zero false accepts, 180/180
  out-of-family controls rejected.
- **Honest asterisks:** LG's exactness relies on noiseless labels — under
  label noise this becomes LPN and the wall re-opens; and battery-C is now
  *saturated* — it no longer discriminates and needs a successor battery.

### 6. Reach gap (two gaps, not one)
- **C09 (inversion parity): family-level, PROVEN** — not by search failure
  but by information-basis Bayes ceilings: the per-bin majority vote (an
  upper bound on *every* function of each family's input statistic) sits at
  chance for all six families (0.494–0.517); the inversion basis alone is
  1.000. The minimal family is the comparison-pair aggregate — and it needs
  no mask search: the full 28-comparator set is *the* canonical order
  statistic (proper subsets score 0.505–0.519, full set 1.000).
- **D08 (count3%4): NOT family-level — a member-selection bug.** The
  spectral family already contains an exact certifiable member
  (cos(ω·count3), ω≈π/2 — literally gridpoint 100 of the existing 200-freq
  grid). `discoverSpectral` selects by count-weighted DFT *power*, which the
  Binomial(8,½) mass concentrates on the parity harmonic (0.79 acc).
  Selection statistic ≠ certification statistic. The same bug makes D09
  seed-fragile.
- **Double dissociation:** +CMP alone solves C09 not D08; +MENUACC
  (accuracy-scored selection over the same grid) alone solves D08 not C09.
  Full batteries, 3 seeds, extended vs replica ladder: B 30/33→33/33 (B11's
  metadata-gated solve now falls blind), C 3/33→6/33, D 28/33→33/33 —
  **+11 flips, zero regressions in 99 cells**, mechanisms 100% replicated.
- Cost signature matches round-1's out-of-closure shape exactly: unbounded
  without the generator; 397–1,689 evals with it. Recommendation: MENUACC
  is a bug-fix (certify the accuracy-argmax), CMP earns a production seat.

### 4. Matcher falsification (the crack, and the fix that costs less)
- **The matcher lies structurally in the false-equal direction.** All 9
  constructed adversaries certify "reducible" (7 at 100% of 500 stream
  seeds), each with an exact disagreement witness. The **horizon bomb** is
  the cleanest: production agreement 1.000, true agreement 10.9% — a
  28-symbol stream cannot see past position 28 at any threshold or seed.
  Beyond constructions: 2 false-equals in 5,803 random production-passing
  pairs, and **8/189 (4.2%) of the real a1a6 census's "reducible" verdicts
  are false-equals** (worst true agreement 0.32).
- **What is NOT fragile:** false-different is structurally impossible
  (0/90,000); production verdict seed-flips 0/2,000 — the 0.008 kill-test
  margin was an aggregate-search property, not per-verdict fragility; the
  inv8 depth-flip is real (exact on 2×16,384 symbols); kill-tests
  non-vacuous at exact depth ≤8.
- **Corrected protocol, ROC-backed:** exact match (threshold 1.0), 64
  streams × 256 symbols, confirmed on 2 independent seeds, 32-symbol
  early-exit. False-equal 0/2,489 labeled pairs, true-equal 1.0000 — and
  **cheaper than production** (13ms vs 70ms per depth-4 census; first-
  mismatch early exit beats the bigger sample). Honest residual: sub-2e-4
  deviators survive any finite-sample protocol.
- **Verdict migrations: none that matter.** 14 intermediate census verdicts
  migrate reducible→irreducible, but promotion identity is unchanged 20/20
  (first-irreducible-in-length-order is insensitive to corrections after
  its index). Not attacked: the coevo-side 12×32 matcher (same mechanics
  likely apply — flagged).

### 5. Assembled engine (the coherence test)
- Four arms × 3 seeds with all baselines re-measured in-harness against the
  taxfix: frozen (B 29/33, C 0/33, D 0/9), revision-only (33/33, 3/33,
  9/9), aimed-without-revision (29/33, 5/33 final, 3/9), **assembled
  (33/33, 8/33, 9/9)** — every documented best simultaneously, at
  revision-only's eval budget (2072), same 5 aimed flips with
  byte-identical masks.
- **Interference: zero at the decision level** — all solved/route/tax/
  basis/trigger columns identical between corresponding arms across 300
  rows. One bounded finding: unsolved targets' terminal coverage drifts
  ±0.01–0.02 downstream of genuine divergence points via a *pre-existing*
  shared-scratch channel (also present between yesterday's own ablation
  arms); never crosses a decision boundary; cleanliness fix queued.
- **Attribution exactly additive:** revision carries the battery-B rescues
  + C08 + all of battery-D; aimed carries the XOR family. The overlap case
  (D11) dedupes correctly — and when aimed solves it without revision, the
  v5 verdict rightly labels that composite engine-expressible remix.
  Revision also cuts the aimed stage's cost 35% by relieving its queue.
- Independently confirms the taxfix migrations (frozen B 29/33, D 0/9,
  decisive band 8/11) from a separately-written harness — two agents, same
  numbers, no shared code path for the comparison.
- **Recommendation adopted: assembled is the production default** —
  revision ON, aimed as a post-ladder stage on stuck targets only,
  v5-ladder at recording/export only. Next round runs on the widened
  8-target decisive band.

## Synthesis (updated as results land)

1. **The Tier 8 effect size was UNDERSTATED by the instrument bug, not
   inflated:** fixing the tax made the frozen arm *weaker* (0/24, and
   battery-B honestly 29/33) and the revision arm's margin *larger*
   (22/24). Skeptic-proofing an instrument strengthened the headline claim
   — the best possible direction for a correction to land.
2. **Third greedyFit-adjacent defect in three days** (stack overflow, scale
   mismatch, and round-1's tax-vacuity design flaw). The pattern says:
   load-bearing instruments need dedicated red-team rounds *before* their
   numbers headline — the matcher attack (exp 4, running) is exactly that
   for wcore's certifier.
3. **Both round-b walls fell in one round, in opposite ways:** the (1/3)^k
   evidence wall was an *estimator* artifact — a better identification
   algorithm (exact GF(2) joint solve) dissolves it with no new primitives
   for the XOR class; C09's wall was *real* (Bayes-ceiling proof) and fell
   only to a new primitive family (comparison aggregates). Walls must be
   diagnosed before they are attacked: exp 6's Bayes-ceiling method is the
   diagnostic, and it also caught D08's "wall" being a selection bug.
   Corollary of the same class: B11's solve needed target metadata in
   production but falls blind with the right family — metadata gates are
   closet reachability gaps.
4. **The batteries are dying of success:** battery-C is saturated (33/33)
   and battery-D is 33/33 under the extended ladder. The program needs a
   successor battery designed against the *new* frontier: label noise (the
   LPN asterisk), deeper compositions, and targets outside both the XOR
   and order-statistic families.
5. **The instrument-trust round paid for itself twice over:** both audited
   instruments were broken (greedyFit scale mismatch; matcher horizon +
   threshold lies), both fixes make the system STRONGER not weaker (Tier 8
   effect 0/24-vs-22/24; exact matching cheaper at 13ms), and in both cases
   every headline verdict survived — the false-equal class was hiding in
   intermediate census rows, not in promotions. The repo's claim-hygiene
   (promotion rules insensitive to census corrections; byte-identical
   pre-fix controls) is what made the corrections cheap. Next instrument in
   line: the coevo-side 12×32 matcher.
6. **All three round-b walls are now resolved, and each fell to a different
   tool:** the (1/3)^k evidence wall was an estimator artifact (exact GF(2)
   identification, exp 2); C09's family wall was real and fell to a new
   primitive family (comparison aggregates, exp 6); the distinct-count
   conjunction wall was a gradient absence and fell to a *curriculum* —
   climb a gradient-bearing sub-conjunction, promote it, compose (exp 1).
   Not one of the three yielded to "more search" or "more compute"; each
   needed a structurally different move, and the diagnostic that told them
   apart (Bayes ceilings, signal-formula derivation, the gradient probe) was
   the actual load-bearing work. This is the round-1 lesson made operational:
   diagnose the wall before attacking it.

---

## Round verdict (final)

Six experiments, six completions. The conjunction wall — round b's named
successor problem — is crossed: a stepping-stone curriculum lifts frontier
reach 0 → 6/9 by discovering and promoting an intermediate abstraction, the
Closure-Principle escape at the curriculum level. Around it: the settled
architecture is proven to cohere in one engine (assembled: every battery's
best simultaneously, zero interference, now the production default); two more
walls fell (evidence lenses saturate battery-C 33/33 by exact GF(2)
identification; comparison aggregates close the C09/D08 reach gap, +11 flips /
0 regressions); and both load-bearing instruments were red-teamed and repaired
with every headline surviving (greedyFit scale fix *strengthened* the Tier 8
effect to 0/24-vs-22/24 and exposed B3's silent leak; the 0.95 matcher was
falsified — 4.2% false-equals — and replaced by an exact protocol that is both
correct and cheaper). Named successor problems: auto-discovering curriculum
decompositions (the conjunction-wall bound), a successor battery beyond XOR +
order-statistic families and into label noise (the LPN asterisk; C and D are
saturated), the coevo-side 12×32 matcher audit, and the shared-scratch
coverage-drift cleanliness fix.

*(Remaining verdicts added as agents land.)*
