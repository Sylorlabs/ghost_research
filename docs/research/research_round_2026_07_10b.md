# Research Round 2026-07-10b — aiming the escapes

**Status:** COMPLETE — all 6 experiments landed 2026-07-10.
**Predecessor:** `research_round_2026_07_10.md` (8/8 complete). Its converged
finding: *the loop's binding resource is aimed out-of-closure generators — not
compute, not more promotion rounds, not stricter gates.* Escapes are cheap when
aimed (A10: one algebra change, 0.508→0.976), worthless when unaimed (A1–A6:
ten rounds bought one behaviour), compute past closure exhaustion is
unspendable (H50: 372-eval hard ceiling), and framework revision is the proven
escape-admission mechanism (Tier 8 ablation, 3/3 seeds) whose gate is currently
vacuous post-revision.

**This round builds and tests the aiming mechanism**, re-audits the one
foundation with a known depth-artifact risk, and sharpens both external
campaigns' weak spots. Same constraints as round 1: new files only, standalone
`zig build-exe`, ≤2 threads / ≤15 min runs, independent verification per claim,
negatives documented as findings, main session commits centrally.

---

## Verdict table

| # | Experiment | Question | Status | Headline | Doc |
|---|-----------|----------|--------|----------|-----|
| 1 | Aimed forge (wcore) | Does residual pressure toward a named frontier beat pure novelty at equal budget? Baseline: unaimed = 3/18→4/18, structured family never flips. | **DONE** | Aiming the *search* fails completely (F 0/9 in both aimed-fitness arms); aiming the *promotion gate* (pick highest-residual certified candidate) produced the arc's **first structured-family solve** (hashtbl + union, 1/2 seeds). distinct-count is a measured **conjunction wall** (climb plateau 0.862 < 0.95 bar). Aim info belongs at the gate, not the inner loop. | `wcore/docs/research/aimed_forge.md` |
| 2 | Aimed proposer (battery-C wall) | Do near-miss witnesses + residual-guided feature proposal move the 10/11 battery-C wall? Baselines: 0/33 frozen, 3/33 revision. | **DONE** | **Wall moves: 3/33 → 8/33.** Every flip's evidence-mined mask is byte-identical to ground truth; all 5 export as novel. Honest limit: the correlation signal is (1/3)^k — aiming is probabilistic (~17%/attempt deg-4, 0 at deg-5); C09's family is a structural miss. | `docs/research/tier8_aimed_proposer.md` |
| 3 | Gate v5 discrimination | Is there a gate that admits certified escapes (C08 must still pass) AND blocks planted remix (v4 passes 100%)? | **DONE** | **v5-ladder breaks the trade-off**: 3/3 C08 admission, 51/51 true remixes blocked, 6/6 wrongly-blocked escapes admitted. Full-basis variants fail *irreducibly* (C08's test_acc = 1.0000 exactly equals remix — no ε separates). Adopt at verdict layer; never bind in-loop. | `docs/research/tier8_gate_v5.md` |
| 4 | Claim-C depth attack (wcore) | Do wcore's "irreducible" verdicts survive +1/+2/+3 certifier depth, or are they resource artifacts (the I53 attack, applied to wcore)? | **DONE** | Known 5% leak confirmed and sharpened (1/20 flips at +1 depth, flip distribution entirely front-loaded, 0 flips at +2..+5); kill-test survives a *completed* depth-8 enumeration — but by only **0.008 margin** vs the 0.95 statistical matcher, which is now the thinner axis. Corrected wording adopted; +1-depth promotion gate costs ~1s/candidate. | `wcore/docs/research/claimc_depth_attack.md` |
| 5 | LABS even-N | Can memetic / pair-flip / structural moves close the 12 even-N + {61,63,64} gaps skew-symmetry can't touch? | **DONE** | **2/12 fully closed (N=44, 50 hit best-known), 3 partial, 4 regressed** (budget split across 8 arms < one concentrated run — real lesson). Key negative: **no even-N analogue of skew-symmetry exists** among mirror-pair hypotheses (isolation test: plain 6.86 vs mirror 4.24). Verifier 12/12 + 63/63. | `boundary_crossing/docs/research/labs_even_n.md` |
| 6 | Decisive battery-D | Build ~10 targets in the ladder-reachable-but-v3-blockable band; turn the 1-target Tier 8 existence proof into an effect size. | **DONE** | **3/11 candidates DECISIVE** (D01 sum%2, D07 count3%3, D11 subset-parity). Ablation on the decisive subset: **ARM-OFF 1/9 vs ARM-ON 9/9**, zero reversals, battery B preserved at fewer evals. Bonus: found a greedyFit scale-mismatch bug (raw-vs-z-scored columns) and a ladder reachability gap (D08). | `docs/research/tier8_battery_d.md` |

---

## Design notes

- Experiments 1–3 are the round's spine: the aiming mechanism at three layers
  (forge fitness, feature proposal, promotion gate). Experiment 6 supplies the
  instrument (a battery that can measure aimed escapes at all). Experiment 4 is
  defensive: the open-atom program rests on the Claim-C certifier, which
  carries exactly the resource-bound risk I53 exposed. Experiment 5 chases the
  itemized record gap from round 1.
- Held-out contamination guard (exp 1): aiming targets (F) and transfer-eval
  targets (E) are disjoint by design; aiming at a target removes it from any
  generalisation claim.
- The `greedyFit` stack fix (commit 67fdd13) means round-2 harnesses need no
  giant-stack workarounds.

---

## Completed-experiment detail

### 6. Decisive battery-D (the instrument)
- Mechanism understood before construction: C08 was decisive because the
  ladder's exhaustive Walsh search finds `S=0xFF` (an exact predictor of
  `parity(count(cells≥3))`) while the v3 tax's mod-synth bank independently
  contains `mod(count3,2)` — the same function under a different name, so the
  certified escape is blocked as remix. Battery-D generalizes that coincidence
  along `sum(g)%k` (k∈{2,3,5,7,11,13}), `count3%k` (k∈{3..6}), and one
  subset-Walsh composite — 11 candidates.
