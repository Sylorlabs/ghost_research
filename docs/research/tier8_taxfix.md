# Tier 8 tax-instrument repair — greedyFit train/test scale mismatch
> **Belongs to: Round 2026-07-10c · experiment 3 of 6 (greedyFit tax fix)** — [round index](research_round_2026_07_10c.md).

**Round:** 2026-07-10c (instrument repair)
**File modified:** `sparse_poly_discovery/equivalence_tax.zig` (`greedyFit` only — the one
edit this round is permitted; all other files new or read-only)
**Harnesses re-run (read-only):** `sparse_poly_discovery/invention_engine.zig`
(`--strict-tax`), `sparse_poly_discovery/tier8_ablation_d.zig`,
`sparse_poly_discovery/tier8_gate_v5.zig` — all rebuilt against the fixed tax
**Date:** 2026-07-10
**Verdict:** the fix makes the tax block every mod-synth-reconstructible escape it was
always supposed to block. The battery-D decisive band grows **3 → 8** (all five
TOO_EASY leaks D02/D03/D04/D09/D10 now classify DECISIVE), Battery-B target **B3
(sum%7) turns out to have been leaking too** and becomes a clean 3/3-seed decisive
member, the two-arm effect size moves from 1/9-vs-9/9 to **0/24-vs-22/24** (plus
29/33-vs-33/33 on Battery B), and the stock `--strict-tax` production battery is
**bit-for-bit unchanged** (11/11, same evals, same library, same tax counters).
Gate v5's verdict-layer conclusion survives re-audit (see §5).

---

## 1. The bug

`docs/research/tier8_battery_d.md` §3 diagnosed it by reading; this round confirms it
by fixing. In `greedyFit` (the greedy forward-selection fit that produces the tax's
`test_acc` reconstruction statistic), the final per-round fit/eval pair disagreed
about feature scale:

1. `fitLogit` was called on the **raw** selected columns (`Xtr`, 120 epochs, lr 0.05);
2. `Xte` was then z-scored with the train split's mean/std;
3. `accLogit` evaluated the **raw-fit weights** against the **z-scored** test columns.

The weight vector was optimized for one affine frame and scored in another. For a
binary {0,1} column the decision boundary happens to survive the substitution almost
by construction, so binary remainders (`mod(x,2)`-shaped columns) still separated —
which is why D01/C08 stayed decisive and the bug went unnoticed. For 3+-valued
remainder columns (`mod(sum,3)`, `mod(count3,3..6)`, …) survival depended on the
accident of that column's empirical mean/std, so the tax silently failed to block
escapes it could reconstruct perfectly: 5 of 11 battery-D candidates leaked TOO_EASY
(escape certified, never blocked), and — found this round — Battery-B's B3 (sum%7)
had been leaking through the same hole in every prior strict-tax OFF-arm run.

## 2. The fix (minimal, consistent)

Standardize **both** splits with the train split's statistics, then fit and evaluate
in that one frame:

```diff
         const dim = n_sel;
         for (0..ui.NSAMP) |s| {
             for (0..dim) |j| Xtr[s][j] = cols[selected[j]][s];
-            Xtr_rows[s] = Xtr[s][0..dim];
         }
         for (0..ui.NSAMP) |s| {
             for (0..dim) |j| Xte[s][j] = cols[selected[j]][s];
         }
-        fitLogit(&Xtr_rows, Y, dim, 120, 0.05, &w);
         for (0..dim) |j| {
             var mu: f64 = 0;
             for (0..ui.NTR) |s| mu += Xtr[s][j];
             ...
             sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(ui.NTR))));
+            for (0..ui.NSAMP) |s| Xtr[s][j] = (Xtr[s][j] - mu) / sd;
             for (0..ui.NSAMP) |s| Xte[s][j] = (Xte[s][j] - mu) / sd;
         }
-        for (0..ui.NSAMP) |s| Xte_rows[s] = Xte[s][0..dim];
+        for (0..ui.NSAMP) |s| {
+            Xtr_rows[s] = Xtr[s][0..dim];
+            Xte_rows[s] = Xte[s][0..dim];
+        }
+        fitLogit(&Xtr_rows, Y, dim, 120, 0.05, &w);
         best_test = accLogit(&Xte_rows, Y, &w, dim, 0, ui.NSAMP);
```

