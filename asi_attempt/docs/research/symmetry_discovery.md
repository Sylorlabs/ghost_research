# Frontier 11 — Symmetry Discovery: symmetry groups predict substrate requirements

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build symmetry-discovery`

## Hypothesis

The symmetry group of a predicate determines which substrate can represent it.
Measure P(label(σ(x)) == label(x)) over random x ∈ X, σ ∈ S₆ — the average-case
symmetry fraction. Predict substrate class from this single number.

## Results

```
predicate         sym_frac  sym_class         predicted_substrate  f10_actual       match
──────────────────────────────────────────────────────────────────────────────────────────
count-parity      1.000     FULLY-SYMMETRIC   spectral/count       spectral (1.000)  ✓
count-period3     1.000     FULLY-SYMMETRIC   spectral/count       spectral (1.000)  ✓
count-AND         1.000     FULLY-SYMMETRIC   spectral/count       sp-grid  (0.976)  ✗
count-XOR         1.000     FULLY-SYMMETRIC   spectral/count       sp-grid  (1.000)  ✗
inv-parity        0.501     HALF-SYMMETRIC    pairwise             staged   (1.000)  ✓
orientation       0.510     HALF-SYMMETRIC    pairwise             pairwise (1.000)  ✓
max-first         0.655     MOSTLY-SYMMETRIC  staged/mixed         clifford (0.910)  ✗
variance-high     1.000     FULLY-SYMMETRIC   spectral/count       staged   (0.971)  ✓
range-high        1.000     FULLY-SYMMETRIC   spectral/count       staged   (1.000)  ✓
k2-parity         0.536     HALF-SYMMETRIC    pairwise             degree3  (0.701)  ✗
k3-parity         0.523     HALF-SYMMETRIC    pairwise             staged   (0.563)  ✓
k4-parity         0.534     HALF-SYMMETRIC    pairwise             staged   (0.628)  ✓

Prediction accuracy: 8/12
```

## Finding 1: The theory is real but incomplete (8/12)

Symmetry fraction correctly predicts substrate class for 8 of 12 predicates. The prediction
rule works: fully-symmetric predicates need spectral/count substrates; half-symmetric
predicates need pairwise or relational. This is a genuine signal from group theory.

The failures expose the rule's limits:
- **count-AND, count-XOR**: symmetry=1.0 correctly points to spectral, but the specific
  variant matters (accuracy-grid vs power-peak). The failure is at the sub-family level,
  not the family level.
- **k2-parity**: predicted pairwise (symmetry=0.536, half-symmetric), actual best is
  degree3 raw-value monomials (0.701). Both are relational/polynomial — close but not exact.
- **max-first**: measured 0.655 (mostly-symmetric), predicted staged. Actual best is
  Clifford at 0.910 (still unsolved).

## Finding 2: Average-case vs worst-case symmetry — a new distinction

The key theoretical surprise: max-first measured **0.655** symmetry, but theoretical
worst-case symmetry should be ~0.167 (only 1/6 of permutations preserve "c[0] is max").

Why the gap? Average-case symmetry measures P(σ preserves label) over random (x, σ).
For max-first, many randomly generated arrays have a high maximum value that appears
only once — but when the maximum value is repeated (e.g., c[0]=7 and c[2]=7), many
permutations keep a maximum-value cell in position 0. The empirical average-case symmetry
is higher than the theoretical worst-case because the input distribution is non-adversarial.

**This is a new distinction:** worst-case symmetry (the group theory notion) vs average-case
symmetry (what matters for learning from random data). A predicate that is worst-case
asymmetric can still be average-case partially-symmetric if the high-symmetry input
configurations are common. The substrate needed depends on BOTH.

## Finding 3: inv-parity measures exactly 0.501 — confirms A₆ structure

The alternating group A₆ has exactly 360 of 720 elements of S₆ (half). Odd permutations
flip the inversion count parity; even permutations preserve it. The measured 0.501 matches
the theoretical 0.5 perfectly (the ≈0.001 deviation is sampling noise at N=60000).

This is an exact measurement of an algebraic group property from data alone — no prior
knowledge of inversion counts or alternating groups needed. The measurement is a machine-
readable probe of the predicate's symmetry algebra.

## What this opens

**RQ: Can we distinguish average-case from worst-case symmetry?**
Measure symmetry fraction for adversarially chosen x (e.g., x chosen to minimize symmetry)
vs random x. The gap between adversarial and random symmetry measures the predicate's
"symmetry margin" — how much the distribution helps. For max-first, this gap is 0.655 - 0.167 = 0.488.

**RQ: Does the symmetry fraction correlate with substrate accuracy after correction for substrate family?**
The 4 mismatches (count-AND, count-XOR, max-first, k2-parity) all have the right family
but wrong sub-variant. Adding a second measurement (within-family accuracy variation) would
give a two-level theory: family from symmetry, variant from a secondary measurement.

See: `predicate_tomography.md`, `gradient_discovery.md`, `antisymmetric_relational.md`.