- **Band classification: 3/11 DECISIVE** — D01 (sum%2) 3/3 seeds, D07
  (count3%3) 2/3 seeds (one genuine borderline), D11 (subset-parity of cells
  0–3) 3/3 seeds via an *unpredicted* route (monomial-forge sign-parity, not
  Walsh). 5 leaked TOO_EASY through a real instrument bug (below); 2 TOO_EASY
  for the predicted reason (mod-synth k-cap 8, skewed base rates); 1 TOO_HARD
  (D08 — the ladder never certifies an escape at all: a reachability gap,
  distinct from the tax-gate effect).
- **Effect size (the round-1 gap closed):** two-arm ablation on the decisive
  subset, 3 targets × 3 seeds: **ARM-OFF 1/9, ARM-ON 9/9**, zero OFF-only
  reversals, battery B preserved (32/33 vs 33/33), ARM-ON again cheaper
  (2072 vs 4412 evals). Framework revision's benefit is now a measured effect
  on a purpose-built battery, not a single-witness existence proof.
- **Instrument bug found (fix queued):** `equivalence_tax.greedyFit` fits
  weights on raw remainder columns but evaluates against z-scored test
  columns — the scale mismatch still separates binary {0,1} remainders but
  not always 3+-valued ones, which is what let D02/D03/D04/D09/D10 leak
  TOO_EASY. Second greedyFit defect found by this program in two days.

### 1. Aimed forge (the spine, layer 1)
- Four arms at identical budget (pop 90 × gens 45 × 10 rounds × 2 seeds);
  the unaimed control re-run reproduced A1–A6's numbers *exactly*. F/E split:
  F = the 9 distinct-count-centric targets the unaimed forge never reached;
  E = 9 rmw-centric targets + 3 decoy sentinels, never aimed at.
- **Aiming the search fails completely:** both aimed-fitness arms (flat 0.5
  blend, annealed 0→0.85) scored F 0/9 on both seeds — behavioral-proximity
  pressure in the forge's fitness cannot cross the wall at equal budget. It
  did cut the SELF-match pathology (75% → 14–38%), so the pressure *is*
  changing the distribution, just not usefully.
- **Aiming the promotion gate works (existence proof):** the fourth arm
  (aimed_promote — promote the highest-residual certified-irreducible
  candidate instead of the shortest) produced the arc's **first
  structured-family solves ever**: hashtbl + union at round 4 on seed
  0x5EED2 (1/2 seeds). The winning atom holds at every retro-audit depth.
- **Diagnosis probe separates the two failure modes:** hashtbl/union's
  residual landscape is fully climbable (1.000 reachable); distinct-count is
  a measured **conjunction wall** — greedy climb plateaus at 0.862 against
  the 0.95 certification bar (random max 0.723). 7/9 of F is behind that
  wall, which no amount of proximity pressure crosses. Named next lever:
  mechanism-level descriptors / stepping-stone curricula, with the measured
  target "lift climbable residual 0.862 → ≥0.95".
- Retro-audit across all 80 promoted atoms: 4/80 leaks (5% — same rate as
  A1–A6, whose leak reproduced exactly). Cost signature of residual-max
  promotion: longer atoms (mean 10.5 vs 4.1 instructions), 2/10 leaks on one
  seed — the gate trades brevity for aim.

