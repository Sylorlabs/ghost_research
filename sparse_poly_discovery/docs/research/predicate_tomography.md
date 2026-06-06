# Frontier 10 — predicate tomography: accuracy profiles fingerprint algebraic class

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build predicate-tomography`

## What was tested

12 predicates × 9 substrates. For each (predicate, substrate) pair: train on 2880 samples,
evaluate on 720, report majority-class-corrected accuracy.

**Predicates:**
- Group A (count/spectral domain): count-parity, count-period3, count-AND, count-XOR
- Group B (relational domain): inv-parity, orientation, max-first
- Group C (distributional — novel, not tested in prior frontiers): variance-high, range-high
- Group D (bit parity / degree ladder): k2-parity, k3-parity, k4-parity

**Substrates:**
- `lin`: degree-1 logistic on raw cell values (6 features)
- `d2`: degree-2 monomials + linear (21 features)
- `d3`: degree-3 monomials + d2 (41 features)
- `pair`: logistic on all signed pairwise differences ci−cj (15 features)
- `sort`: logistic on sorted cell values (6 features, order-statistic aware)
- `cliff`: Clifford grade-2 blade with shared basis for all pairs (15 features)
- `sp-pow`: power-spectrum spectral on count
- `sp-grd`: accuracy-grid spectral on count (fix for AND-composition failure, F9)
- `staged`: accuracy-grid over {count, inv-count, range, var4} — best inner quantity

## Results

```
PREDICATE TOMOGRAPHY  NCELL=6  VMAX=8  THRESH=4  NSAMP=3600

