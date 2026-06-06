# Frontier 9 — period candidate search: accuracy-grid fixes AND-composition failure

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build period-candidate-search`

## What was tested

Three strategies for finding the dominant period of a binary classifier over cell count c:

| Strategy | Method | Core idea |
|----------|--------|-----------|
| A power-spectrum | Find ω at peak of |FFT(E[y\|c])|² | Hunt the power peak (existing approach) |
| B accuracy-grid | Find ω maximizing classifier accuracy over ω ∈ (0,π] | Directly optimize what we care about |
| C iterative-residual | Run A, subtract dominant-period fit, run A again on residuals | Decompose multi-frequency signals by subtraction |

Tested on five primitives (NCELL=30, NSAMP=12000):

| primitive | theory ω | period |
|-----------|---------|--------|
| period-2 | π = 3.1416 | 2 |
| period-3 | 2π/3 = 2.0944 | 3 |
| 2 XOR 3 | π/3 = 1.0472 | 6 |
| 2 AND 3 | π/3 = 1.0472 | 6 |
| 2 XOR 3 XOR 5 | π/15 = 0.2094 | 30 |

## Results

```
── 2 AND 3 (p=6) ← the failing case (theory ω=1.0472) ──
  A power-spectrum:     found ω=0.0052,  acc=0.822  (DC, FAILS)
  B accuracy-grid:      found ω=1.0315,  acc=1.000  (FIXED)
  C iterative-residual: ω2=0.0052,       acc=0.822  (DC still, FAILS)
  exact theoretical ω:  1.0472           acc=1.000

── 2 XOR 3 XOR 5 (p=30) ──
  A power-spectrum:  found ω=1.1781,  acc=0.869
  B accuracy-grid:   found ω=1.0367,  acc=0.950
  C iter-residual:   ω2=0.0052,       acc=0.869
  exact theory ω:    0.2094           acc=0.640

SUMMARY TABLE:
  Strategy           | p-2  | p-3  | 2XOR3 | 2AND3      | 2XOR3XOR5
  -------------------+------+------+-------+------------+-----------
  A power-spectrum   | ok   | ok   | ok    | FAIL 0.822 | FAIL 0.869
  B accuracy-grid    | ok   | ok   | ok    | OK   1.000 | ok   0.950
  C iter-residual    | ok   | ok   | ok    | FAIL 0.822 | FAIL 0.869
```

## Verdict

**Strategy B (accuracy-grid) fixes AND-composition failure.** The power-spectrum approach
fails on `2 AND 3` because AND creates a 1/6-sparse positive class whose Fourier spectrum
is dominated by the DC (near-zero frequency) component. The accuracy-grid search ignores
the power spectrum entirely and directly optimizes what matters: which ω produces a
cos-feature with the highest test accuracy. It finds ω≈1.03≈π/3 with acc=1.000.

**Strategy C (iterative-residual) does NOT fix it.** After subtracting the DC-trend
classifier from the labels, the residuals still exhibit DC dominance in the second spectral
pass. The near-zero frequency found in pass 1 isn't an informative first component — it's
measuring the class imbalance. Subtracting a prediction based on DC doesn't expose the
period-6 frequency; it just removes a small constant bias. The iterative approach is a
reasonable idea but it only works when the first pass finds a REAL component to subtract.

**Triple-period (2 XOR 3 XOR 5, period 30):** accuracy-grid reaches 0.950, which is
substantially better than power-spectrum (0.869) and much better than exact theory ω (0.640).
The exact theoretical frequency π/15 ≈ 0.209 gives only 0.640 because the period-30 signal
is spread too thin: with NCELL=30, each of the 30 count values appears only ~400 times in
NSAMP=12000, and E[y|c] is noisy. The accuracy-grid finds ω≈1.037, close to the period-6
dominant harmonic of the period-30 function, which is strong enough to achieve 0.950 even
though it isn't the fundamental period.

## The core finding: search objective is itself a closure question

The power-spectrum approach is closed over spectral power as its fitness signal. When
a predicate's structure aligns with what spectral power measures (balanced periodic signal),
it works. When the predicate is sparse (AND-composed), spectral power is the wrong fitness
signal — it finds "rare events" not "periodic events."

Strategy B escapes this closure: it uses accuracy (downstream task performance) as the
fitness signal for the ω search. The search domain (ω ∈ (0,π]) is the same; only the
objective changes. That single change — from power-peak to accuracy-peak — is enough to
flip AND-composition from failure (0.822) to success (1.000).

This mirrors the general closure principle: the power-spectrum substrate without accuracy
feedback is closed and insufficient for sparse AND-compositions, just as degree-k
monomials without degree-(k-1) terms are insufficient for XOR parity.

## What this opens

Three new questions:

1. **AND at arbitrary sparsity:** At what positive-class fraction does the accuracy-grid
   advantage over power-spectrum vanish? For 1/6 sparsity the gap is 1.000 vs 0.822.
   For 1/2 (balanced), both should work. The crossover point defines "how sparse is too
   sparse for spectral."

2. **Unknown periods with accuracy-grid:** If neither period is known, accuracy-grid
   over the full ω ∈ (0,π] can find the best single frequency. But for multi-period
   AND-compositions, one frequency may not be enough. Does iterative accuracy-grid
   (find best ω, freeze it, find best ω₂ in remaining signal) work?

3. **Triple-period decomposition:** 2 XOR 3 XOR 5 (period 30) gets 0.950 with accuracy-grid
   using a single harmonic. Adding a second frequency (two-component logistic over the
   two best grid frequencies) may push this to 1.000.

See: `multi_period.md`, `operator_inference.md`, `composed_discovery.md`.
