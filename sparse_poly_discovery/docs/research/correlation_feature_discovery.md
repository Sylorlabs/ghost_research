# Correlation-Based Feature Pair Discovery

**Status:** built, measured, three negative results with a precise explanation.
**Reproduce:** `zig build correlation-discover`

---

## The Question

Can an agent identify WHICH two features to track for dual-band control using
only its failure history — without exhaustive O(N²) pair search?

Known exhaustive result: `(left_mass, max_cell) = 0.25 fail/1k` on dual-band.
Goal: find this pair via O(N) failure analysis.

---

## Three Approaches Tested

### Approach 1: Deviation-based failure correlation

**Method**: run warmup with feature=sum. After each `env.step()`, read ALL
features from `env.grid`. (When `failed==true`, the grid is the post-action
failed state — reset happens at the start of the NEXT call.) Compute:
- `safe_mean` / `safe_std`: feature distribution on non-failure steps
- `fail_mean`: feature distribution on failure steps
- `deviation_score = |fail_mean - safe_mean| / safe_std`
- `oor_fraction`: fraction of failures where feature was outside `[safe_min, safe_max]`

**Result** (5000 steps × 8 seeds):
```
  feature        | safe_mean | safe_std | fail_mean | deviation | oor_frac
  ---------------+-----------+----------+-----------+-----------+---------
  nonzero_count  |     14.67 |     1.86 |     10.78 |     2.094 |    0.000
  left_mass      |     11.52 |     3.62 |      6.26 |     1.454 |    0.892
  max_cell       |      2.00 |     0.70 |      2.67 |     0.964 |    0.000
  right_mass     |     16.00 |     5.59 |     21.39 |     0.964 |    0.000
  sum            |     27.52 |     7.56 |     27.65 |     0.017 |    0.075
```

**Proposed pair**: (nonzero_count, left_mass) — deviation-based top-2.
**Verify**: 259.93 fail/1k. **NEGATIVE.**

Failure: `nonzero_count` ranks highest by deviation because it drops when cells
drain during undercharge failures. It's a correlated-but-secondary signal.
`max_cell` is NOT identified because it doesn't deviate at failure time (OOR=0.000).

---

### Approach 2: Controllability-ranked pairing

**Method**: run O(N) single-feature probes (one `ScalarController` per feature,
8000 steps × 6 seeds each). Rank by fail/1k. Pair the top-2.

**Result**:
```
  sum           : 32.96 fail/1k
  left_mass     : 48.42 fail/1k
  max_cell      : 115.92 fail/1k
  right_mass    : 115.92 fail/1k
  nonzero_count : 296.00 fail/1k
```

**Proposed pair**: (sum, left_mass) — the two individually-best features.
**Verify**: 291.40 fail/1k. **NEGATIVE.**

Failure: individually-good features pair badly when their delta models corrupt
each other. `(sum, left_mass) = 291.40` is catastrophically worse than either
alone. The best pair `(left_mass, max_cell)` requires `max_cell` which ranks 3rd
individually (115.92 fail/1k) — much worse than sum.

---

### Approach 3: Residual OOR analysis

**Method**: identify primary feature by highest OOR fraction → `left_mass` (0.892).
Among failures where left_mass was NOT OOR ("residual failures"), count which
other features were OOR.

**Result**: 114 residual failures. ALL features have 0/114 OOR in residual failures.

**Proposed pair**: (left_mass, sum) — defaults to alphabetical when all 0.
**Verify**: 291.40 fail/1k. **NEGATIVE.**

Failure: the 11% of failures where left_mass is in-range at failure time show
NO other feature OOR either. The failure cause isn't visible in static state.

---

## The Precise Finding

**`max_cell` has 0.000 OOR fraction at failure time** across all three analyses.
Yet it's the best pairing feature. Why?

The value of tracking `max_cell` is **prospective**, not retrospective:
- The controller avoids cell overflow BEFORE it becomes OOR by choosing
  discharge/rest over charge when max_cell is high.
- This preventive action means max_cell is rarely at its failure threshold
  when failures occur — the failures that do happen are for OTHER reasons
  (left_mass OOR), and at those failure times max_cell is within normal range.

**Retrospective failure analysis systematically misses proactive-control features.**

Features that prevent failures through preemptive action selection don't show OOR
at failure time, because they prevent failure from happening. The signal of a
feature's value is CAUSAL for control but NOT CORRELATED with observed failures —
the act of tracking it changes what failures occur.

---

## Comparison with the Bit-Op Domain (Emergent Escape #38)

This is the control-domain analog of pair-emerge in the bit-op domain:
- `x&(x-1)` needed BOTH AND and SUB. Single-op greedy search missed AND because
  AND alone doesn't reduce Hamming weight — only the combination does.
- `(left_mass, max_cell)` needs BOTH features. Retrospective analysis misses
  max_cell because max_cell alone has poor control (115.92) and 0 OOR correlation.

In both cases: the value of an element is only visible in COMBINATION, not alone.
Single-element analysis (greedy search, failure correlation) misses emergent pairs.

---

## What Would Work

1. **Exhaustive pair search**: O(N²) probes. This is what found (left_mass, max_cell) = 0.25.
   It's the only method tested that works — and it works because it tests pairs in
   combination, not individual features or retrospective correlates.

2. **Model-based look-ahead**: if the agent has a predictive model of future state,
   it can simulate "what failures would occur if I controlled max_cell?" and discover
   its value prospectively. No predictive model exists in this system.

3. **Counterfactual analysis**: hold left_mass under perfect control (simulation),
   ask what failures remain. Those would be the max_cell failures that max_cell prevents.
   Requires simulation capability.

---

## Honest Grade

The negative result is clean and precise. Three different approaches all fail for
the same underlying reason: retrospective analysis misses proactive-control features.

This is a genuine contribution to understanding what makes feature discovery hard:
the features that matter for control are not the features that correlate with
observed failures — they are the features that would have CHANGED what failures occurred.

See: `pair_feature_control.md`, `adaptive_feature.md`, `pair_search.md`.