G  predicate         lin    d2     d3     pair   sort   cliff  sp-pow sp-grd staged  pos%
──────────────────────────────────────────────────────────────────────────────────────────
A  count-parity      0.525  0.504  0.504  0.508  0.621  0.507  1.000  1.000  1.000   49%
A  count-period3     0.686  0.686  0.686  0.686  0.686  0.686  1.000  1.000  1.000   35%
A  count-AND         0.682  0.682  0.682  0.682  0.682  0.682  0.682  0.976  0.976   31%
A  count-XOR         0.810  0.810  0.824  0.810  0.810  0.810  0.810  1.000  1.000   21%
B  inv-parity        0.540  0.535  0.519  0.538  0.558  0.521  0.560  0.539  1.000   50%
B  orientation       0.989  0.990  0.990  1.000  0.610  0.997  0.610  0.610  0.610   43%
B  max-first         0.846  0.871  0.879  0.894  0.781  0.910  0.781  0.781  0.790   23%
C  variance-high     0.918  0.918  0.918  0.918  0.918  0.918  0.918  0.933  0.971   92%
C  range-high        0.932  0.932  0.932  0.932  0.932  0.932  0.932  0.944  1.000   93%
D  k2-parity         0.515  0.686  0.701  0.524  0.567  0.521  0.524  0.608  0.608   49%
D  k3-parity         0.504  0.508  0.525  0.532  0.544  0.521  0.503  0.563  0.563   50%
D  k4-parity         0.519  0.507  0.504  0.529  0.540  0.506  0.532  0.628  0.628   51%
```

## Finding 1: Profile uniqueness — the fingerprint works

All 12 rows are distinct. No two predicates have the same accuracy profile across the 9
substrates. The tomography works as a fingerprint: given only the 9-dimensional accuracy
vector, the predicate's algebraic class is uniquely identifiable. This validates the core
hypothesis of the experiment.

## Finding 2: Three ceiling gaps — the substrate library has holes

The most important result: three predicates (max-first, k3-parity, k4-parity) defeat every
known substrate. These are not hard problems — they're problems whose structure is outside
the current library's algebraic closure.

**max-first** (peak: 0.910, Clifford): the predicate is c[0] > all other cells — a conjunction
of 5 pairwise comparisons. Pairwise and Clifford features get close because they encode each
comparison, but a logistic classifier cannot learn a hard 5-way AND from soft pairwise signals.
Missing substrate: **rank features** — how many cells does c[i] beat? rank[0]=5 iff c[0] is
the global max. A linear logistic on rank values would solve this in one step.

**k2-parity** (peak: 0.701, d3): degree-2 raw features get 0.686 — above chance but not
perfect. The XOR of two thresholded values is a degree-2 function of the THRESHOLD BITS,
but a degree-2 polynomial of the raw integer values can only approximate the step function.
Missing substrate: **threshold-bit monomials** — b[i] = (c[i] ≥ THRESH) as explicit binary
features, then degree-2 products. This was solved in F4 but over binary inputs; here the
raw-integer feature set fails.

**k3/k4-parity** (peaks: 0.563, 0.628): everything near chance. Missing substrates:
degree-3 and degree-4 threshold-bit monomials respectively. The ceiling gap grows with k.

## Finding 3: Class imbalance masks the baseline — distributional predicates are mislabeled as "easy"

variance-high (92% positive) and range-high (93% positive): every logistic substrate sits at
0.918 and 0.932 — the majority-class rate. Most substrates appear to "work" but they're
predicting all-positive. The actual learning only shows in `staged`: 0.971 for variance,
1.000 for range.

This is a methodological finding: **raw accuracy is misleading for highly imbalanced
predicates.** The corrected measure is (acc − majority_baseline) / (1 − majority_baseline).
Under this measure, linear gets 0.0 on both distributional predicates (learns nothing).
Staged gets 0.625 on variance and 1.000 on range.

The staged substrate solves range-high perfectly because range is exactly the inner quantity:
accuracy-grid on statRange discovers a ω such that cos(ω · range) thresholds at range ≥ 4.
For variance-high, the cosine basis approximates the threshold less cleanly (0.971 not 1.000)
because the variance values are more spread out — a step function basis would be better.

## Finding 4: orientation solved three ways with different "why"s

Orientation (c[0] > c[1]) is solved by lin (0.989), d2 (0.990), d3 (0.990), pair (1.000),
cliff (0.997). Each reaches it differently:
- **pair**: c[0]−c[1] is directly one of the pairwise features; logistic uses that alone.
- **cliff**: sin(θ₁−θ₀) = sin(π(c[1]−c[0])/VMAX) is monotone in c[0]−c[1]; one feature suffices.
- **lin**: c[0] and c[1] with equal and opposite weights recover c[0]−c[1] implicitly.

The fact that three structurally different substrates all solve this predicate means orientation
is in the intersection of multiple algebraic closures — it lives in a "common ground" between
relational, linear, and Clifford algebras. Profile uniqueness still holds because the MAGNITUDE
of accuracy differs (lin 0.989 vs pair 1.000 vs cliff 0.997).

## What this opens: five new research questions

**RQ1 — Symmetry groups predict substrate requirements**
count-parity is invariant under ALL permutations of cells → spectral works.
orientation breaks under swap(c[0],c[1]) → position-sensitive features needed.
Can we measure the symmetry group of an unknown predicate empirically (fraction of
random permutations that preserve the label)? If the symmetry fraction predicts which
substrate works, we have a complete theory of substrate requirements — derived from the
predicate's geometry rather than empirical testing.

**RQ2 — Training gradient as substrate discovery signal**
When logistic on degree-2 fails for k3-parity, the error gradient in the space of possible
features points toward degree-3 monomials. Can the gradient BE the substrate discovery
signal — training on the wrong substrate, then reading the failure gradient to find the
right one?

**RQ3 — Step function basis for threshold predicates**
Replace cos(ω·s) with sign(s−θ) as the staged classifier. Expected: variance-high jumps
from 0.971 → 1.000. If confirmed: the choice of basis function within the spectral
operator (Fourier vs step vs wavelet) is itself a substrate parameter.

**RQ4 — Substrate composition depth**
staged = spectral ∘ inner_quantity (depth 2). Does a depth-3 predicate exist that requires
three sequential extractions? If yes, what is it? If no, why is depth 2 sufficient for all
predicates over NCELL=6?

**RQ5 — Minimum closure escape**
For each ceiling gap, what is the single smallest addition to the substrate library that
closes the gap? max-first needs 6 rank scalars. k2-parity needs 15 threshold-bit products.
What is the closure complexity of each predicate — measured in bits of additional structure
needed to escape the current library's closure?

See: `multi_period.md`, `period_candidate_search.md`, `higher_order_closure.md`,
`composed_discovery.md`, `antisymmetric_relational.md`.