### 2. Aimed proposer at the battery-C wall (the spine, layer 2)
- Baselines reproduced exactly in-harness: 0/33 frozen, 3/33 revision.
  **Aimed proposer: 8/33** — five flips beyond revision (C02, C04, C05,
  C06×2 seeds), 6m56s single-threaded, ~438 evals/target for the aimed step.
- Mechanism: mine near-miss evidence (the monomial sweep's own argmax + a
  256-Walsh sweep), scan 6 generic per-cell lenses over the evidence mask,
  greedily grow/shrink, certify through the real coverage/R² bar; tax as a
  post-hoc export filter only (round 1's settled design).
- **Derivation honesty (the required check):** in every flip the
  evidence-mined mask is byte-identical to the target's ground-truth mask;
  none of the 22 non-flips had a coincidental match; all 5 flips export as
  genuinely novel (corr 0.018–0.045 vs any existing feature) with a
  remix-flagged control (corr 1.0) validating the proxy.
- **The honest limit, measured not asserted:** a k-cell XOR target's
  correlation with the true mask under the ladder's only lens is (1/3)^k —
  below the 162-way argmax noise floor for degree ≥5. So aiming works
  *probabilistically*: ~17%/attempt at degree 4, 0/3 at degree 5. An unaimed
  brute control (all masks × lenses) solves 9/10 — the wall is
  evidence-guidance, not reachability. C09 (inversion-count parity, an
  order-statistic) resists both: wrong feature family entirely, an honest
  structural miss.

### 3. Gate v5 (the spine, layer 3)
- Shadow-audited 4 gate variants against 103 real captured gate decisions
  from live passes that replicated the round-1 ablation byte-identically.
- **The pre-registered full-basis designs fail irreducibly, measured:**
  C08's `test_acc(3)` = 1.0000 *exactly* — identical to true remix — so no
  ε or margin in the leave-one-out / marginal-coverage family can separate
  a genuine escape from a reconstruction. The honest negative stands for
  that whole design space.
- **v5-ladder breaks the trade-off by changing the quantifier:** remix =
  reconstructible by families the *ladder can promote* (level-1
  engine-expressible basis), not by audit-only mod-synth/pipeline columns
  the engine can't express. Result: 3/3 C08 admission (1.000), 51/51 true
  remixes blocked, 6/6 wrongly-blocked escapes admitted. (Designed
  mid-experiment from seed-1 interim data — provenance disclosed — then
  evaluated identically on all 3 seeds.)
- **Adopted recommendation:** v5-ladder at the verdict layer (drop-in,
  cheaper per check); retire the vacuous v4 lane (C08 now survives on the
  merits); feed the honest 41% post-revision novel rate to the T8-AG-21
  monitor (vs the lane-pinned 100%); use ladder-novel as the wcore export
  filter; never bind in-loop (13/22 real promotions would flip — the class
  round 1 measured at −2 solves / 5.4× evals).

### 4. Claim-C depth attack (the defensive audit)
- Baseline reproduction exact: both seeds re-derived the identical 20
  promoted atoms; the witness-capturing certifier agreed 20/20 with
  production at depth 3 before being pushed deeper.
- **Flip distribution entirely front-loaded:** 1/20 flips at +1 depth (the
  known a1a6 leak, independently re-verified with a disjoint-seed witness);
  0 flips at +2 through +5 among rows that completed. 3/20
  final-library-redundant (post-hoc, not certifier error). Depth ≥5 vs
  14-atom libraries honestly marked budget-open per row.
- **Kill-test integrity upgraded and re-scoped:** distinct-count correctly
  IRREDUCIBLE with the depth-8 enumeration fully *completed* (16/16
  replicates) — but the closest adversarial approach was **0.9420 vs the
  0.95 match threshold**. The statistical matcher, not depth, is now the
  thinner axis of the certifier.
- **Corrected wording adopted (mirrors I53):** "irreducible at depth ≤ 3
  against the promotion-time library under the production evaluator (0.95,
  8×28 streams)" — never "irreducible"; retro-audit "holds" = "no
  composition found at *completed* depth ≤ D". A +1-depth promotion gate
  (~1 s/candidate) catches the entire observed artifact class.
- Housekeeping correction: the certifier code is `inv_coevo.zig` +
  `inv_atomforge.zig` (not checker.zig/evaluator.zig, which are the
  unrelated STLC line); `reducibleLib` has no register/width axis to push —
  depth is its only resource axis.

### 5. LABS even-N (the record-gap chase)
- Attacked all 12 miss lengths with 7–8 arms each (pair/triple-flip
  neighborhoods with incremental updates, memetic crossover/restarts, three
  mirror-pair structural hypotheses), 160–185M evals per length, three
  sub-runs each within the 15-min cap.
- **Closed: N=44 (E 126→122) and N=50 (161→153) now match best-known.**
  Partial: N=56 (75% of gap), N=60 (22%), N=63 (19%). Unchanged: 48, 61, 64.
  **Regressed: 52, 54, 58, 62** — honestly reported; the methodological
  lesson is real: 2.3–3× total budget *split across 8 arms* underperforms
  yesterday's single concentrated run — next round should winnow arms first,
  then concentrate.
- **Key structural negative:** no even-N analogue of skew-symmetry among
  mirror-pair forms. Fair isolation at N=48 (equal 35M budget, fresh state):
  plain F=6.86 vs mirror-alternating 4.24 vs palindrome/antipalindrome 1.90
  (near-random). Unrestricted pair/triple search won 9/12 lengths. If an
  even-N restriction exists, it isn't in this hypothesis family — finding
  one is genuine open theory (the literature reaches even-N records with
  branch-and-bound compute, not a symmetry trick).
- Verifier: 12/12 new claims + 63/63 prior claims verified; planted two-lie
  test refuted (exit 1). EXTRAORDINARY never fired.

## Synthesis (updated as results land)

1. **Tier 8's load-bearing claim is now quantitative:** 1/9 → 9/9 on a battery
   designed to detect it, replicating round 1's C08 mechanism across two more
   target families plus one *unpredicted* decisive route (D11's monomial
   sign-parity) — the band is a real, populatable region, not a C08 fluke.
2. **Instrument-trust theme continues:** every round that stresses
   `equivalence_tax` finds a defect (stack overflow in round 1, scale
   mismatch now). The tax is load-bearing for the whole Tier 8 program;
   its z-scoring path needs a dedicated audit + fix.
3. **The round's central bet is confirmed at layer 2:** frontier-coupling
   works — the battery-C wall moved 3/33 → 8/33 with byte-identical
   evidence-to-ground-truth derivations, not lucky draws. And its limit is
   now a *formula*, not a mystery: the aiming signal decays as (1/3)^k under
   the current lens, so the next lever is better evidence lenses (raise the
   signal), not more attempts. C09's family-level miss + D08's reachability
   gap mark where proposal-from-evidence ends and genuine
   family/primitive invention has to begin — the same frontier
   sparse_poly's inner-forge work identified from the other side.
4. **WHERE the aim information goes is now settled by three independent
   experiments:** in the forge's fitness it does nothing (exp 1: F 0/9);
   at the promotion/selection step it works (exp 1's aimed_promote — first
   structured-family solve; exp 2's evidence-guided proposal; round 1's
   revision mechanism). Combined with round 1's "tax must not gate the
   inner loop," the architecture principle reads: **inner loops explore
   un-aimed and un-gated; aim and taxes act at selection boundaries.**
5. **Two wall *types* are now measured, needing different tools:**
   climbable-but-unaimed residual landscapes (hashtbl 1.000 — solved by
   gate-level aiming), vs conjunction walls (distinct-count plateau 0.862;
   C09's family miss; D08's reachability gap) where the needed structure
   has no gradient in the current descriptor space. The conjunction-wall
   class is the round's named successor problem: stepping-stone curricula
   or mechanism-level descriptors, with the measured 0.862→0.95 target.
6. **The Tier 8 gate problem is solved in principle:** v5-ladder shows the
   admission/discrimination trade-off was an artifact of quantifying remix
   over a basis richer than the engine can express. "Novel" must mean
   "novel relative to what the system can itself produce" — a
   closure-relative definition, pleasingly consistent with the Closure
   Principle itself. With v5-ladder at the verdict layer + the selection-
   boundary principle (synthesis #4), the Tier 8 loop now has a coherent,
   fully-measured gate architecture.
7. **Certifier trust after two audits:** the artifact class is small (5%),
   entirely front-loaded at +1 depth, and cheaply closable (~1 s/candidate
   promotion-time depth-4 check — adopt it). The new thin axis is the 0.95
   statistical matcher (0.008 kill-test margin) — the next falsification
   round should attack the matcher, not depth.

---

## Round verdict (final)

Six experiments, six completions. The round's bet — *aim the escapes* — is
confirmed with an architecture: *where* aim enters is decisive. Inner loops
explore un-aimed and un-gated; aim, taxes, and novelty verdicts act at
selection boundaries (promotion choice, proposal evidence, verdict layer,
export filter). Concretely delivered: battery-C wall 3/33 → 8/33 with
byte-identical derivations; first-ever structured-family solves via
gate-level aiming; Tier 8 effect size 1/9 → 9/9 on a purpose-built decisive
battery; a gate (v5-ladder) that admits every genuine escape and blocks
every true remix; the certifier leak bounded and closable; two LABS
best-knowns matched. Named successor problems: the conjunction-wall class
(0.862→0.95), better evidence lenses (the (1/3)^k signal), the greedyFit
z-scoring fix, the 0.95-matcher falsification, D08's reachability gap, and
the even-N restriction (open theory).