Why z-score both (rather than drop the z-scoring and go raw both ways): (a) the
original code's evident intent was standardized evaluation — it z-scored `Xte`
deliberately; the omission was on the fit side; (b) statistics computed on the train
split and applied identically to train and test is the textbook scaling protocol —
no test-set leakage, one model frame; (c) the remix basis mixes columns whose scales
span orders of magnitude (mod-synth `mul`/`add` nodes vs {0,1} monomial signs), and
a fixed-budget SGD logit (fixed lr, 120 epochs) systematically underfits large-scale
columns on raw data — i.e. the raw-frame fit *understates reconstructibility*, which
is exactly the observed leak. Standardization makes the fixed budget uniformly
effective across the basis, so `test_acc` is a tighter approximation of "can this
basis reconstruct the candidate."

Deliberately **not** changed: the per-round candidate-selection loop (fit raw → score
raw on the validation slice) is internally consistent — both sides of that comparison
live in the same frame — so it is left alone. Also noted while reading:
`WITNESSED_SURVIVORS`/`isWitnessed` (the `world_sum_mod(7)` whitelist) is dead code —
defined, never called — so nothing shields B3 from the fixed tax.

## 3. Regression gate (a): stock `invention_engine --strict-tax`

Rebuilt pre-fix and post-fix binaries, ran both. Output is **line-identical**
(modulo the known garbage-label bytes on B11's dangling escalation label and wall
time): certified **11/11**, battery evals **372**, final library **19**, tax
`checked=8 novel=8 remix_blocked=0`. Zero shift to explain: the production battery
runs at basis v4 with the reality lane on, where all 8 checked promotions are
certified escapes admitted by the lane regardless of the remix statistic, and none
of the greedy verdicts flip on these particular candidates.

## 4. Regression gate (b): battery-D reclassification + updated ablation

### 4.1 Baseline reproduction (pre-fix binary, control)

Before touching anything, the pre-fix binary was re-run: it reproduces
`tier8_battery_d.md` exactly — 3/11 decisive {D01, D07, D11}, the same five
TOO_EASY leaks, Phase-2 aggregate 1/9 vs 9/9, and a byte-identical
`results/battery_d_2026_07_10.csv`. The instrument change is therefore the only
variable in what follows.

### 4.2 Post-fix classification (production seed, same method)

| Target | base rate | OFF | OFF cov | OFF blocked | ON | ON route | Class (pre-fix → post-fix) |
|--------|-----------|-----|---------|-------------|-----|----------|----------------------------|
| D01 sum%2 | 0.506 | stuck | 0.479 | 1 | SOLVE | world | DECISIVE → **DECISIVE** |
| D02 sum%3 | 0.330 | stuck | 0.672 | 1 | SOLVE | world | TOO_EASY → **DECISIVE** |
| D03 sum%5 | 0.188 | stuck | 0.807 | 1 | SOLVE | world | TOO_EASY → **DECISIVE** |
| D04 sum%7 | 0.145 | stuck | 0.859 | 1 | SOLVE | world | TOO_EASY → **DECISIVE** |
| D05 sum%11 | 0.099 | SOLVE | 0.904 | 0 | SOLVE | base | TOO_EASY → TOO_EASY |
| D06 sum%13 | 0.066 | SOLVE | 0.927 | 0 | SOLVE | base | TOO_EASY → TOO_EASY |
| D07 count3%3 | 0.335 | stuck | 0.655 | 1 | SOLVE | menu | DECISIVE → **DECISIVE** |
| D08 count3%4 | 0.281 | stuck | 0.713 | 0 | stuck | — | TOO_HARD → TOO_HARD |
| D09 count3%5 | 0.220 | stuck | 0.783 | 1 | SOLVE | menu | TOO_EASY → **DECISIVE** |
| D10 count3%6 | 0.117 | stuck | 0.879 | 1 | SOLVE | menu | TOO_EASY → **DECISIVE** |
| D11 subset-parity{0-3} | 0.499 | stuck | 0.503 | 3 | SOLVE | forge | DECISIVE → **DECISIVE** |

**8/11 DECISIVE.** All five leaks moved to DECISIVE — in every case the OFF arm now
certifies the same escape it always certified and the fixed tax **blocks** it
(blocked ≥ 1), instead of silently letting it promote. The three non-movers stay for
their original, predicted reasons: D05/D06 solve from the library baseline before any
escape is attempted (mod-synth `k` range 2..8 can't reach 11/13, and the skewed base
rate lets `cov0` clear 0.90 — the clean negative control), and D08 is a
ladder-reachability gap (neither arm ever certifies an escape).

