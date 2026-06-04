# Frontier 7 — multi-period discovery: spectral scales to XOR-combined periods, fails on AND

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build multi-period`

## What was tested

Four primitives over cell count c = #{cells ≥ THRESH}:

| primitive | structure | theory ω |
|-----------|-----------|---------|
| period-2 | c mod 2 | π = 3.14 |
| period-3 | (c mod 3)==0 | 2π/3 = 2.09 |
| 2 XOR 3 | (c mod 2) XOR ((c mod 3)==0) | π/3 = 1.05 (period 6) |
| 2 AND 3 | (c mod 2) AND ((c mod 3)==0) | π/3 = 1.05 (period 6) |

## Results

```
  primitive           | found ω  | power-ratio | single-ω acc | two-ω acc
  --------------------+----------+-------------+--------------+-----------
  period-2            | 3.1416   |    6.3x     |    1.000     |   1.000
  period-3            | 2.0996   |    2.8x     |    1.000     |   1.000
  2 XOR 3 (period 6)  | 1.0420   |    2.8x     |    1.000     |   0.885
  2 AND 3 (period 6)  | 0.0052   |    2.1x     |    0.789     |   1.000
```

Accuracy at exact theoretical frequencies:

```
  primitive            | cos(π·c)  | cos(2π/3·c) | cos(π/3·c) | cos(π)+cos(2π/3)
  ---------------------+-----------+-------------+------------+-----------------
  2 XOR 3 (period 6)   |   0.602   |    0.602    |   1.000    |    0.885
  2 AND 3 (period 6)   |   0.717   |    0.885    |   1.000    |    1.000
```

## Verdict and interpretation

**Period-3 confirmed (new result).** The spectral operator cleanly finds ω=2π/3 for
a period-3 predicate. Prior experiments only tested period-2.

**XOR of two periods: spectral finds the combined period.** For `(c mod 2) XOR ((c mod 3)==0)`,
the spectral operator finds ω≈π/3=1.042, which is exactly the combined period-6 frequency.
Single-frequency accuracy: 1.000. This is a clean positive result: **the spectral operator
handles XOR-composed periods by finding the LCM period.**

Why this works: XOR of two periods creates a new periodic function with period lcm(p1,p2).
The Fourier spectrum of this function has a dominant component at ω=2π/lcm, and the spectral
operator finds it. The combined function is balanced (0 and 1 roughly equally distributed
over one period of 6), so the fundamental frequency dominates.

**AND of two periods: spectral FAILS to find the combined period.** For `(c mod 2) AND ((c mod 3)==0)`,
the spectral operator finds ω≈0.005 (near DC), giving only 0.789 accuracy.

Why this fails: AND of two conditions creates a SPARSE indicator — y=1 only when c≡0 mod 6
(one value per period). The Fourier spectrum of a sparse spike train is dominated by the
DC component and low-frequency harmonics, not the fundamental period-6 frequency.
The "near-DC" peak the operator finds represents the rarity of y=1 events, not their period.

But: cos(π/3·c) alone gives 1.000 accuracy on the AND predicate too (exact-frequency test).
The period IS there in the signal; the spectral operator just can't locate it through the
power peak because the near-DC trend dominates.

**Two-component spectral [cos(π·c), cos(2π/3·c)]:**
- For XOR: 0.885 — WORSE than single-frequency (1.000). The two component frequencies
  together over-parameterize the already-solved problem.
- For AND: 1.000 — better than single-frequency (0.789). The AND predicate genuinely needs
  two frequency components to classify (it's the intersection of two conditions).

## The failure mode characterization

The single-pass spectral operator fails on sparse AND-compositions because:
1. The AND creates a sparse positive class (1/6 of cases)
2. Sparsity makes the DC (near-zero frequency) component dominate the power spectrum
3. The operator finds the "trend" (rarity) rather than the "oscillation" (period)

Fix: explicit multi-frequency search (enumerate candidate combined periods) rather than
hunting the power peak. For AND-composed predicates, the correct ω = π/lcm(p1,p2) gives
1.000 but is not the power-peak frequency.

## What this opens

Three new questions:
1. **More than two periods:** does XOR of three periods (period 2, 3, 5 → combined period 30)
   still hit a clean spectral peak? At some point the signal must be too distributed.
2. **Unknown periods:** if both periods are unknown (not just which cells are relevant),
   can the spectral operator find both? Or does iterative subtraction (find dominant period,
   subtract, find next) decompose them?
3. **AND at arbitrary sparsity:** at what positive-class fraction does the DC term overwhelm
   the period-k term in the power spectrum? This is a signal-to-noise question.

See: `spectral_discovery.md`, `composed_discovery.md`.
