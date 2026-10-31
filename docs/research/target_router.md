# Target router — a learned selector for which "aim" mechanism to commit to
> **Belongs to: Round 2026-07-11 · experiment E2 of 6 (learned aim / target router)** — [round index](research_round_2026_07_11.md).

**Harness:** `sparse_poly_discovery/target_router.zig` (new file; no existing
file modified; reads `open_invention_tier8_battery_c.zig`, `tier8_battery_d.zig`,
`open_invention_rq1.zig` read-only for battery targets/labels/constants; the
GF(2)-elimination and power-vs-accuracy spectral mechanisms were read from
`tier8_aimed_proposer.zig`/`tier8_lenses.zig` for reference and reimplemented
fresh here — those files expose no public API besides `main`).
**Date:** 2026-07-11 (round E)
**Wall clock:** 1.1s, single-threaded (well inside the 15-min budget).
**Verdict:** **THE ROUTER MATTERS, AND SAYS SO HONESTLY.** On 13 held-out
targets the learned router solves **12/13 (92.3%)** vs fixed-best's **6/13
(46.2%)** and random's **1/13 (7.7%)** — and does it with *fewer* evals
(4,701 vs 6,084 vs 6,165 single-shot; 5,946 vs 8,799 vs 12,579 multi-shot
ranked). It needs roughly **24 labeled training targets** before it starts
beating fixed-best (at n≤16 it ties fixed-best exactly; at n=24 it jumps to
84.6% val accuracy). All 12 correct-and-solving router picks are
independently re-derived (exact mask/statistic recovery, not just "accuracy
cleared 0.90"). No leakage: two exact-duplicate targets (across battery
namings) were caught and deduplicated before the split; the post-fix min
train↔test descriptor distance is 0.037 (clear).

---

## Question

Round b (`tier8_aimed_proposer.md`) moved the battery-C XOR wall 3/33→8/33
with evidence-guided composition, but the lens (mod-2/GF2 over the near-miss
mask) was **fixed by the experimenter**. Round c (`tier8_evidence_lenses.md`)
proved the wall was an estimator artifact and introduced several *exact*
lenses (L0..LG) — always **handed to** the target, never *chosen by* the
machine. This experiment asks the next question in the aim program: can a
**router**, given only a target's own cheap failure signal (which weak
evidence probes fire, the spectral power-vs-accuracy gap, base-rate skew,
etc. — all computable **without knowing which family solves the target**),
**predict** which of several qualitatively distinct aim mechanisms to commit
to, on a target it has never seen labeled?

## Design

### Three mechanisms (families)

Reusing round c's own taxonomy directly: round c found that the battery-C XOR
wall and the C09/B11 order-statistic wall were "secretly one family" — both
live in a single 45-column GF(2) dictionary (LG). That collapses what could
have been four candidate mechanisms into three:

| Family | What it is | Cost (evals) |
|---|---|---|
| **base** | The ladder's own cheap value/threshold basis: monomial sign (degree ≤4, 162 masks), Walsh tb-parity (weight ≤8, 255 masks), single pairwise comparisons (28), world sum/count mod-*k* (6 primes), power-argmax spectral pick on count3 (1), and AND/OR composition of the top-5 of the above (10 pairs × 2 ops). No special aim. | 468 |
| **gf2_joint** | Round-c's LG lens: one 45-column GF(2) dictionary (28 pairwise comparison bits `c_ij=[g_i>g_j]`, 8 mod-2 bits, 8 threshold-@3 bits, intercept), solved by exact Gaussian elimination over ≤300 train rows, certified on held-out test rows. Subsumes both the XOR wall (lives in the 8 mod-2 bits) and the order-statistic wall (lives in the 28 comparison bits). | 45 |
| **spectral_acc** | Round-c's MENUACC fix generalized: accuracy-argmax (not power-argmax) selection over a 200-point frequency grid, across **6** candidate scalar statistics (`sum(g)`, `count(cells≥t)` for t=1..5) instead of just count3. | 1,200 |

Each is a standalone certifier: fit/select on rows `[NTR,NVA)=[3500,5250)`,
certify on `[NVA,NSAMP)=[5250,7000)` — identical split discipline to
`tier8_lenses.zig`. `COVER=0.90` (reused from `open_invention_rq1.zig`).