With the instrument fixed, the original a-priori tax-fate predictions of
`tier8_battery_d.md` §1 are now right for **every testable candidate except D11**
(9/10; D08 untestable — no escape to tax): "reconstructible by the mod-synth bank"
now *is* sufficient for a block. D11 remains decisive via the monomial-forge
sign-parity mechanism, blocked through monomial columns as before — its
"not remixable" prediction stays wrong, unchanged by the fix.

### 4.3 Phase 2 — two-arm × 3-seed ablation on the new 8-target decisive set

| Seed | Arm | B solve | D-decisive | Tax checked | Novel | Blocked | B evals |
|------|-----|---------|------------|-------------|-------|---------|---------|
| 0xF023… | OFF | 10/11 | 0/8 | 31 | 0 | 31 | 1383 |
| 0xF023… | ON (rev@1) | 11/11 | 8/8 | 21 | 14 | 7 | 693 |
| 0xC1B1… | OFF | 9/11 | 0/8 | 30 | 0 | 30 | 1733 |
| 0xC1B1… | ON (rev@1) | 11/11 | 7/8 | 20 | 13 | 7 | 693 |
| 0xC2B1… | OFF | 10/11 | 0/8 | 30 | 0 | 30 | 1383 |
| 0xC2B1… | ON (rev@1) | 11/11 | 7/8 | 19 | 12 | 7 | 686 |

Aggregate (3 seeds):

| Metric | ARM-OFF | ARM-ON | pre-fix (3-target set) |
|--------|---------|--------|------------------------|
| Battery B | **29/33** | **33/33** | 32/33 vs 33/33 |
| D-decisive | **0/24** | **22/24** | 1/9 vs 9/9 |
| Novel promotions | 0 | 39 | 4 vs 26 |
| Remix-blocked | 91 | 21 (all pre-revision) | 65 vs 21 |
| Battery B evals | 4499 | 2072 | 4412 vs 2072 |
| Solved ON-only | — | **26** | 9 |
| Solved OFF-only | 0 | — | 0 |

Per-target replication of OFF-blocked → ON-solved:

- **3/3 seeds:** D01, D02, D03, D04, D07, D10, D11 — and **B3 (sum%7)**, a
  Battery-B target, whose `world_sum_mod(7)` escape the buggy tax had been
  leaking in OFF arms all along (certified escape blocked 1× per seed, OFF cov
  0.850–0.860, ON cov 1.000). Note D07 improves from 2/3 pre-fix to 3/3: its
  borderline seed (0xC1B1) was itself an artifact of the scale accident.
- **1/3 seeds:** D09 (count3%5) — ON-solves only at 0xF023 (where OFF certifies
  the menu escape and the fixed tax blocks it: checked=1, blocked=1). At
  0xC1B1/0xC2B1 *neither* arm solves it and *neither* arm ever certifies an
  escape (checked_d=0 in both arms, cov stuck at 0.788/0.767) — at those grids
  D09 is a ladder-reachability gap like D08, not a tax effect. D09 is decisive
  at the production seed but borderline across seeds — reported as found, the
  honest successor to pre-fix D07's 2/3.
  B10 (parity AND sum%5) also stays a 1/3-seed marginal (0xC1B1 only,
  escape never certified elsewhere, blocked_certs=0 — same as every prior round).
- ARM-OFF novel count is now **0** — under frozen v3 with a working instrument,
  *every* checked promotion in these runs is correctly recognized as
  basis-reconstructible. The single pre-fix OFF "novel" was the leak.

The revision effect is not just replicated but larger and cleaner: **26 target-seed
existence proofs (0 reverse separations)** vs 9 pre-fix, at the same ON-arm eval
cost (2072, identical trajectory) and a *higher* OFF-arm cost (4499 — more blocked
promotions force more re-escalation).

## 5. Regression gate (c): gate-v5 shadow audit re-run

`tier8_gate_v5.zig` rebuilt against the fixed tax, full shadow audit re-run
(~11 min, 2 threads, same seeds). Verdict: **v5-ladder's conclusions survive —
every load-bearing number either reproduces digit-for-digit or moves in the
direction that strengthens the original recommendation.**

