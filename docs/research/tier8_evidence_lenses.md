# Tier 8 evidence lenses — raising the (1/3)^k aiming signal

**Harness:** `sparse_poly_discovery/tier8_lenses.zig` (new file; no existing
file modified; the v1 block inside it is a verbatim read-only copy of
`tier8_aimed_proposer.zig`'s machinery so yesterday's 8/33 baseline reproduces
in-harness)
**Date:** 2026-07-10 (round c)
**Seeds:** same 3 as the ablation/aimed-proposer line — `0xF0235A11CE0FF1CE`,
`0xC1B10D20260706`, `0xC2B10D20260707`
**Wall clock:** 5m12.8s single-threaded, full lab (3 seeds × 14 targets × 20
resamples × 6 lenses) + full pipeline (3 arms × 3 seeds). Well inside budget.
**Verdict:** **THE WALL IS DOWN — and the reason is a formula, not luck.**
Better evidence lenses take the battery-C ladder-only score from yesterday's
**8/33 to 33/33** (revision baseline 3/33 and aimed-v1 8/33 both reproduced
byte-identically in-harness first, including v1's exact 13,152-eval cost).
All 30 new flips derive their mask **byte-exact** from evidence (30/30
derivation chains match ground truth), all 30 export as novel (tax proxy corr
0.025–0.083), and the new lens costs *fewer* evals than yesterday's
(12,630 vs 13,152). C11 (degree 5): 0/3 → 3/3. C09 (inversion parity, the
family-level miss): 3/3 — **lens-fixable**, with a precise caveat below about
what "lens" had to mean.

---

## Question

Yesterday (`docs/research/tier8_aimed_proposer.md`) moved the battery-C wall
3/33 → 8/33 and derived why it stops there: the evidence miner scores
candidate cell-subsets through the ladder's only per-cell bit, the threshold
`tb(v)=[v≥3]`, while a k-cell XOR target's label is a parity of the mod-2
bits `lb(v)=v&1`. The per-cell channel `tb↔lb` has correlation 1/3, so the
true mask's evidence signal is exactly **(1/3)^k** — under the 162-way argmax
noise floor at degree ≥ 4, hence ~17%/attempt hits at degree 4, 0/3 at
degree 5 (C11), and a structural miss on C09. This round builds lenses that
raise the signal, **deriving each lens's signal formula before measuring
it**, and re-runs the full pipeline against the re-reproduced 8/33 baseline.

## The derivations (written before the run; verified by it)

Per-cell channel, v uniform on {0..5}: joint counts of (tb,lb) are
(0,0):2, (0,1):1, (1,0):1, (1,1):2, so

- `E[(-1)^lb] = E[(-1)^tb] = 0` (each bit alone is a fair coin),
- `E[(-1)^(tb+lb)] = 1/3` (agree w.p. 2/3), independent across cells.

For target T (|T|=k), label bit `y = ⊕_{i∈T} lb_i`. Every lens below scores
"signed agreement" `E[(-1)^(feature ⊕ y)]` on the search rows (≡ correlation
of ±1 features; noise sd `1/√n = 0.0169` at n=3500; the expected max of m
nulls ≈ `√(2 ln m)/√n`).

| Lens | Feature family | Derived signal | When nonzero | Argmax noise floor |
|---|---|---|---|---|
| **L0** (baseline = yesterday's miner) | tb-parity over mask M (162 masks) | **(1/3)^k** | M = T exactly, else 0 | 0.054 (m=162) |
| **L1** single-upgrade | lb on ONE cell i, tb on M\{i} (1,016 cands) | **(1/3)^(k−1)** | M = T and i ∈ T | 0.063 (m=1016) |
| **L2** pairwise/second-order | lb on a PAIR ⊆ M, tb on the rest (1,792 cands) | **(1/3)^(k−2)** | M = T and pair ⊆ T | 0.065 (m=1792) |
| **L3** Gibbs/conditional | greedy (M,U) growth from L1/L2 top-J seeds, re-measured each step | (1/3)^(k−u) after u recovered cells → grows 3× per accepted step | endpoint validated | endpoint null sd 0.024, accept ≥0.90 ⇒ ~0 false accepts |
| **LW** Walsh spectral (residual over lb bits; also tb bits) | full 256-point WHT per bit-channel | **1.0** at S=T on the lb side (0 elsewhere); (1/3)^k on the tb side | exact | 0.058 (m=510) vs signal 1.0 |
| **LG** GF(2) joint solve | dictionary = 28 comparison bits `c_ij=[g_i>g_j]` + 8 lb + 8 tb + intercept (45 cols); Gaussian elimination on the 3500 search rows, consistency + held-out check | **exact, k-independent** (noiseless linear system; unique solution iff rank 45) | any target linear over the dictionary | none — consistency is checked exactly, the argmax disappears |

Notes forced by the derivation:

1. **Correction to the round brief:** "(1/3)^(k−1) per recovered pair" is
   actually the *single-cell* formula; a recovered **pair** gives
   (1/3)^(k−2). Recovered cells compose multiplicatively: u correct
   mod-2-read cells ⇒ (1/3)^(k−u). (Any cell outside T, read through either
   bit, contributes an independent fair coin ⇒ signal exactly 0 — the
   landscape stays flat off the true mask; only on-mask upgrades help.)
2. **Yesterday's two evidence channels were secretly one family.** The
   monomial sign `sign(φ(M))` and the Walsh `χ_S(signPattern)` are both
   tb-parities (up to fixed sign), so running both bought no second look —
   both are capped at (1/3)^k. C08 is the exception that proves it: its truth
   IS a tb-parity (`0xFF`), measured at signal 1.000 under L0's own family
   (which is exactly why the revision baseline already solves C08 upstream).
3. **Why Gibbs beats the flat argmax** (mechanism, not hope): the flat sweep
   needs the true candidate at **rank 1** of 1,792; Gibbs+endpoint needs it
   only in the **top J** (J=10 L2 + 4 L1 seeds), because each accepted upgrade
   multiplies the re-measured signal by 3 (0.037 → 0.111 → 0.333 → 1.0) and a
   wrong endpoint cannot pass a 0.90 bar whose null sd is 0.024 (~37σ).
4. **Why LG ends the game for this family:** correlation lenses pay the
   (1/3)-per-unrecovered-cell price *per candidate, one candidate at a time*.
   The parity family is closed under GF(2) addition, so ~3.5k noiseless rows
   determine the whole 2^45 hypothesis space at once by elimination — sample
   cost O(dim), not O(3^k), and "argmax vs noise floor" is replaced by exact
   consistency plus a held-out check. **C09 is in the span:** inversion-count
   parity ≡ XOR of all 28 comparison bits (by definition of inversion count),
   i.e. the coefficient vector `cmp=0xFFFFFFF, lb=0, tb=0, k0=0`.
5. **The honest boundary of LG** (stated up front): it works because the
   labels are *noiseless*. With label noise, learning parity from a
   correlation-free channel is the LPN regime — elimination breaks and the
   (1/3)^(k−u) arithmetic of L1–L3 becomes the operative bound again. And the
   dictionary is a choice: C09 became linear only after pairwise-order bits
   were *admitted as evidence primitives*. LG is "a better lens" in exactly
   the sense the task asked for — a better statistic over the same mined
   residual stream — but the C09 fix is dictionary + joint identification,
   not a smarter univariate correlator (the probes below show no correlator
   in the same dictionary works).

### Reproduce

```bash
cd sparse_poly_discovery
zig build-exe tier8_lenses.zig -O ReleaseFast    # zig 0.14.1
./tier8_lenses                                    # 5m13s, single-threaded
# CSV -> results/lenses_2026_07_10.csv  (5,193 data rows)
# smoke: ./tier8_lenses --lab-only --seeds=1 --resamples=2   (~3.5s)
```

---

## Lab results (measured 2026-07-10; 3 seeds × 20 bootstrap resamples of the 5,250 search rows; test rows [5250,7000) never touched by the lab)

### Hit rate per attempt (hit = evidence mask byte-equals ground truth; fa = false accepts)

| Lens | deg-4 XOR (8 tgts) | deg-5 C11 | C08 (tb-par) | C09 (inv-par) | controls (3) |
|---|---|---|---|---|---|
| L0 baseline | 6/480 (**1.3%**) | 0/60 | 0/60 | 0/60 | 0 fa |
| L1 single-upgrade | 94/480 (**19.6%**) | 0/60 | 0/60 | 0/60 | 0 fa |
| L2 pairwise | **480/480 (100%)** | 18/60 (30%) | 0/60 | 0/60 | 0 fa |
| L3 Gibbs | **480/480 (100%)** | **51/60 (85%)** | 0/60 | 0/60 | **0 fa** |
| LW mod2-WHT | **480/480** | **60/60** | **60/60** | 0/60 | **0 fa** |
| LG GF(2) joint | **480/480** | **60/60** | **60/60** | **60/60** | **0 fa (0/180 consistent)** |

Zero false accepts anywhere: the three out-of-family controls
(`product_bind`, `max_parity`, `rank2_eq1`) are rejected by LG's consistency
check in 180/180 attempts (best held-out val 0.527 ≈ chance), and no
validated lens (L3/LW/LG) ever accepted a wrong mask. LG's rank was **45/45
in all 840 attempts** — the dictionary is full-rank on 3,500 rows, so the
recovered representation is *unique*: byte-exact truth recovery is forced by
consistency, not sampled luck.

### Formula check — measured mean signal at the TRUE candidate vs derivation

| Lens | deg-4 measured | deg-4 predicted | deg-5 measured | deg-5 predicted |
|---|---|---|---|---|
| L0 | 0.0087 | 0.0123 | −0.0038 | 0.0041 |
| L1 | 0.0320 | 0.0370 | 0.0052 | 0.0123 |
| L2 | **0.1064** | **0.1111** | 0.0297 | 0.0370 |

Consistent within sampling error (deg-4 has 24 independent seed×target pools,
pool sd ≈ 0.014 ⇒ mean sd ≈ 0.003; deg-5 has only 3 pools, sd ≈ 0.008 — the
deg-5 rows are noisy but sign-correct at L1/L2). The hit rates then follow
the extreme-value arithmetic: L0's 0.0123 sits 0.73σ *below* its own
argmax floor (predict a few %; measured 1.3%); L1's 0.037 ≈ 2.2σ with 4 true
candidates racing 1,012 nulls (predict ~20%; measured 19.6%); L2's deg-4
0.111 clears its floor by ~2.7σ per true pair with 6 true pairs (predict
~100%; measured 100%); L2's deg-5 0.037 is *below* floor but has 10 true
pair-candidates (predict ~25–35%; measured 30%), and Gibbs only needs one of
those in the top-10 to cascade (measured 85%, per-seed 15/20, 20/20, 16/20).
The theory and the measurements agree everywhere it matters.

**Scoring-statistic footnote (honesty):** the lab's L0 uses |corr|-argmax on
bootstrap splits and measures 1.3%; yesterday's in-pipeline miner used a
logistic-fit accuracy argmax at the standard split and hit 5/30 ≈ 17% (small
n; 95% CI ≈ 6–35%). Both are honest measurements of "the true candidate's
signal is below the argmax noise floor" — the hit probability in that regime
is statistic- and split-dependent noise-surfing, which is precisely the
pathology the new lenses remove. The like-for-like comparison is the lab
column above, same statistic, same resamples, across all six lenses. (V1's
logistic path was ALSO re-run in full in the pipeline below and reproduced
its 5 flips exactly.)

### C09 order-statistic probes: no correlator works, even in the right dictionary

| Probe (all in cmp-bit space) | Result (3 seeds × 20 resamples) |
|---|---|
| max abs agreement, 28 single `c_ij` bits | 0.0554 (≈ null max for 28×60 draws) |
| max abs agreement, 200 random pair-subset parities | 0.1286 — weak *real* structure exists (cmp bits are dependent: shared cells + tie bias P(c_ij=1)=5/12), but nowhere near exploitable |
| Gibbs climb in cmp-space (single-bit toggles, endpoint-validated) | **0/60 hits**, best endpoint 0.058 — the landscape toward the all-28 parity is flat |
| LG joint solve over the same bits | **60/60 exact** (`cmp=0xFFFFFFF, lb=0, tb=0`) |

This is the C09 verdict in one table: the miss was **lens-fixable, but only
by joint algebraic identification over an order-statistic dictionary** — the
same dictionary defeats every correlation/greedy statistic we threw at it,
matching the derivation (inversion parity's spectrum over the c-bits is
concentrated on the full 28-bit character).

---

## Pipeline results (task point 3): 3 seeds, same battery-C ladder-only slice

| Arm | Solves | Evals (mining+compose+certify) |
|---|---|---|
| revision baseline (v4 + reality lane), re-run | **3/33** (C08 ×3 — matches yesterday) | — |
| aimed v1 (yesterday's lens path), re-run in-harness | **8/33** (+5: C02, C06 / C05 / C04, C06 — the identical flip set) | 13,152 (identical to yesterday) |
| **aimed v2 (new lenses: LG primary, LW→Gibbs fallback)** | **33/33** (+30: every stuck target, every seed) | **12,630 (≈421/target — cheaper than v1)** |

- All 30 v2 flips routed through **gf2**; the LW/Gibbs fallbacks were never
  needed. Certification used the identical bar (escape to ≥0.90 held-out test
  coverage from below, R² < 0.40 vs the target's own grown library):
  cov 0.47–0.52 → 1.000 on all 30, R² ∈ [−0.187, −0.020].
- **Derivation chains: 30/30 byte-exact** — recovered (lb, tb, cmp,
  intercept) equals the target's `bc.BATTERY_C` ground truth in every flip,
  verified programmatically per flip (printed in the run log), including
  C11's 5-cell `lb=0x37` and C09's `cmp=0xFFFFFFF` (all 28 pairs). Zero
  certified-but-inexact cases.
- **Tax as export filter only** (never a gate): all 30 flips export as
  **novel**, best correlation vs any existing library/near-miss feature
  0.025–0.083 — far from the 0.90 remix bar.
- Search discipline: v2 mining used only rows [0,3500) with validation on
  [3500,5250); the test split [5250,7000) appears only in the certify bar.

## Honesty checks (task point 4)

1. `grep -n "xorMasked\|xorPopcountReadout\|buildXorCols" tier8_lenses.zig`
   → matches only the header comment; **zero call sites**. The GF(2) solver,
   WHT, comparison bits, and parity evaluations are from-scratch local code;
   ground-truth labels come from `bc.labelTarget` (the target oracle), as in
   every prior harness.
2. The v1 arm is a byte-level copy re-run in the same process and reproduced
   yesterday's result exactly (8/33, same 5 flip identities, same 13,152
   evals) — the 33/33 sits on a verified baseline, not a drifted one.
3. LG cannot "return the answer" for out-of-span targets: 0/180 consistent on
   controls, val ≈ 0.5. And within-span recovery is unique (rank 45/45), so
   exact-truth matches are forced, not selected.
4. No thresholds were tuned on outcomes: accept bars (0.90 endpoint, 0.99
   val-acc, 0.5 spectral) were fixed at write time from the derived noise
   sds; the derivations above were written into the harness header before the
   first full run.

## Verdicts

- **C11 (degree 5): lens-limited, now solved.** 0/3 yesterday because
  (1/3)^5 = 0.4% < noise floor. Today: L2 raises the flat-argmax rate to 30%,
  Gibbs to 85%, LW/LG to 100%; pipeline 3/3 with exact masks. The signal-decay
  analysis was the correct diagnosis, and raising the signal was sufficient.
- **C09 (inversion parity): lens-fixable — with the precise meaning that the
  fix = order-statistic evidence primitives (c_ij bits) + JOINT algebraic
  identification.** New primitives in the *evidence dictionary* were required
  (task's option (c) — pairwise comparisons); no correlation-style lens over
  those same primitives works (singles/subsets/Gibbs all fail); the joint
  GF(2) solve recovers the exact 28-bit character 60/60 and certifies 3/3 in
  the pipeline. So: "genuinely needs new primitives" is true at the
  dictionary level, "lens-fixable" is true at the search-machinery level —
  no new *promotable feature family* had to be handed to the system; the
  discovered function is exported through the same composed-candidate path
  as yesterday.
- **The (1/3)^k wall was an estimator artifact, not an information limit.**
  The information was always in the residual stream; per-candidate univariate
  correlation through the tb bit was simply the wrong estimator. The general
  lesson for the aiming program: when the target family is closed under a
  group operation (here GF(2) addition), *identify jointly in that algebra*
  instead of ranking candidates one at a time.

## Limits / open

1. **Noise fragility (the honest asterisk on LG):** exact elimination
   requires noiseless labels. A noisy-label variant (LPN regime) would need
   majority/statistical decoding and re-opens the wall; the L2/L3 lenses
   degrade gracefully instead. Worth one measured round: inject ε label
   noise, find each lens's breakdown curve.
2. **Dictionary admission is the new frontier:** C09 fell to c_ij bits chosen
   because order-statistics were the named suspect family. A principled
   admission rule (which bit-families earn a place in the evidence
   dictionary, at what multiple-testing cost) is the successor question — the
   same shape as the atom-forge/primitive-substrate arc.
3. **The ladder still cannot *promote* these functions as first-class
   features** (`ui.Feature` has no parity-over-lens-bits member) — unchanged
   from yesterday; v2 certifies composed candidates outside the union. If the
   Tier-8 loop should retain these escapes across targets, the Feature union
   needs the (dictionary-mask, parity) variant, which is a framework-revision
   proposal in the T8-AG-22 sense.
4. Battery-C is now saturated (33/33): the battery no longer discriminates
   among evidence-quality improvements. Next battery should include noisy
   parities, deeper compositions (parity-of-products), and non-parity
   order statistics (e.g. `rank2_eq1` stays honest-unsolved here).

## Files

- Harness: `sparse_poly_discovery/tier8_lenses.zig` (lab + pipeline + v1
  copy; `--lab-only/--pipeline-only/--seeds=N/--resamples=N`)
- Data: `results/lenses_2026_07_10.csv` (5,193 data rows: 5,040 lab lens
  rows + 60 C09-probe rows + 93 pipeline rows; schema in header row)
- Run log (full stdout incl. all 30 per-flip derivation chains): reproduced
  by the command above; summary tables also printed by the binary.
- Reads (unmodified, read-only): `unified_invention.zig`,
  `invention_engine.zig`, `equivalence_tax.zig` (config toggles only),
  `open_invention_tier8_battery_c.zig`, `open_invention_rq1.zig`.
- Predecessors: `docs/research/tier8_aimed_proposer.md` (the (1/3)^k
  derivation and 8/33 baseline), `docs/research/tier8_ablation.md`,
  `docs/research/research_round_2026_07_10b.md` (synthesis item 3 names this
  experiment).
