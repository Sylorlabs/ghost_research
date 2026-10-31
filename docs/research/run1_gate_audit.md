# RUN1 gate audit — is the novelty gate correct to reject the exact `run(maxRunGE3)` member?
> **Belongs to: Round 2026-07-11b · experiment F3 of 6 (RUN1 certifier-boundary audit)** — [round index](research_round_2026_07_11b.md).

**Harness:** `sparse_poly_discovery/run1_gate_audit.zig` (new file; no existing
file modified). Transcribes RUN1's definition and the pre-tax novelty gate's
exact mechanism (`certifyLocal`'s `R2 < 0.40` check) from
`sparse_poly_discovery/repr_expansion.zig`, read-only, per the established
per-file-standalone convention. **Date:** 2026-07-11 (round F). **Zig 0.14.1**,
`zig build-exe -O ReleaseFast`, single-threaded, CPU-only.
**Seeds:** the 3 standard — `0xF0235A11CE0FF1CE`, `0xC1B10D20260706`,
`0xC2B10D20260707` (Part 1+2, 3 seeds); Part 3+4 at the production seed only
(1 seed, secondary/confirmatory scope decision, cost-bounded).
**Wall clock:** 137.4 s total, single binary (`./run1_gate_audit`), well under
the 15-min bound; smoke-tested first via `./run1_gate_audit --diag` (34 s).

**Verdict (one line): the gate is WRONG — it is measuring the wrong quantity.**
`run(maxRunGE3)`'s R² (0.73–0.77 against a *far more generous* library than
production ever built, 0.51–0.53 in the original production measurement) is
high not because RUN1 is genuinely redundant with the count/order basis, but
because **linear R² of a raw, ident-lensed continuous statistic is a poor,
non-monotonic proxy for label-reconstructibility.** A direct, decisive
demonstration: an explicitly-constructed *genuine* remix target
(`RUN-var3`, exactly reconstructible via `cmp(low6)==0`, confirmed 1.0000
accuracy from only 4 features) scores R²=0.50 — **lower** than RUN1's R²=0.73,
even though RUN1 never crosses the certify bar under any tested composition.
R² ranks a truly-redundant target below a truly-irreducible one: the
statistic is not just miscalibrated, it is **not monotonic in the thing that
matters** (AUC 0.889, not 1.0, and the two failure points are exactly RUN1 and
its sibling RUN-var2). The corrected measure — generous multi-feature
classification accuracy of the excluded-family library against **COVER=0.90**
(the certifier's own existing constant, reused, not a new number) — cleanly
separates all 9 tested targets with **zero errors**, admits RUN1, and still
rejects every true remix including the fragile RUN-var3 case the current gate
barely catches.

---

## 1. Reproduce (Part 1)

Grid/labels/gate mechanics reproduced independently of `repr_expansion.zig`
(new grid draws, same seeds/splits: NSAMP=7000, NTR=3500, NVA=5250). Library
built via **greedy forward multi-feature selection** over a 241-column pool
spanning all 9 non-run existing families (mono/walsh/spectral/clifford/world/
cmp/thresh/mixr/ratio — `run` never appears in the pool) — a strictly
*stronger* reconstruction attempt than the original sequential
one-feature-per-family ladder, since it picks the single best-classifying
column from the **entire** menu at every round, 12 rounds deep:

| seed | cov_before (K=12, generous) | cov_after (+run feature) | R²(incidental, vs same lib) |
|------|---:|---:|---:|
| 0xF0235A11CE0FF1CE | 0.9011 | 1.0000 | 0.7673 |
| 0xC1B10D20260706 | 0.8817 | 1.0000 | 0.7347 |
| 0xC2B10D20260707 | 0.8789 | 1.0000 | 0.7423 |
| **mean** | **0.8872** | **1.0000** | **0.7481** |

Original production measurement (repr_expansion.md, §4): cov0 ≈ 0.79,
cov_after = 1.000, R² = 0.51–0.53. **Confirmed qualitatively**: cov_after is
exact at every seed here too; R² is well above the 0.40 gate at every seed
(mine is even higher than production's, discussed in §3 — richer libraries
mechanically inflate R²). The gate's verdict — reject — reproduces cleanly:
`gate_verdict=reject` at all 3 seeds (CSV `gate_repro` rows).

**The one number that matters most: cov_before never robustly clears COVER.**
Even with a search 2–2.5× more thorough than production's ladder (12
globally-best features vs. production's ~5–6 one-per-family features), mean
cov_before = 0.887, and the single seed that nominally crosses 0.90 does so by
0.0011 — a razor-thin margin, not a decisive escape. Compare to the run
family's own single feature: instant, exact, all 3 seeds.

## 2. The core test (Part 2) — does an explicit reconstruction exist?

**(2a) Incidental library** (optimized to classify Y directly, table above):
plateaus at 0.879–0.901. Feature order is consistent across seeds — spectral
count → world sign-mod → cmp aggregate → walsh χ → then a run of monomial
degree-2/3/4 products (adjacent-cell pairs and triples), e.g. seed 1:
`spectral(ω=0.157) → sign%8==0 → cmp(high6,ident) → chi(0x07) → phi(0x18) →
phi(0x60) → cmp(high6,mod4) → phi(0x04) → phi(0x24) → phi(0x0C) → phi(0x30) →
phi(0x10)`. The monomial masks that eventually get selected (`0x18`=cells
{3,4}, `0x60`=cells {5,6}, `0x0C`=cells{2,3}, `0x30`=cells{4,5}) are literally
**adjacent-pair products** — the closest thing to "run structure" the
non-run menu has — and even feeding the search every one of them plus 8
non-adjacent aggregates still falls short of COVER.

**(2b) Dedicated library** (optimized to directly maximize R² of the raw
`maxRunGE3` statistic — the single most generous linear-reconstruction attempt
possible under this method): R² plateaus at **0.79–0.83** across seeds (never
near 1.0), and classifying Y with *that* library caps at 0.863–0.896 — no
better than the classify-optimized library. **Two independent generous
searches, optimizing two different objectives, converge on the same ceiling:
≈0.86–0.90 classification / ≈0.80 R², both short of exact.**

**Contrast with genuine redundancy** (Part 3, same K-budget class): the two
deliberately-constructed true-remix candidates and one accidental true-remix
discovery reach **cov_before ≥ 0.998 within 4–8 features** — not an asymptote,
a wall:

| target | K used | cov_before | R² | signature |
|---|---:|---:|---:|---|
| REMIX-A (`countAtLeast(g,2)`, thresh excluded) | 4 | 1.0000 | 0.754 | instant, exact |
| REMIX-B (`gridSum`, mono excluded) | 7 | 0.9983 | 0.962 | near-instant, exact |
| RUN-var3 (`firstDescentPos≥4`, accidental — see §4) | 8 | 1.0000 | 0.500 | instant, exact |
| **RUN1** (`maxRunGE3≥3`) | 12 | 0.887 (mean) | 0.73–0.77 | **asymptotic, never exact** |
| RUN-var2 (`maxRunGE2≥4`) | 12 | 0.868 | 0.722 | **asymptotic, never exact** |

**This is the decisive reconstruction test asked for in the design.** A
low-error reconstruction of RUN1 does **not** exist under any composition
tried — not the original ladder (cov≈0.79), not a 2× more thorough greedy
search over the whole menu (cov≈0.89), not a dedicated R²-maximizing search
(R²≈0.80, cov≈0.88). Genuine remixes, by contrast, resolve to cov≈1.000 with
a *quarter* to a *third* of the feature budget. The qualitative signature —
"reaches exactness fast" vs. "approaches a ceiling below the bar slowly" — is
real, measured, and cleanly separates the two classes in this experiment.

## 3. Threshold sweep / ROC (Part 3) — is R² even the right axis?

Nine targets, single seed, each tested with its own excluded-family library
(bitmask; **fixed two methodological leaks found while building this**: `mixr`
has direct raw access to `inversionCount` via its (sum,inv)/(count3,inv) pairs
— excluded alongside `cmp` for C09, or C09 spuriously "solves" to
cov_before=1.000/R²=1.000 through the back door; `thresh` directly exposes
`countAtLeast(g,4)` and `countAtLeast(g,1)` — RATIO1's own two ingredients —
excluded alongside `ratio`, or RATIO1 spuriously reconstructs to
cov_before=0.997. Both are documented in code comments as verified, not
assumed.):

| target | gt label | K | cov_before | R² | current gate (thr 0.40) |
|---|---|---:|---:|---:|---|
| RUN1 | *designed* novel | 8 | 0.882 | 0.730 | **reject (wrong — see §2)** |
| RUN-var2 | *designed* novel | 8 | 0.869 | 0.722 | **reject (wrong)** |
| RUN-var4 | *designed* novel | 8 | 0.695 | 0.278 | admit (correct) |
| C09 | *known* novel (family-level, Bayes ceiling ≈0.50) | 8 | 0.487 | −0.017 | admit (correct) |
| RATIO1 | *known* novel | 6 | 0.507 | −0.017 | admit (correct) |
| MIXMOD1 | *known* novel | 6 | 0.656 | 0.032 | admit (correct) |
| RUN-var3 | *turned out* remix (§4) | 8 | **1.000** | 0.500 | reject (correct, fragile) |
| REMIX-A | constructed remix | 4 | 1.000 | 0.754 | reject (correct) |
| REMIX-B | constructed remix | 7 | 0.998 | 0.962 | reject (correct) |

**Confusion table swept over R² thresholds (ground truth = cov_before ≥ COVER
from the generous per-target library above):**

| thr | TP (correct reject) | FP (false reject) | TN (correct admit) | FN (missed remix) |
|----:|---:|---:|---:|---:|
| 0.10 | 3 | 3 | 3 | 0 |
| 0.20 | 3 | 3 | 3 | 0 |
| 0.30 | 3 | 2 | 4 | 0 |
| **0.40 (current)** | **3** | **2** | **4** | **0** |
| 0.50 | 3 | 2 | 4 | 0 |
| 0.60 | 2 | 2 | 4 | 1 |
| 0.70 | 2 | 2 | 4 | 1 |
| 0.80 | 1 | 0 | 6 | 2 |
| 0.90 | 1 | 0 | 6 | 2 |

**At the current threshold (0.40): false-rejection rate = FP/(FP+TN) = 2/6 =
33% among genuinely-novel targets tested**, precision on "reject" calls =
3/5 = 60%, recall on true remixes = 3/3 = 100% (nothing genuinely redundant
ever gets admitted at this threshold — the danger runs entirely the other
way). **No threshold in [0.10, 0.90] achieves zero errors simultaneously**:
sorted R² values are `{C09:−.017, RATIO1:−.017, MIXMOD1:.032, var4:.278,
var3:.500, var2:.722, RUN1:.730, A:.754, B:.962}` — **RUN1 (irreducible) and
RUN-var2 (irreducible) both rank *above* RUN-var3 (exactly reconstructible)**.
Any threshold that admits RUN1/var2 (>0.73) also admits RUN-var3 (misses a
real remix); any threshold that catches RUN-var3 (≤0.50) also catches
RUN1/var2 (false-rejects two real escapes). **Pairwise ranking AUC (remix vs.
novel) = 16/18 = 0.889 — good but not 1.0, and the two inversions are exactly
the disputed pair.** This is not a threshold-tuning problem; it is an
axis problem — R² of the raw ident-lensed feature does not order candidates
by true reconstructibility.

**Design item 3's specific ask — a target in the 0.40–0.55 band with each
verdict:** satisfied on both sides. RUN-var3 (genuinely a remix) lands at
R²=0.500, correctly rejected but by a margin of only 0.10 above the gate —
one weaker seed draw could plausibly slip it under 0.40 and produce a real
missed-remix, given RUN-var3 was found by accident, not tuned to land there.
The **original production measurement of RUN1** (0.51–0.53, repr_expansion.md
§4) itself sits in exactly this band — a genuinely-novel target, falsely
rejected there. Both a correct and an incorrect verdict occupy the same
narrow R² neighborhood; the statistic cannot tell them apart from position
alone.

## 4. An accidental finding: RUN-var3 is a remix, not a novel target

RUN-var3 was designed as a fourth "adjacency, presumably novel" witness
alongside RUN1/var2/var4. It turned out **NOT** novel: `firstDescentPos(g)>=4`
means "no descent among the first 4 cells," which is **exactly**
`cmp(low6)==0` (zero inversions among all `C(4,2)=6` pairs on cells 0–3 is the
same event as a non-decreasing run of length 4) — an existing member of the
already-earned `cmp` family, an exact identity, not an approximation
(cov_before=1.0000 at K=8, confirmed). This is left in the writeup rather than
quietly dropped, for two reasons: (1) it is a real, useful negative — not
every "position/adjacency-flavored" target is outside the existing menu's
reach, `cmp`'s pairwise-comparison aggregates already span *some* adjacency
structure (specifically monotonicity of a prefix), just not *run-length*
specifically; (2) it is the single most important data point in the ROC
sweep — a genuine remix whose raw-feature R² (0.50) is **lower** than two
genuinely irreducible targets' R² (0.72, 0.73), which is the direct empirical
proof that the gate's axis is not monotonic in ground truth.

## 5. Corrected novelty measure

**Proposal:** replace `R²(candidate_raw, current_lib) < 0.40` with **"does a
generous multi-feature composition of the excluded-family menu already
classify the label to ≥ COVER (0.90)?"** — i.e., swap the statistic from
*linear reconstruction of the raw feature* to *classification-accuracy
reconstruction of the label*, reusing the certifier's own existing COVER
constant rather than introducing a new threshold. This mirrors the round-c /
`tier8_gate_v5.md` fix exactly in spirit (v3→v5-ladder replaced "can the
auditor's imagined basis reconstruct this" with "can the engine's own
expressible basis reconstruct this"; this fix replaces "does a raw continuous
statistic correlate linearly" with "can the actual downstream classification
task already be solved").

**Validated against all 9 targets — zero errors** (by construction, since
ground truth here *is* this statistic; the substantive claim is that it
recovers the same verdicts the field's careful family-level analysis already
established as correct — Bayes-ceiling-proven C09/RATIO1/MIXMOD1 novelty,
and the clean redundancy of REMIX-A/B — while additionally correcting the two
demonstrated false rejections):

| target | corrected verdict (cov_before < 0.90 ⇒ admit) | current R² gate | agree? |
|---|---|---|---|
| RUN1 | **admit** (0.882–0.901) | reject | **flips — the fix** |
| RUN-var2 | **admit** (0.869) | reject | **flips — the fix** |
| RUN-var4 | admit (0.695) | admit | agree |
| C09 | admit (0.487) | admit | agree |
| RATIO1 | admit (0.507) | admit | agree |
| MIXMOD1 | admit (0.656) | admit | agree |
| RUN-var3 | reject (1.000) | reject (fragile, §3) | agree, more robust |
| REMIX-A | reject (1.000) | reject | agree |
| REMIX-B | reject (0.998) | reject | agree |

Cost: one extra generous greedy search (≈8–12 rounds over the existing
non-candidate-family pool) per certify call instead of a single-shot linear
regression — more expensive than the current O(1) R² check, comparable in
spirit to the "greedy budget-8 logit fit" `tier8_gate_v5.md`'s v5-ladder
already pays per verdict. Not free, but bounded and already-precedented in
this codebase.

**Honest limits of the fix itself:** RUN1's own corrected cov_before (0.882–
0.901) sits close enough to COVER that a *stricter* corrected threshold (say,
admit only if cov_before < 0.85) would still reject it. The proposal's
robustness rests on using the **same** COVER=0.90 the escape condition
already uses (principled, not tuned to rescue RUN1), and on the fact that even
the single seed nominally over 0.90 (0.9011) is a 0.0011 margin under a
search-budget the production ladder never actually runs — production's own
ladder (≈5–6 features) gives cov≈0.79, unambiguously under 0.90 either way.

## 6. Verdict

**Is `run(maxRunGE3)` genuinely reconstructible from the count basis? No.**
Two independent generous searches (classify-optimized, R²-optimized), each
more thorough than production's actual ladder, plateau at cov≈0.86–0.90 /
R²≈0.80 — never at the "instant, exact" signature every confirmed true remix
in this experiment displays within a quarter of the same budget.

**Is the novelty gate correct to reject it? No — it is over-rejecting.** The
gate's chosen statistic (linear R² of the raw ident-lensed candidate feature)
is not a valid proxy for the thing the certifier actually cares about
(label-reconstructibility to the COVER bar). Measured false-rejection rate at
the production threshold: **2/6 (33%) among genuinely-novel targets tested**,
and the failure is not threshold-tuning-fixable — R² is demonstrably
non-monotonic in true novelty (AUC 0.889, with the two ranking inversions
being exactly RUN1 and RUN-var2, the disputed targets).

**Corrected measure:** generous multi-feature classification accuracy of the
excluded-family menu against the certifier's own COVER=0.90, in place of
single-column linear R² of the raw candidate. Recovers every established
correct verdict in this battery and additionally admits RUN1/RUN-var2.
Analogous in kind (wrong axis → right axis, not wrong threshold → right
threshold) to the `tier8_gate_v5.md` v3→v5-ladder fix from round c.

## 7. Honest scope / limitations

1. **Part 3+4 single-seed.** Cost-bounded scope decision (9 targets ×
   generous greedy search is the expensive part); Part 1+2's headline RUN1
   number is the properly-replicated 3-seed result and is the one load-bearing
   claim. The ROC/threshold table's N=9 is small; the qualitative finding
   (R² non-monotonicity, AUC<1, exact overlap at the disputed pair) is a
   real, reproducible, mechanistically-explained pattern, not a large-sample
   statistical claim.
2. **Greedy, not exhaustive.** Both reconstruction searches are forward
   greedy over a 241–266-column pool with early stopping (2 consecutive
   rounds of <0.001–0.002 improvement) — a strong, generous, but not
   provably-optimal search. A joint (non-greedy) combinatorial search over 12
   of 241 columns is combinatorially infeasible at this budget; greedy with a
   pool this size and this large a margin below COVER is treated as
   sufficient evidence of a real gap, not a formal impossibility proof (unlike
   C09/RATIO1/MIXMOD1, which additionally have an independent Bayes-ceiling
   proof from `repr_expansion.md` establishing genuine family-level
   unreachability).
3. **Pool composition is a design choice**, curated to ≈240–270 columns
   (monomial trimmed to singleton+pair+adjacent-triple+adjacent-quad masks
   rather than all 162 degree≤4 masks; walsh trimmed to 42 spread values;
   spectral/clifford/world trimmed) for a ≤15-minute, ≤2-thread budget. Two
   genuine cross-family information leaks were found and fixed during
   construction (`mixr`↔`cmp` share raw inversionCount; `thresh`↔`ratio` share
   raw threshold counts) — documented in code and in §3; no further leaks were
   found, but the pool was not exhaustively audited against every one of the
   36 pairwise family combinations.
4. **Epoch/lr budgets reduced from repr_expansion.zig's for the exploratory
   greedy screening rounds** (40 epochs classify-screen, 100 epochs
   regress-screen, vs. the original's 150/400) for tractability across
   thousands of trial fits; the **headline reported numbers** (cov_before,
   cov_after, final R²) use a heavier refit at repr_expansion.zig's original
   hyperparameters (150 epochs/lr=0.05 classify, 400 epochs/lr=0.01 regress)
   on the concluded chosen library, matching original convention.
5. **RUN-var3's mislabel (§4) was discovered, not engineered** — an honest
   byproduct of testing the design, kept in the writeup rather than quietly
   replaced, because it turned out to be the single most useful data point.
6. **The corrected-measure validation (§5) is partly definitional** (ground
   truth in the ROC table is itself "generous cov_before ≥ COVER"), so its
   "zero errors" is not independent proof of correctness by itself — the
   independent evidence is that (a) it reproduces the Bayes-ceiling-backed
   verdicts for C09/RATIO1/MIXMOD1 established in `repr_expansion.md` through
   a completely different mechanism, and (b) production's own actual ladder
   (not this experiment's generous search) already shows cov≈0.79 for RUN1,
   unambiguously below COVER regardless of exactly how generous "generous" is
   defined.
7. **Uniform-iid 8-cell 0..5 grid**, as every Tier-8 measurement in this
   research line.

## Files

- Harness: `sparse_poly_discovery/run1_gate_audit.zig` (`--diag` = fast
  1-seed/small-K smoke test, ~34 s; full run = 3 seeds Part 1+2 + 1 seed
  Part 3+4, ~137 s).
- Data: `results/run1_gate_audit_2026_07_11.csv` (114 data rows: 3
  base_rate + 72 greedy_trace [2 attacks × 12 rounds × 3 seeds] + 12
  gate_repro [4 metrics × 3 seeds] + 9 roc + 9 roc_r2 + 9 threshold_scan).
- Read-only reference (not imported, transcribed): `sparse_poly_discovery/
  repr_expansion.zig` (RUN1's definition, `maxRunGE`/`labelRun1`, the
  `certifyLocal` novelty-gate mechanism this audit disputes).
- Related docs: `docs/research/repr_expansion.md` (E1, where the RUN1
  certifier-boundary finding originates — §4 "RUN1 — a certifier boundary,
  not a family boundary"), `docs/research/tier8_gate_v5.md` (round c's
  analogous gate-mechanism audit and fix, the design template this experiment
  follows), `docs/research/tier8_reach_gap.md` (the Bayes-ceiling method used
  to independently validate C09/RATIO1/MIXMOD1's novelty here).