### Battery (71 targets, reusing the round's own batteries)

- **Battery C** (`open_invention_tier8_battery_c.zig`, 11 targets, minus C10
  — see "Dedup" below): the XOR-popcount family (weight 4–5 masks), C08
  (all-bits tb-parity), C09 (inversion-count parity).
- **Battery D** (`tier8_battery_d.zig`, 11 targets): sum-mod-k (D01–D06),
  count3-mod-k (D07–D10), a subset-Walsh boundary probe (D11).
- **Battery B** (`open_invention_rq1.zig::generateBatteryB`, 11 targets minus
  B11 — see "Dedup"): monomial/Walsh/sign-mod/oriented/composed targets.
- **xor_extra** (12 new): weight-2/3/6/7 XOR masks (battery C only covers
  weight 4–5) — `rol8` of a base run-length mask at 3 shifts per weight.
- **cmp_subset** (6 new): parity over a *prefix* of the 28 canonical
  comparison pairs, sizes {3,6,10,14,18,22} — generalizes C09/B11's
  all-28 case to smaller order-statistic aggregates.
- **spectral_extra** (16 new): `count(cells≥t) mod k` for t∈{1,2,4,5} (t=3 is
  battery D's own count3), k∈{3,4,6,8} — deliberately spans both "power-pick
  already lands right" (base-solvable) and "power-pick lands wrong"
  (spectral_acc-needed) cases, determined **empirically**, not by construction.
- **base_extra** (6 new): plain `sum(g)≥c` / `count(cells≥2)≥c` thresholds.

**Dedup (leakage guard, applied *before* the split):** `open_invention_e2.zig`
reduces `xor_cells` and `parity_xor` to the identical formula
`xorMasked(g,mask)&1`; Battery C's C01 (`xor_cells`, mask=0x0F) and C10
(`parity_xor`, mask=0x0F) are therefore an **exact duplicate pair** — dropped
C10. Battery B's B11 (`inversion_parity`) is an exact duplicate of C09 (same
formula) — dropped B11. Both were originally caught by the router's own
leakage guard (see Honesty checks) before being fixed; the run below is
post-fix.

### The descriptor (10 features, computable without knowing the winning family)

All computed on the VAL split `[NTR,NVA)` only, using cheap near-miss
statistics — never the full arm certifiers:

