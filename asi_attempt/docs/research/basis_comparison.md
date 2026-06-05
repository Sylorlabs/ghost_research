# Frontier 13 — Basis Comparison: cosine vs step vs square-wave vs dual

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build basis-comparison`

## Hypothesis

The spectral operator uses cos(ω·s) as its classifier basis. This is optimal for
PERIODIC predicates but wrong for THRESHOLD predicates. A step function sign(s−θ)
should be optimal for threshold predicates. A dual basis (cos AND/OR step) should
handle mixed predicates like count-AND (sparse periodic).

## Bases tested

- **cos**: cos(ω·s), frequency ω optimized by accuracy-grid over training set
- **step**: sign(s−θ), threshold θ optimized by grid search
- **sqwave**: square-wave — hard-thresholded cosine: +1 in [0,π/ω), −1 in [π/ω, 2π/ω)
- **dual**: majority vote: cos(ω·s)≥0 AND s≥θ, or cos(ω·s)≥0 OR s≥θ (best mode chosen)

## Key results

```
predicate       best inner stat + basis   accuracy    vs F10 staged
────────────────────────────────────────────────────────────────────
count-parity    count + cos               1.000       same
count-period3   count + cos               1.000       same
count-AND       count + dual(AND)         1.000       +0.024
count-XOR       count + cos               1.000       same
inv-parity      inv   + cos               1.000       same
variance-high   var4  + step              1.000       +0.029 ← CLOSES GAP
range-high      range + (any)             1.000       same
k2-parity       inv   + dual(OR)          0.640       n/a (still incomplete)
```

## Finding 1: Step function closes variance-high from 0.971 → 1.000

This was the remaining ceiling gap from F10. var4 + cos gave 0.921 (majority class).
var4 + step gives **1.000**. The step function sign(var4 − θ) with optimal θ perfectly
thresholds variance at the boundary. The cosine basis cos(ω·var4) oscillates and can
only approximate a threshold — the step function is the algebraically correct basis here.

This confirms the hypothesis: **the basis function is itself a substrate choice.** The
spectral operator with cos is closed over periodic functions; extending it with a step
function escapes this closure for threshold predicates.

## Finding 2: Dual basis (cos AND step) solves count-AND to 1.000

count-AND was the failure case from F7/F9 that required accuracy-grid to reach 0.976.
The dual basis count+dual(AND) gives **1.000** — the missing ingredient.

Why AND logic: count-AND = (count mod 2 == 1) AND (count mod 3 == 0). The cosine
cos(π/3·count) encodes the period-6 structure. The step θ captures the rarity (positive
class only when count ≡ 0 mod 6, i.e., count is small). The AND of these two conditions
perfectly characterizes the AND-composition predicate.

This is the most surprising result: the dual basis doesn't just improve over the individual
bases — it COMBINES their information in a way that neither can achieve alone, without any
additional learning. The AND logic between cosine and step is a hard-coded algebraic
combination that maps directly onto the predicate's compositional structure.

## Finding 3: The basis × inner-quantity interaction is the real discovery

The full picture:

```
predicate type    best inner stat   best basis   why
─────────────────────────────────────────────────────────────────────
periodic          count             cos          Fourier basis matches periodic structure
periodic-sparse   count             dual (AND)   periodicity + rarity both matter
periodic-XOR      count             cos          XOR creates balanced period, cos sufficient
threshold         var4 or range     step         step function = exact threshold
composed          inv               cos          inv-count periodic under inversions
k-parity          (none work)       (any)        inner-quantity search doesn't help for parity
```

The finding: the PAIR (inner quantity, basis) is what matters — neither alone is sufficient.
The tomography (F10) tested fixed inner quantities with the accuracy-grid (cos basis only).
This experiment reveals that swapping the basis within the same inner quantity can close
gaps that the basis grid-search missed.

## Finding 4: Square-wave basis is a curiosity, not a winner

The square-wave (hard-thresholded cosine) matches or ties cos on most predicates but
never beats the dual. It's the midpoint between cos and step: it has periodicity but
hard boundaries. For periodic predicates where the soft cosine is already optimal, the
hard thresholding doesn't help. It's never the unique winner.

## The revised spectral operator

The results suggest a generalized staged operator:

```
STAGED_DUAL(x, pred):
  for each inner_stat in {count, inv, range, var4}:
    for each basis in {cos, step, dual_AND, dual_OR}:
      train basis(stat(x)) on training data
      score on validation set
  return best (inner_stat, basis) pair
```

This replaces the original staged operator's fixed cos basis with a search over basis
functions. F10's staged score of 0.971 for variance-high becomes 1.000 with this extension.
The only remaining ceiling gaps are the k-parity predicates, which require degree-k
threshold-bit features — no inner-quantity approach will close them.

## What this opens

**The basis zoo**: cos, step, dual are three members of a larger family. Others:
- **wavelet**: localized periodic basis for predicates with varying periodicity
- **polynomial step**: sign(s² − θ·s + c) — a quadratic decision boundary on the statistic
- **logistic threshold**: sigmoid(α·(s−θ)) — soft step with learned sharpness

**Automatic basis selection**: given any inner quantity statistic, the dual basis
(cos AND step, optimized over ω and θ) is a strong universal default. It subsumes pure
cos (when step becomes redundant) and pure step (when cos becomes redundant), with no
additional learning complexity beyond the 2-parameter grid search.

See: `period_candidate_search.md`, `predicate_tomography.md`, `gradient_discovery.md`.
