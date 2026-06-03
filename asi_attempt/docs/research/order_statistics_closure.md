# A New Closure Split: Extremal vs. Central Order Statistics

**Status:** NEW research (not a re-run). One conjecture confirmed decisively, two
hypotheses refuted. Reproduce: `zig build order-stats`

## The Question (genuinely open in advance)

`concentration_control.md` proved an EXTREMAL order statistic (`max`) is outside every
finite polynomial closure, but **one** `max` feature crosses it — because
`max = lim_{p→+∞}` of the power mean, and `min = lim_{p→−∞}`. Both extremes are
soft-extreme limits, each "1-feature simple."

The **median** is different in kind: it is **not** a power-mean limit in any direction —
it is a *central / rank* statistic. So:

> Is the median outside the closure of `{low-degree polynomial + max + min}`? I.e., do the
> extremal features that crossed the polynomial→max boundary help reach a central one?

Answer was unknown to me before running it.

## Method

Decisive-probe style. Build a balanced dataset of states (16 cells, fixed total sum) whose
median is above vs. below a threshold, where the candidate "should-be-blind" features are
matched EXACTLY between the two classes via an integer-key bin-merge (the merge also
**balances** classes within each key, so chance = 0.500 exactly). Train logistic regression
over several bases on held-out data.

## Result 1 — The median is NOT reducible to {poly2 + max + min}  (CONJECTURE CONFIRMED)

Matched: sum (fixed), `Σx²`, `max`, `min`. **n = 59,170** balanced samples.
```
  basis                    | held-out accuracy
  poly2                    | 0.497
  poly2 + max + min        | 0.496   <-- extremal features give NOTHING
  poly2 + median           | 1.000
  poly2 + max + min + med  | 1.000
```
With sum, `Σx²`, `max`, `min` all matched, any function of `{poly≤2, max, min}` is identical
across classes → provably chance, and the held-out 0.496 confirms it (no coordinate
leakage). Only the explicit rank feature crosses it.

## Result 2 — Degree-general: still chance at degree 3 with both extremes  (CONFIRMED)

Match `p1, p2, p3` AND `max` AND `min` (minimal symmetric power-sum basis). **n = 31,118.**
```
  [1,p1,p2,p3]             | 0.500
  [1,p1,p2,p3] + max + min | 0.500   <-- extremes give nothing at degree 3 either
  [1,p1,p2,p3] + median    | 1.000
```
So the median is outside `{degree-≤3 symmetric polynomial + max + min}`, not just degree 2.

**This establishes a new split in the closure lattice:**
- **Extremal** order statistics (`max`, `min`): power-mean limits, each one feature.
- **Central / rank** order statistics (`median`): NOT reachable from polynomial + the
  extremes; they require genuine rank information.

## Result 3 — The split is BINARY, not graded  (my "smooth gradient" hypothesis REFUTED)

I expected near-extremal ranks (2nd largest) to be *easier* for `{poly2+max+min}` than the
median — a smooth rank-complexity gradient. Matching `(p1,p2,p3,max,min)` and classifying
the k-th largest:
```
  k-th largest |  {poly2+max+min} held-out acc
     2 (2nd)   | 0.503
     3         | 0.506
     4         | 0.498
     5         | 0.492
     6         | 0.500
     7         | 0.498
     8 (median)| 0.494
```
**Every interior rank is at chance.** The 2nd-largest is *already* as unreachable as the
median. Given the polynomial moments, the closure `{poly + max + min}` contains the literal
extremes and **nothing else of the rank structure**. The result is binary (extremes vs. all
interior), not a gradient. Hypothesis refuted; the truth is sharper.

## Result 4 — Is rank-complexity graded in DEGREE? (hypothesis NOT cleanly supported)

The fixed-basis spectrum (Result 3) cannot see a *degree* gradient. So: predict the k-th
largest from a degree-d power-sum basis `[1,p1..pd]` (sum fixed, classes balanced, NO other
matching). `deg1` uses only the fixed sum → 0.500 for all k (baseline confirmed clean).
```
  k (rank) |  deg1 |  deg2 |  deg3
     1 (max)| 0.500 | 0.696 | 0.886
     2      | 0.500 | 0.765 | 0.756
     3      | 0.500 | 0.592 | 0.550
     4      | 0.500 | 0.617 | 0.706
     6      | 0.500 | 0.500 | 0.666
     8 (med)| 0.500 | 0.587 | 0.753
```
**Non-monotonic.** The max is the most degree-responsive (0.50→0.89), consistent with "high
moments pin the max." But interior/central ranks do NOT show a clean "more central ⇒ needs
higher degree" pattern (k=3 is the worst-predicted; the median at deg3 beats k=3 and k=6).
So the graded-degree law is **not cleanly supported** here — predictability of a rank from
low moments is governed by messier threshold/distribution interactions than a simple
centrality order. Honest negative; the open question (a clean rank×degree law) is not
resolved by this construction.

## Honest Grade

- **Strong, clean, new:** the median (and every interior rank) is outside
  `{degree-≤3 polynomial + max + min}` — a genuinely new extremal-vs-central closure split,
  decisive at n≈30–60k with exact moment+extreme matching and held-out chance = 0.500.
- **Two of my hypotheses died on contact with data** (the smooth rank gradient; the clean
  graded-degree law). That is the point of the exercise — propose, then try to break it.
- **Caveat:** the explicit rank feature scoring 1.000 is expected (the feature is the label
  threshold); the load-bearing result is that the extremal features score *chance*. And the
  claim is scoped to low polynomial degree + the literal extremes; with enough moments
  (`p1..p_N`) the full sorted vector — hence any rank — is recoverable.

## Why It Matters

The closure principle is the project's spine: behaviours live inside a closure, and crossing
a boundary needs a generator that adds the missing structure. This maps a previously
uncharted region of that lattice: order statistics are not one homogeneous "non-polynomial"
blob. The **extremes** are a thin, cheap shell (one soft-extreme limit each); the **interior
ranks** are collectively a separate, richer stratum that the extremes do not touch. Any
"invent the feature you need" system must treat central/rank quantities as a distinct
primitive class, not as something reachable by sharpening a max.

See: `concentration_control.md` (the max boundary), `representation_discovery.md`
(learning the extremal rung), repo-root `CLOSURE_PRINCIPLE.md`.