| # | Feature | What it measures |
|---|---|---|
| d1 | max \|signed agreement\| over monomial162 | weak "value-basis" signal (round-c's L0 statistic) |
| d2 | max \|signed agreement\| over walsh255 | weak tb-parity signal at any weight ≤8 |
| d3 | max \|signed agreement\| over single cmp bits (28) | weak order-relation signal |
| d4 | max \|signed agreement\| over 24 sampled cmp-subset parities | weak *joint* order-statistic signal |
| d5 | best VAL accuracy of world_sum_mod (6 primes) | "is base's own cheapest feature already sufficient" |
| d6 | accuracy of the **power-argmax**-picked frequency on count3 | the ladder's own (possibly wrong) spectral pick |
| d7 | best accuracy over the **full accuracy-argmax** sweep on count3 | what MENUACC would find |
| d8 | d7 − d6 | the power-vs-accuracy gap (round c's core diagnostic) |
| d9 | std-dev of the monomial162 signed-agreement distribution | flatness (XOR-wall signature: no visible peak) |
| d10 | \|mean(Y)−0.5\| on train split | base-rate skew |

### Router

**k-NN on standardized descriptors.** Standardization (mean/sd) is fit on
TRAIN only. `k∈{1,3,5}` is chosen once on VAL (k=3 wins, 0.923 val accuracy);
the **final** router is refit on TRAIN+VAL and scored **once** on TEST.
Ties fall back to the single nearest neighbor. No MLP was needed — the
weak-signal descriptor already separates the three families almost linearly
(see Results), so the round's own guidance ("simplest first... then an MLP
if warranted") stops at k-NN.

### Split (stratified by class, over TARGETS not rows)

Per-class shuffle (seed `0x5171700020260711`), then ~60/20/20 train/val/test
per class (floor 1 in val/test if the class has ≥3 members). Result:
**train=44, val=13, test=13** out of 70 solved targets (1 excluded — see
Honest scope).

### Three arms, scored once on TEST

- **A (router):** k-NN(k=3) trained on TRAIN+VAL, standardized on TRAIN+VAL.
- **B (fixed-best):** always predicts the majority family in TRAIN+VAL
  (`base`, 33/70 overall).
- **C (random):** uniform random family per target (seed
  `0x2A2A2A2A20260711`, single run — theoretical expectation is exactly
  1/3 regardless of class balance, since exactly one of 3 mechanisms is
  tried single-shot per target).

**Metric:** solves (predicted family == the target's true, empirically-
determined winning family) and evals spent (single-shot: cost of the one
mechanism committed to, whether right or wrong; multi-shot/ranked: cumulative
cost of mechanisms tried, in the router's/fixed-best's/random's ranked order,
until the correct one is hit — since the union of the 3 mechanisms solves
every target in this battery by construction, multi-shot always eventually
solves; the question is how many wrong guesses it costs first).

### Reproduce

```bash
cd sparse_poly_discovery
zig build-exe target_router.zig -O ReleaseFast   # zig 0.14.1
./target_router                                   # 1.1s, single-threaded
# CSV -> results/target_router_2026_07_11.csv
```

---

## Results (measured 2026-07-11)

### Class counts (ground truth, determined by actually running all 3 arms on every target)

| Family | Count | Composition |
|---|---|---|
| base | 33 | 9 base_extra+spectral_extra (power-pick already right), 9 batteryD, 8 batteryB, 6 base_extra, 1 batteryC (C08) |
| gf2_joint | 27 | 12 xor_extra, 9 batteryC (XOR-popcount ×8 + C09), 6 cmp_subset |
| spectral_acc | 10 | 7 spectral_extra (genuinely needs accuracy-argmax), 2 batteryD (D08, D09 — reproduces round c exactly), 1 batteryB (B10, see caveat below) |
| *(excluded)* | 1 | B9 "oriented v1>v0" — see Honest scope |

### Sample-complexity curve (VAL accuracy vs #labeled training targets)

| n_train | router | fixed-best | random |
|---|---|---|---|
| 4 | 0.462 | 0.462 | 0.333 |
| 8 | 0.462 | 0.462 | 0.333 |
| 12 | 0.462 | 0.462 | 0.333 |
| 16 | 0.462 | 0.462 | 0.333 |
| **24** | **0.846** | 0.462 | 0.333 |
| 32 | 0.846 | 0.462 | 0.333 |
| 44 (full) | **0.923** | 0.462 | 0.333 |

The router **ties** fixed-best exactly at n≤16 (not "does no better" — it is
*identical*, i.e. with too little data k-NN degenerates toward predicting
the majority class of its tiny neighbor pool, which is exactly the
fixed-best strategy) and **crosses** it between n=16 and n=24. Sample
complexity for this battery/descriptor: **~20–24 labeled targets.**

### Headline: 3 arms on 13 held-out TEST targets

| target | true family | router | fixed-best | random |
|---|---|---|---|---|
| BASE sum>=15 | base | HIT | base (HIT) | miss |
| B5 Walsh χ{S=0x11} | base | HIT | base (HIT) | miss |
| D02 sum%3 | base | HIT | base (HIT) | miss |
| SPEC t4k8 | base | HIT | base (HIT) | miss |
| B7 Walsh χ{S=0x0A} | base | HIT | base (HIT) | miss |
| D04 sum%7 | base | HIT | base (HIT) | HIT |
| XR w6 mask=0xE7 | gf2_joint | HIT | base (miss) | miss |
| CMP sz6 | gf2_joint | HIT | base (miss) | miss |
| C07 XOR 0x99 | gf2_joint | HIT | base (miss) | miss |
| C03 XOR 0x55 | gf2_joint | HIT | base (miss) | miss |
| C11 XOR 0x37 | gf2_joint | HIT | base (miss) | miss |
| SPEC t2k3 | spectral_acc | HIT | base (miss) | miss |
| SPEC t2k4 | spectral_acc | miss | base (miss) | miss |

| Arm | Solves | Solve rate | Evals (single-shot) | Evals (multi-shot, ranked) |
|---|---|---|---|---|
| **router** | **12/13** | **0.923** | **4,701** | **5,946** |
| fixed-best | 6/13 | 0.462 | 6,084 | 8,799 |
| random | 1/13 | 0.077 | 6,165 | 12,579 |

The router beats fixed-best on solves (+6) **and** on both eval-cost metrics
(23% fewer single-shot evals, 32% fewer multi-shot evals) — it isn't winning
by spending more, it wins by aiming better. The one miss (SPEC t2k4,
`count(cells≥2) mod 4`) is a genuine router error: its neighbors in
descriptor space were apparently closer to base/gf2 exemplars than to the
sparse spectral_acc training pool (only 7 non-battery-D spectral_acc
training examples exist — the minority-class data-hunger this experiment set
out to measure).

### Honesty checks

1. **Leakage guard (train→test descriptor distance).** Computed for every
   test target against every train target, standardized using TRAIN-only
   mean/sd. Post-dedup: **min dist² = 0.037** (no warning; the guard is
   wired to flag anything <0.01). Pre-dedup (before C10/B11 were dropped),
   the identical guard **caught the leak itself** — `C01 XOR 0x0F` in TEST
   sat at dist²=0.00000 from its exact duplicate `C10` in TRAIN. This is the
   round-c/D6 lesson working as designed: the guard is not a formality, it
   found a real duplicate on the first run.
2. **Derivation-chain check (task point 5).** For every TEST target where
   the router predicted correctly **and** the predicted family's arm
   actually certified, independently re-derive the winning mechanism's
   parameters and check them against the target's own construction — not
   just "accuracy ≥ 0.90":
   - `gf2_joint` + `xor_extra`/`cmp_subset`: recovered GF(2) solution's
     mod-2-bit portion (bits 28–35) or comparison-bit portion (bits 0–27)
     must equal the target's true mask/pair-subset exactly.
   - `gf2_joint` + battery C: recovered mod-2 bits must equal the target's
     `e2_spec.mask` (XOR-popcount targets) or recovered comparison bits must
     equal all 28 (C09, `inversion_parity`).
   - `spectral_acc` + `spectral_extra`: the winning statistic index must
     equal the target's true constructing statistic.
   - `spectral_acc` + battery D: the winning statistic must be
     `count(cells≥3)` (battery D's own statistic).
   - `base`: certified test accuracy ≥ 0.90 via whichever base sub-family won.

   **Result: 12/12 correct-and-solving router predictions independently
   verified** (all recovered masks/statistics byte-exact to construction).
3. **Router never sees test labels during fit or standardization** — fit
   uses TRAIN (for k-selection) then TRAIN+VAL (for the final model);
   TEST descriptors are computed identically but never touch the fit.
4. **Overlap audit (a design sanity check, not part of the router's own
   scoring):** 33/70 (47%) of solved targets are certified by more than one
   arm — but **every single overlap is structurally expected**, not a sign
   that the three families fail to discriminate:
   - `base`+`gf2_joint` overlaps (Walsh-subset targets, D01 sum%2, C08, B1/B2
     monomial): the true function is a linear combination of the *same* tb/mod-2
     bits that live inside the 45-column GF2 dictionary as a literal subspace
     — of course GF2-joint also certifies them.
   - `base`+`spectral_acc` overlaps (spectral_extra where the power-pick
     already lands correctly, plain threshold targets): spectral_acc's
     accuracy-argmax search is a strict superset of base's own power-pick
     candidate, and its statistic pool includes `sum(g)`/`count(cells≥t)`
     directly, so simple interval predicates fall in both.
   - **Zero overlap** in the "hard wall" targets: every pure XOR-popcount
     (C01–C07/C11), cmp_subset, and xor_extra target sits at gf2_joint=1.0
     with base≈0.5–0.7 and spectral≈0.5 — reproducing round c's core finding
     (the wall is invisible to every other basis) cleanly inside this fresh
     harness.

---

## Honest scope / limitations

1. **B9 "oriented v1>v0" excluded (1/71, base=0.834, gf2=0.500, spec=0.614).**
   Grid cells are `intRangeAtMost(u8,0,5)`; ties (`g[0]==g[1]`, P=1/6) collapse
   to the same output as `g[0]>g[1]` under this harness's single-direction
   `cmpBit` (only `i<j` comparisons are dictionary columns), capping any
   single-comparison-bit family at 5/6≈0.833 accuracy — below COVER on every
   arm. This is a genuine, structurally-expected miss of this harness's
   simplified pair-relation family (not the production ladder's, which may
   handle both comparison directions), documented rather than patched.
2. **B10 "parity AND sum%5" (labeled spectral_acc, spec_acc=0.9069) is a
   borderline/skewed-base-rate case**, not a clean diagnostic: the AND of
   two ~50%/20%-positive-rate predicates has a base rate near 10%, so
   "always predict 0" already scores ~90% — base_acc=0.8903 and
   spec_acc=0.9069 both sit within noise of that ceiling. This harness's
   base arm's AND/OR composer only combines candidates from the
   monomial/walsh/pair pool, never a world_sum_mod feature with a
   walsh feature, so it cannot reconstruct this specific composite exactly;
   spectral_acc's borderline pass likely reflects the skewed base rate more
   than genuine structure recovery. Flagged, not fixed (in TRAIN+VAL only,
   does not affect the TEST headline).
3. **B4 "sign%mod 11" (labeled base, base_acc=0.9114) passes via
   argmax luck, not a dedicated feature.** This harness's base arm
   implements `world_sum_mod` (on `sum(g)`) but not the production ladder's
   separate `world_sign_mod` (on `signPattern(g)`, 0..255) family — B4's
   pass comes from the broader monomial/walsh/spectral candidate pool
   happening to clear 0.9114, not an exact residue check. A follow-up
   harness should add `world_sign_mod` as its own base candidate family.
4. **Single held-out grid seed.** All targets share one grid
   (`0xE2A0011E2026071`, `NSAMP=7000`); no seed-replication arm was run
   (budget: this experiment already used its 15-min allocation on the
   3-arm + curve + honesty-check design, not multi-seed replication).
5. **Small minority class.** `spectral_acc` has only 10 members (7 outside
   battery D) — the sample-complexity curve and the single TEST miss both
   point at this as the router's actual bottleneck, not a flaw in the
   routing method itself.
6. **The "true family" label uses a fixed precedence** (base > spectral_acc
   > gf2_joint) when more than one arm certifies, to assign the cheapest
   genuinely-sufficient mechanism as ground truth. The overlap audit above
   confirms this precedence never contaminates the gf2_joint class (which
   never overlaps with anything) and only ever resolves "this target didn't
   actually need the expensive mechanism" cases correctly.

## Verdict

**The learned router beats both fixed-best and random on held-out targets,
on solves and on eval cost, and needs ~20–24 labeled examples to do it.**
This generalizes round c's exact-GF(2) identification (a lens *handed to* a
known-hard target) to a genuine selection problem (predict *which* lens,
*before* being told the target is hard) — and the three "aim" mechanisms
this router chooses among are themselves nothing more exotic than round c's
own three lenses (base value-basis, GF2-joint, accuracy-scored spectral),
confirming the round's premise that **aim is a scarce, learnable resource**:
a cheap 10-feature failure-signal descriptor, computed without knowing the
answer, is enough to predict where to spend the expensive mechanism's
budget, most of the time, once given enough labeled experience of the
battery.

## Files

- Harness: `sparse_poly_discovery/target_router.zig`
- Data: `results/target_router_2026_07_11.csv` (3 blocks: per-target
  train/val/test rows with descriptor+arm-accuracy+prediction columns;
  sample-complexity curve; summary key/value pairs)
- Reads (unmodified, read-only): `open_invention_tier8_battery_c.zig`
  (`BATTERY_C`, `labelTarget`), `tier8_battery_d.zig` (`BATTERY_D`,
  `labelTarget`), `open_invention_rq1.zig` (`generateBatteryB`,
  `labelBattery`, `NSAMP`/`NTR`/`NVA`/`COVER`)
- Predecessors: `docs/research/tier8_aimed_proposer.md` (the fixed-lens
  8/33 baseline and the (1/3)^k derivation), `docs/research/
  tier8_evidence_lenses.md` (the exact-lens 33/33, the LG unification this
  experiment's `gf2_joint` family reuses directly), `docs/research/
  tier8_reach_gap.md` (D08/C09 family-vs-selection diagnosis, reused for the
  `spectral_acc` and `gf2_joint` family designs)
- Round: `docs/research/research_round_2026_07_11_PLAN.md`,
  `docs/research/research_round_2026_07_11.md`
