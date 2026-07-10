# Research Round 2026-07-10b — aiming the escapes

**Status:** LIVE — updated as each experiment lands. 3/6 complete.
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
| 1 | Aimed forge (wcore) | Does residual pressure toward a named frontier beat pure novelty at equal budget? Baseline: unaimed = 3/18→4/18, structured family never flips. | pending | — | `wcore/docs/research/aimed_forge.md` |
| 2 | Aimed proposer (battery-C wall) | Do near-miss witnesses + residual-guided feature proposal move the 10/11 battery-C wall? Baselines: 0/33 frozen, 3/33 revision. | **DONE** | **Wall moves: 3/33 → 8/33.** Every flip's evidence-mined mask is byte-identical to ground truth; all 5 export as novel. Honest limit: the correlation signal is (1/3)^k — aiming is probabilistic (~17%/attempt deg-4, 0 at deg-5); C09's family is a structural miss. | `docs/research/tier8_aimed_proposer.md` |
| 3 | Gate v5 discrimination | Is there a gate that admits certified escapes (C08 must still pass) AND blocks planted remix (v4 passes 100%)? | pending | — | `docs/research/tier8_gate_v5.md` |
| 4 | Claim-C depth attack (wcore) | Do wcore's "irreducible" verdicts survive +1/+2/+3 certifier depth, or are they resource artifacts (the I53 attack, applied to wcore)? | pending | — | `wcore/docs/research/claimc_depth_attack.md` |
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
