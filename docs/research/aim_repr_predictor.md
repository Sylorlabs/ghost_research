# Aim x Representability — the arc's unifying predictor (2026-07-11, round E)
> **Belongs to: Round 2026-07-11 · experiment E5 of 6 (aim × representability predictor)** — [round index](research_round_2026_07_11.md).

**Question:** the round's capstone. Four rounds converged on "the ceiling is
AIM x REPRESENTABILITY." This experiment makes that quantitative: build
`reach ~ f(representability, aim-quality, diversity, budget)`, measure which
factor dominates, and test the sharpest form of the claim — a **phase
boundary** where aim only pays once representability is satisfied.

**Verdict in one line:** **Representability dominates** (`corr(reach,
repr)=0.807, R²=0.652`, partial R²=0.368 after controlling for aim/D/evals —
5-100x every other factor's partial R²) and the **phase boundary is real and
sharp**: split by representability bin, `corr(aim, reach)` is **0.00 in the
LOW bin, 0.00 in the MID bin, and 0.18 (R²=0.033) in the HIGH bin** — aim's
effect is statistically indistinguishable from zero until representability
clears a threshold, then it turns on. **Certified-solve rate is exactly 0% in
LOW and MID bins regardless of aim or budget, and 45.9% in the HIGH bin** —
the cleanest possible confirmation. Diversity (D), which D6 found to predict
reach at R²=0.405 in isolation, turns out to be a **proxy for
representability** (`corr(D,repr)=0.60, R²=0.36`): once representability is
measured directly and controlled for, D's partial correlation with reach
**flips negative** (-0.238) — extra families beyond what a target needs
dilute a fixed budget rather than helping (a genuine budget-fragmentation
effect, echoing `breadth_vs_depth.md`). Falsification found one honest,
explained failure mode (2.24% of high-aim/high-repr cells still miss —
needle-in-haystack cells where the absolute per-family budget is too small to
find the exact base even when routing is perfect) and zero of the reverse
(low-aim/low-repr cells never spuriously solve).

---

## 1. The four metrics, precisely defined

Reusing the world/family/battery design of round-d's `diversity_predictor.zig`
(6 families, 9-target battery) and the full-enumeration "Bayes ceiling"
method of round-c/d (`tier8_reach_gap.md`, `breadth_scaling.md`) — both
**read-only reuse**, freshly duplicated into a new standalone file per the
round's "new files only" constraint.

**World:** identical 8-cell grid, values in [0,6), 800/400/300 TRAIN/VAL/TEST
split (VAL selects, TEST reports exactly once per decided winner). Six
families (closures): `mono`, `pair`, `walsh`, `spectral`, `worldmod`, `cmp`.
Nine targets: 0-5 each has one "home" family; 6-7 are **conjunctions** of two
heterogeneous families' native predicates (only cross-family combination
reaches them); 8 is the falsification target, outside every family and every
pairwise combination by construction.

### (1) REPRESENTABILITY(target, pool) — continuous, budget-independent, in [0,1]