**ADMISSION (need ≥0.90):** v5-ladder admits C08 **3/3** with reconstructed
coverage 1.000; all full-basis variants (v5-full ε=0…0.08, v5-margin) fail
**0/3** with coverages **0.506 / 0.483 / 0.502** — digit-for-digit identical to
the pre-fix run. The irreducible admission/discrimination trade-off for
full-basis gates is unchanged.

**DISCRIMINATION:** the planted pool (OFF-pass remix-blocked captures) grows
**57 → 69** because the fixed v3 tax blocks more: per seed 23 captures (was 19).
The new pool partitions exactly, verified row-by-row in the CSV:

- **60 true remixes** — every one with `test_acc(1) = 1.0000`; v5-ladder blocks
  **60/60 (100%)**, matching pre-fix 51/51.
- **9 wrongly-blocked certified escapes** — v5-ladder admits **9/9**: the 6 C08
  escapes (cov_before ≈ 0.49–0.51, `test_acc(1)` ≈ 0.73, same signatures as
  pre-fix) **plus 3 new B3 (sum%7) escapes** (one per seed, cov_before
  0.850–0.860, `test_acc(1)` 0.855–0.862, mod-synth family) — the very escapes
  the fixed tax newly blocks in OFF arms. v5-ladder correctly recognizes them
  as engine-novel (`world_sum_mod(7)` excluded, nothing else at level 1
  reconstructs sum%7) without any new tuning — the engine-expressible principle
  generalizes to the newly-exposed decisive member on first contact.

v4 (live gate) still admits 69/69 — the vacuous-lane hole, unchanged.
v5-full/margin block 69/69, i.e. they now also kill the 3 B3 escapes —
the full-basis trade-off got *worse* under the fixed instrument (see NO-HARM).

**NO-HARM:** pre-revision 0/21 flips for both v5-full(ε=0) and v5-ladder
(faithful v3-strict shadows, same as pre-fix). Post-revision: 22 events split
**9 novel / 13 remix** under the fixed v4 measurement — the identical split to
pre-fix — and **v5-ladder agrees with the v4 verdict 22/22** (identical),
would-block 13/22 (identical). The full-basis variants worsen: v5-full
18/22 → **22/22** would-block, v5-margin 18/22 → **21/22** — with a
consistently-scaled fit, level-3 reconstructibility saturates at ≥COVER on
even more real promotions, further confirming that full-basis
reconstructibility cannot serve as a binding gate.

**Live-pass internal control:** ARM-ON reproduces exactly (B 33/33, C-ladder
3/33, evalsB 692/699/692, revision@1 every seed). ARM-OFF B drops 32/33 →
**29/33** — B3 blocked at all 3 seeds, the same migration the battery-D
harness measured independently.

The gate-v5 doc's recommendation (adopt v5-ladder at the verdict layer, keep
promotion measurement-only, retire the v4 lane, do not bind in-loop) stands
under the fixed instrument, with *stronger* discrimination evidence (69-row
pool, 2 independent escape families) and *stronger* evidence against
full-basis binding.

## 6. Verdict-migration table (every prior number that changed)

Every prior published number that the fix changes, with source doc:

| # | Prior claim (doc) | Pre-fix value | Post-fix value | Direction |
|---|-------------------|---------------|----------------|-----------|
| 1 | D02/D03/D04/D09/D10 class (`tier8_battery_d.md` §2) | TOO_EASY ×5 | **DECISIVE ×5** | leak closed |
| 2 | Decisive battery-D set (`tier8_battery_d.md`) | 3/11 {D01,D07,D11} | **8/11** {D01–D04,D07,D09–D11} | grows |
| 3 | Phase-2 D-decisive effect (`tier8_battery_d.md` §4) | OFF 1/9 vs ON 9/9 | **OFF 0/24 vs ON 22/24** | stronger |
| 4 | ON-only existence proofs (`tier8_battery_d.md` §4) | 9 | **26** | stronger |
| 5 | D07 OFF-block replication (`tier8_battery_d.md` §4) | 2/3 seeds | **3/3 seeds** | pre-fix borderline was the instrument artifact |
| 6 | Battery-B ARM-OFF under strict v3 (`tier8_ablation.md` §"Per-seed", reproduced identically in both re-run harnesses) | B 32/33 | **B 29/33** | B3 (sum%7) was leaking; now a 3/3-seed decisive member |
| 7 | ARM-OFF tax counters, battery-D harness | novel 4 / blocked 65 / checked 69 / evalsB 4412 | **0 / 91 / 91 / 4499** | v3 novel-rate drops to 0 — every strict-v3 promotion in these runs is remix |
| 8 | ARM-ON tax counters, battery-D harness | novel 26 / checked 47 | **39 / 60** | more targets, all post-revision admits; blocked 21 unchanged |
| 9 | Gate-v5 planted pool (`tier8_gate_v5.md`) | 57 = 51 true + 6 escapes | **69 = 60 true + 9 escapes** | pool grows; partition stays exact |
| 10 | v5-ladder discrimination (`tier8_gate_v5.md`) | 51/51 blocked + 6/6 admitted | **60/60 blocked + 9/9 admitted** | conclusion survives, coverage extends to B3 |
| 11 | v5-full post-rev would-block (`tier8_gate_v5.md`) | 18/22 | **22/22** | full-basis gate looks worse |
| 12 | v5-margin post-rev would-block (`tier8_gate_v5.md`) | 18/22 | **21/22** | worse |
| 13 | Greedy non-monotonicity instance (`tier8_gate_v5.md` footnote: one row with `test_acc(3)=0.690 < test_acc(1)=0.901`) | 1 observed row | **0 rows** (no `test_acc(3) < test_acc(1)` anywhere in the 115-row audit) | that instance was itself the scale artifact; v5-full's verdict agreement is now a clean 13/22 (blocks everything) |

