# Prospective Controller Disagreement

**Status:** built, measured, partial positive. Reproduce: `zig build parallel-disagree`

## Setup

Run N single-feature ScalarControllers simultaneously on the same environment.
The primary controller (sum) picks the actual action. All controllers observe
the outcome and update their models.

At each step: count how often each controller's recommended action DIFFERS from
the primary (sum) controller's choice.

**Hypothesis**: the feature-controller that most often contradicts the primary is
tracking a constraint the primary misses — best candidate to add as second feature.

This is PROSPECTIVE (forward-looking action disagreement) vs the RETROSPECTIVE
(backward-looking failure correlation) approach tested in `correlation_feature_discovery.md`.

---

## Results (8000 steps × 8 seeds on DUAL_BAND)

```
  feature        | disagree_rate | fail/1k (under sum policy)
  ---------------+---------------+---------------------------
  nonzero_count  |         0.577 | 53.11   ← TOP by disagreement
  max_cell       |         0.422 | 53.11   ← #2
  right_mass     |         0.422 | 53.11
  left_mass      |         0.417 | 53.11
  sum            |         0.000 | 53.11
```

---

## Comparison with Retrospective Correlation

```
  Method                | Top-1         | Top-2         | max_cell rank
  ----------------------+---------------+---------------+--------------
  Retrospective (corr.) | nonzero_count | left_mass     | #3
  Prospective (disagree)| nonzero_count | max_cell      | #2
```

Prospective disagreement is BETTER than retrospective correlation at identifying
max_cell: it moves max_cell from #3 to #2 in the ranking.

**Why**: max_cell's controller recommends discharge/rest when max_cell is elevated,
but sum's controller may recommend charge when sum is low. This forward-looking
tension (controllers disagree before any failure occurs) correctly flags max_cell
as tracking something the sum controller misses.

Retrospective correlation missed max_cell because max_cell is never OOR at failure
time (it prevents failures proactively). Prospective disagreement detects max_cell
because it observes max_cell's controller contradicting sum's controller in real time.

---

## The Volatility Problem

nonzero_count still tops the ranking at 0.577 despite being the WORST control feature
(499.98 fail/1k in the main eval, 296.00 fail/1k in single-feature probe). Why?

nonzero_count changes dramatically with every action:
- charge: adds ions, makes more cells non-zero → nonzero_count up
- discharge: drains cells to 0 → nonzero_count down
- rest: cells decay to 0 → nonzero_count down

High volatility = the nonzero_count controller frequently recommends different
actions from sum's controller simply because it's tracking a noisier signal.
The disagreement is not due to detecting a real constraint tension — it's noise.

**The fix**: normalize disagreement by feature volatility (variance in feature value
per unit action). A feature with high volatility needs high raw disagreement to
show a meaningful signal. Normalized disagreement = disagreement / volatility.

With normalization:
- nonzero_count would drop (high raw disagree, high volatility → low normalized)
- max_cell might rise (moderate raw disagree, low volatility → higher normalized)
- left_mass should remain high (direct constraint, clear tension with sum)

---

## Honest Grade

Partial positive: prospective disagreement IMPROVES on retrospective correlation
by correctly moving max_cell to #2. But it can't cleanly identify the right pair
because feature volatility conflates "contradicting due to constraint tension" with
"contradicting due to noise."

The approach is directionally correct: looking at forward-facing action contradictions
is better than looking at backward-facing failure correlations. But it needs
volatility normalization to be clean.

See: `correlation_feature_discovery.md`, `pair_feature_control.md`.