Precomputed once per (target, active-family-set) as a full-enumeration
ceiling: for every family alone, the best held-out TEST accuracy over its
**entire** candidate space (all bases, AND same-family internal AND/OR/XOR
combos among its top-8 — see §3, the fairness fix); for every pair of
families, the best TEST accuracy of any AND/OR/XOR combination of their
top-8 (by TEST accuracy) candidates. `representability = rescale(best
ceiling accuracy)`, `rescale(a) = clamp((a-0.5)*2, 0, 1)` (chance=0,
perfect=1). This is descriptive — a property of what the closure **can**
express — not a search claim, exactly the round-c/d Bayes-ceiling usage
(`tier8_reach_gap.md`: "the best accuracy over all 255 masks x 6 lenses is
the family-level impossibility bound"). Because targets 6/7 are conjunctions,
representability is naturally continuous: with only one of the two required
families present, the single-family ceiling still partially predicts the
conjunction (an intermediate score, e.g. ~0.6-0.8); with both present, the
pair ceiling reaches ~1.0.

### (2) AIM-QUALITY(proposer, target) — a controlled, non-circular knob A ∈ {0, 0.25, 0.5, 0.75, 1.0}

Operationalized as a real budget-routing mechanism, not asserted: each active
family `f` gets a match score `z_f` = that family's best **VAL** (never TEST)
accuracy against the target — a genuine correlation-strength signal, exactly
the round brief's suggested definition ("probability the proposer's lens
matches the target family; or the correlation signal strength"). `z` is
min-max normalized within the active set and mixed with independent
per-repeat noise: `s_f = A*z_f_norm + (1-A)*noise_f`, routed via
`softmax(s/0.15)` into per-family budget shares of `E_total`. `A=0` → budget
allocation carries no information about which family actually correlates
with the target (pure noise routing). `A=1` → budget concentrates on the
family/families whose VAL-measured correlation is strongest. **Critically,
this mechanism does not know the target's true home family** — it only sees
a VAL-accuracy signal that is only strong when the true family happens to be
present. This is what makes the representability x aim interaction an
**emergent** result of the sweep, not a built-in assumption.

### (3) DIVERSITY = D, count of distinct active families, 1..6 (identical to D6)

### (4) BUDGET = evals_actual, realized (post-cap) candidate evaluations spent per cell

**REACH** (dependent variable): `best_test` = max(best single member TEST
accuracy, best pairwise AND/OR/XOR combo TEST accuracy) — selected by VAL
among the pool's budget-limited, aim-routed, randomly sampled candidates,
reported on TEST exactly once for the already-decided winner (identical
discipline to D6's leakage fix). `reach_score = rescale(best_test)` — same
units as representability, so "reach approaching its ceiling" is a direct
comparable statement. `certified_solve = best_test >= 0.97`.

**Design difference from D6, stated up front:** D6's proposer candidate sets
were sampled once per pool and reused unchanged across all 9 targets
(target-agnostic). Here, because aim is explicitly a per-(proposer,target)
property, each (pool, target, aim, budget, repeat) cell re-routes and
re-samples its members' candidates for that specific target. This is
intentional — it is what makes aim measurable at all.

---

## 2. Harness and sweep

New file: `sparse_poly_discovery/aim_repr_predictor.zig` (no existing file
imported or modified). Zig 0.14.1, `zig build-exe aim_repr_predictor.zig -O
ReleaseFast`, single-threaded, CPU-only.

**Grid:** D ∈ {1..6} (pool size fixed at `N = 4*D`, i.e. `MEMBERS_PER_FAM=4`
constant across D so D isolates diversity, not raw pool size) x R_DRAWS=4
independent random family-subset shuffles per D x 9 targets x 5 aim levels x
3 budget levels (`E_total` ∈ {60, 240, 960}) x 2 inner repeats = **6,480
cells**. Representability is computed once per (D, draw, target) — before
aim/budget/repeat vary — so it is genuinely budget- and aim-independent by
construction, letting all four factors vary largely independently across the
sweep (D and representability do correlate empirically, §5 — that's a
measured finding, not a design flaw, and partial correlations handle it
correctly).

**Cost:** the full-enumeration cache (every (family,base,target) fit + VAL/
TEST prediction vectors, ~4,968 entries) is built once (69ms) and reused by
every downstream computation — representability ceilings, aim routing, and
per-cell candidate selection are all cheap lookups against it, which is what
keeps the whole sweep fast: **0.6s wall clock** for all 6,480 cells, far
under the 15-min budget. Single-threaded throughout (no `std.Thread` used).

**Data:** `results/aim_repr_predictor_2026_07_11.csv`, 6,480 rows + header:
`cell_id, target, D, draw_id, N, members_per_fam, active_mask, aim, e_total,
evals_actual, repr_score, reach_score, certified_solve, best_test_acc,
has_req`.

---

## 3. A bug found and fixed — the exact D6 fairness pitfall, reincarnated

First full run showed representability=1.0 pools with `certified_solve=false`
alongside impossible-looking rows: **D=1 pools (a single family, e.g. `cmp`
alone) reporting `best_test_acc` up to 0.94 on targets that family has
nothing to do with**, while the family's own single-base ceiling was ~0.55-0.57
(chance). Falsification check (B) — "aim<=0.25 & repr<=0.2 but reach>0.6" —
flagged **16/48 (33%) violations**, all D=1, all involving `cmp` (5 bases,
cheap to enumerate) or other small families.

Root cause: `reprScore()`'s single-family ceiling only checked **one base at
a time**; it never tried **same-family** internal AND/OR/XOR combos (only
cross-family pairs were combo-checked). But the actual pool search
(`runCell`) freely combines **any** two members regardless of whether they
share a family — so a D=1 pool with 4 members of the same family can (and
did) find a same-family combo the ceiling never checked, making measured
reach appear to **exceed its own representability ceiling**, which is
mathematically impossible for a true ceiling. This is precisely
`diversity_predictor.md` section 4.2's already-documented fix ("the solo
baseline must get the same combo capability as the pool") — recurring in a
fresh harness, exactly as that doc predicted such asymmetries would if not
guarded against.

**Fix:** `CEIL_SINGLE_TEST` now also searches top-8 same-family internal
combos (mirroring the cross-family pair ceiling) before being used as the
representability ceiling. **After the fix:** violation (B) dropped from
33% to **0/24 (0.00%)** in the same smoke run, and `corr(reach,
representability)` rose from 0.673 to 0.761 (the corrected metric is a
tighter, more informative ceiling). This is the "guard against the leakage
D6 caught" instruction, concretely exercised — not just avoided by
discipline, but caught, diagnosed, and fixed the same way once already.

---

## 4. The regression (n = 6,480 cells)

| predictor | corr(reach, ·) | R² (simple) | partial R² (controlling for the other three + interaction) |
|---|---:|---:|---:|
| **representability** | **0.807** | **0.652** | **0.368** |
| D (diversity) | 0.380 | 0.144 | 0.057 |
| evals_actual (budget) | 0.156 | 0.024 | 0.010 |
| aim | 0.077 | 0.006 | 0.003 |
| repr x aim (interaction) | 0.437 | 0.191 | 0.013 |

**Representability dominates every other factor by 5-100x on partial R².**
Full model `reach ~ b0 + b1*repr + b2*aim + b3*D + b4*evals + b5*(repr*aim)`:
`b0=0.062, b1(repr)=0.922, b2(aim)=-0.084, b3(D)=-0.032, b4(evals)=0.0001,
b5(interaction)=0.204`, **R²=0.682**. The additive-only model (no interaction
term) already gets **R²=0.678** — the interaction adds only +0.004 to a
*linear* R², which understates its importance (§5 shows the true shape is a
**gate**, not a linear slope, so a single interaction coefficient is a blunt
instrument for it). `b2(aim)` flips sign between the additive model (+0.071)
and the interactive model (-0.084) — the textbook signature of an
interaction: aim's marginal effect *at representability=0* is slightly
negative (concentrating all budget onto a noise-selected "best-looking"
family, when nothing actually works, forfeits the stochastic spread that
might otherwise get lucky), and rises through the positive interaction term
as representability increases.

---

## 5. THE PHASE BOUNDARY — the sharpest test, and it holds

Binned by representability (LOW [0,0.34), MID [0.34,0.67), HIGH [0.67,1.0]):

| bin | n | corr(aim, reach) within bin | R² | mean reach_score | certified_solve rate |
|---|---:|---:|---:|---:|---:|
| LOW  | 810  | -0.013 | 0.0002 | 0.078 | **0/810 (0.0%)** |
| MID  | 1,380 | 0.015 | 0.0002 | 0.604 | **0/1,380 (0.0%)** |
| HIGH | 4,290 | **0.181** | **0.033** | 0.860 | **1,968/4,290 (45.9%)** |

**Aim's correlation with reach is statistically zero in LOW and MID, and
clearly positive only in HIGH.** Mean reach_score by (representability bin,
aim level) makes the gate visible directly:

| repr bin | aim=0.00 | aim=0.25 | aim=0.50 | aim=0.75 | aim=1.00 |
|---|---:|---:|---:|---:|---:|
| LOW  | 0.078 | 0.079 | 0.080 | 0.077 | 0.076 |
| MID  | 0.602 | 0.600 | 0.604 | 0.607 | 0.608 |
| HIGH | 0.782 | 0.853 | 0.886 | 0.888 | 0.892 |

LOW and MID are **flat lines** — aim buys nothing, at any level, when the
pool cannot represent the target (LOW) or can only partially represent it via
a single sub-condition (MID — see below for why MID is flat too). HIGH rises
monotonically and substantially (+0.11 from aim=0 to aim=1). The **binary**
certified-solve rate is the starkest version of this: **exactly 0% in LOW
and MID regardless of aim or budget, 45.9% in HIGH** — since MID's ceiling
itself tops out around 0.60-0.70 raw accuracy (well below the 0.97 solve
bar), no amount of aim can push a MID cell over the certification threshold;
only HIGH cells (ceiling near 1.0) are certifiable at all, and aim decides
what fraction of them actually get there.

### Why is MID flat too, not just LOW?

MID-bin cells are mostly conjunction targets (6/7) with only **one** of the
two required families present — the achievable ceiling (~0.6-0.7) comes from
that single family's best individual base, which is **easy to find** at any
budget/aim level (it's the single best-VAL-scoring candidate in a family with
≤92 bases — ordinary random search locates it reliably without needing
correct cross-family routing). Aim's mechanism (routing budget *across*
families) has nothing to add when the ceiling is already "find the one best
base in the one family that matters" — a task any reasonable search
already solves. Aim's payoff appears specifically in HIGH-bin cells that
require **combining** two correctly-identified families under a tight
budget, which is exactly where correct routing (vs. wasted budget on
irrelevant families) matters.

### Budget modulates aim's payoff size (a genuine three-way interaction)

Within the HIGH bin, splitting further by `E_total`:

| E_total | aim=0.00 | aim=0.25 | aim=0.50 | aim=0.75 | aim=1.00 | rise (0→1) |
|---:|---:|---:|---:|---:|---:|---:|
| 60  | 0.713 | 0.782 | 0.826 | 0.826 | 0.838 | **+0.125** |
| 240 | 0.787 | 0.859 | 0.906 | 0.912 | 0.912 | **+0.125** |
| 960 | 0.846 | 0.919 | 0.925 | 0.926 | 0.925 | +0.079 |

Aim's absolute payoff is largest at scarce-to-moderate budget and shrinks at
the most generous budget (diminishing returns as brute-force enumeration
starts to substitute for good routing) — consistent with the arc's repeated
"budget saturation" motif (H50's plateau, breadth_scaling's coupon-collector
ceiling): aim helps most exactly when budget is tight enough that where you
spend it matters.

---

## 6. Reconciling with D6: diversity was a proxy for representability

D6 (`diversity_predictor.md`) found diversity D to predict out-of-closure
reach at R²=0.405, "dominant over count and budget." Measured here directly:

| D | mean representability | n |
|--:|---:|---:|
| 1 | 0.480 | 1,080 |
| 2 | 0.621 | 1,080 |
| 3 | 0.743 | 1,080 |
| 4 | 0.839 | 1,080 |
| 5 | 0.926 | 1,080 |
| 6 | 0.964 | 1,080 |

`corr(D, representability) = 0.600` (R²=0.360) — more families in a pool
mechanically raises the *chance* that a target's required family (or both
required families, for conjunctions) is present. This is exactly why D
predicted reach well in isolation: it was standing in for representability
**without measuring it directly**. Once representability is measured and
controlled for, D's **partial** correlation with reach **flips negative**
(-0.238, partial R²=0.057) — extra families beyond what a target structurally
needs **dilute a fixed budget** rather than helping, a genuine fragmentation
cost (same mechanism `breadth_vs_depth.md` found: "budget fragmentation
kills the expensive... target"). Confirmed directly: restricting to HIGH-bin
cells only (representability already saturated near 1.0, holding it
~constant) and looking at reach by D alone: **0.890 (D=1) → 0.873 (D=2) →
0.871 (D=3) → 0.843 (D=4) → 0.860 (D=5) → 0.857 (D=6)** — a real, if modest
(~0.03-0.05), downward drift as D grows *even when representability is
already satisfied*, the dilution signature. **D6's finding was correct as
measured but not causally complete** — this experiment supplies the missing
causal layer underneath it.

---

## 7. Falsification: does the law survive attempts to break it?

Two directions, both measured, both with mechanism traced (not just counted):

**(A) High aim + high representability but low reach** (`aim>=0.75 &
repr>=0.8 & reach<0.2`): **36/1,608 cells (2.24%)**. Not random — **all 36
are target 2** (the pure XOR-parity target, walsh's home, needing an exact
92-way mask match) at **mostly `E_total=60`** (33/36) and a spread of D
values. Mechanism: this is the same "needle-in-haystack" wall documented in
`breadth_scaling.md` — a parity target's accuracy landscape is flat (~0.50)
everywhere except a single spike at the true mask, so even **perfectly
routed** budget (100% of `E_total` correctly directed to the walsh family)
fails if the *absolute* per-member budget (here ~15 candidates/member out of
92 bases) is too small to reliably land the exact needle in this specific
random draw. This is not a violation of "representability x aim" so much as
a demonstration that **a third ingredient — sufficient absolute budget within
the correctly-aimed family — is jointly necessary**: aim controls *where*
budget goes, not whether there is *enough* of it. Consistent with the arc's
coupon-collector motif throughout (H50, breadth_scaling).

**(B) Low aim + low representability but high reach** (`aim<=0.25 &
repr<=0.2 & reach>0.6`): **0/192 (0.00%)**, clean — once the §3 fairness bug
was fixed, no cell ever solved a target its pool's ceiling said was
impossible. This is the sharper, more important direction to falsify (an
"impossible" target that gets solved anyway would refute representability as
a genuine ceiling), and it holds with zero exceptions across the full sweep.

---

## 8. The unifying model (precise, hedged statement)

> **reach is governed primarily by representability (partial R²=0.368,
> 5-100x every other factor); diversity's predictive power in isolation
> (D6: R²=0.405) is substantially a proxy for representability
> (corr(D,repr)=0.60) and, once representability is controlled for, extra
> diversity beyond what a target needs mildly HURTS reach via budget
> dilution (partial corr=-0.238); aim-quality has an effect that is
> statistically indistinguishable from zero below the representability
> threshold and clearly positive above it (corr(aim,reach) 0.00 → 0.00 →
> 0.18 across LOW/MID/HIGH bins; certified-solve rate 0% → 0% → 45.9%) — a
> genuine phase boundary, not a smooth interaction; and aim's payoff size is
> itself modulated by absolute budget (largest at scarce-to-moderate budget,
> saturating at generous budget), with one honest residual failure mode
> (needle-in-haystack targets at very low absolute budget, 2.24% of the
> high-aim/high-repr cells) where correct aim is necessary but not
> sufficient without enough raw search volume to find the exact candidate.**

In the arc's own vocabulary: **representability gates whether the target is
reachable at all; aim decides, among representable targets, how much of that
reachability is actually realized; diversity's apparent role in earlier
rounds was mostly a low-resolution stand-in for representability; and budget
is a third, jointly-necessary ingredient that determines whether aim's
correct routing can actually be cashed in.**

---

## 9. Honest limitations

1. **Aim is operationalized as cross-family budget routing only**, not
   within-family candidate steering. A richer aim mechanism (e.g. biasing
   *which* bases within a family get sampled, not just how much budget the
   family gets) is untested here and could show a different, possibly
   stronger, phase-boundary shape.
2. **The representability ceiling for cross-family pairs uses a top-8-by-
   TEST-accuracy heuristic**, not exhaustive enumeration of all base pairs
   (that would be `92*92*3` per pair per target — the single-family same-
   family-combo fix in §3 used the identical top-8 heuristic and was
   sufficient to eliminate all measured violations, but a stricter
   exhaustive check was not run; the top-8 heuristic could in principle still
   under-count some pair's true ceiling for a family with many bases whose
   best combining candidate is not among its individually-top-ranked ones).
3. **The battery is small-scale** (8-cell grid, 6 families, 9 targets) —
   this is a model of the phenomenon, in the same spirit as
   `diversity_predictor.zig`/`breadth_scaling.zig`, not the production
   engine. The phase boundary is measured in this model; whether it holds at
   the same sharpness in the full Tier-8 battery is not tested here.
4. **AIM's z_f match score is a single-base VAL ceiling** (no combo
   awareness) — a real, non-circular signal, but a probe with less
   information than the full representability ceiling. This is deliberate
   (a real proposer's cheap pre-scan would not have combo-level foresight
   either) but means aim's routing is somewhat weaker than an oracle router
   would be; the measured phase boundary is therefore a *lower* bound on how
   sharp a better-informed aim mechanism's boundary could be.