**Numbers that did NOT move** (checked, not assumed): stock `--strict-tax`
production battery (11/11, 372 evals, 19 library, 8/8/0 tax counters,
line-identical); gate-v5 admission (3/3 vs 0/3, coverages 0.506/0.483/0.502
digit-for-digit); no-harm pre-revision 0/21; post-revision verdict split
9 novel / 13 remix and v5-ladder agreement 22/22 and would-block 13/22; every
ARM-ON live trajectory (evalsB 693/693/686 battery-D harness, 692/699/692
gate-v5 harness, revision@1 all seeds); D01/D07/D11 decisive, D05/D06
TOO_EASY, D08 TOO_HARD; B10's 1/3-seed marginal status; C08's mechanism and
all Battery-C claims (binary-remainder class — the class the bug never
affected).

## 7. Honest scope

- The fix touches only the final fit/eval pair inside `greedyFit`. The candidate
  pre-filter (train-correlation) and per-round selection (raw fit, raw validation
  scoring) are unchanged; they are internally consistent but still greedy
  approximations. Greedy non-monotonicity remains possible in principle (the
  statistic is not a certified reconstructibility bound), though the one instance
  observed in the v5 round disappears under the fixed instrument (migration #13).
- `results/battery_d_2026_07_10.csv` and `results/gate_v5_2026_07_10.csv` were
  regenerated by the (deterministic) harnesses under the fixed tax during this
  round and then **restored to their committed pre-fix contents**, so those files
  keep matching the docs that cite them. The post-fix data lives in
  `results/taxfix_2026_07_10.csv` (summary + migrations) and
  `results/battery_d_taxfix_2026_07_10.csv` / `results/gate_v5_taxfix_2026_07_10.csv`
  (full harness outputs under the fixed tax).
- Not re-run: `tier8_ablation.zig` (original B+C ablation), the taxonomy round,
  and the tax-gate-promotion economics. Their headline *mechanism* conclusions are
  unaffected in direction (v3→v4 revision remains load-bearing; blocking in-loop
  remains expensive), but any of their OFF-arm numbers that involve B3 solving
  under strict v3 (e.g. the original ablation's ARM-OFF "B 32/33") are now known
  to include one instrument leak and would shift to 29/33-class values under the
  fixed tax. C08/Battery-C claims are untouched: C08 is binary-remainder class,
  the class the bug never affected, and the gate-v5 re-audit (§5) re-measures its
  admission directly.
- Wall times: stock battery ~25 s; battery-D harness ~10 min single-threaded
  (8-target Phase 2); gate-v5 ~11 min, 2 threads. All within round limits.

## Files

- Fix: `sparse_poly_discovery/equivalence_tax.zig` (`greedyFit`)
- Data: `results/taxfix_2026_07_10.csv`,
  `results/battery_d_taxfix_2026_07_10.csv`,
  `results/gate_v5_taxfix_2026_07_10.csv`
- Logs and pre/post binaries retained in the session scratchpad only; harnesses
  rebuild reproducibly with `zig build-exe <harness>.zig -O ReleaseFast` (zig 0.14.1)