5. **Interaction captured two ways** — a single linear `repr*aim` term
   (weak, +0.004 R², because a linear term is a poor fit to a step/gate
   shape) and the bin-conditional analysis (strong, the real signal). The
   headline claim rests on the bin-conditional evidence, not the linear
   interaction coefficient; readers should weight §5 over §4's `b5`.
6. **Single world seed** (`WORLD_SEED`), 4 draws per D, 2 inner repeats — the
   sweep is large (6,480 cells) but built from one grid-generation seed; a
   second independent world was not run in this experiment.

---

## 10. Reproduce

```bash
cd sparse_poly_discovery
zig build-exe aim_repr_predictor.zig -O ReleaseFast   # zig 0.14.1
./aim_repr_predictor --smoke                           # ~0.1s, reduced grid, timing/sanity check
./aim_repr_predictor > ../results/aim_repr_predictor_2026_07_11.csv   # full sweep, ~0.6s
# CSV on stdout (6,480 rows); stderr has target base rates, single-family
# ceilings, correlations/regression, phase-boundary tables, falsification
# report.
```

Single-threaded, CPU-only, ~0.6s wall clock (far under the 15-min budget). No
existing file was modified; `sparse_poly_discovery/aim_repr_predictor.zig` is
the only new file this experiment added, plus this doc and the results CSV.

Cross-references: `docs/research/diversity_predictor.md` (D6, the diversity
metric and train/val/test leakage discipline this experiment reuses and
extends), `docs/research/breadth_scaling.md` /
`docs/research/breadth_vs_depth.md` (the representability/budget-
fragmentation findings this experiment's D-dilution result and needle-in-
haystack falsification case both directly echo), `docs/research/tier8_reach_gap.md`
(the Bayes-ceiling representability method), `CLOSURE_PRINCIPLE.md` (the
arc-level framing this experiment quantifies).
