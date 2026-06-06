# Frontier 6 — composition detection via power-accuracy mismatch

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build operator-inference`

## The probe

Hypothesis: when spectral is applied to the WRONG domain for a composed predicate, it
still generates a "spectral peak" (non-trivial power ratio) but the classifier at that
peak FAILS (low accuracy). A simple periodic family shows high power AND high accuracy.
The mismatch — not the power alone — is the composition signal.

## Results

```
  family              | P1 lin | P2a pwr | P2b acc | P3 swap | P4 ord | → detect
  --------------------+--------+---------+---------+---------+--------+---------
  parity-of-count     | 0.494  |    5.3x | 1.000   | 0.028   | 9.90x | SPECTRAL ✓
  inversion-parity    | 0.512  |    3.6x | 0.503   | 0.008   | 9.90x | RELATIONAL ✗
  XOR(b0,b1)          | 0.781  |    2.9x | 0.597   | 0.000   | 1.28x | ?

  --- composition probe ---
  parity-of-count:   raw-spectral acc = 1.000,  inv-spectral acc = 0.517  → no mismatch ✓
  inversion-parity:  raw-spectral acc = 0.503,  inv-spectral acc = 1.000  → GAP = 0.497
  XOR(b0,b1):        raw-spectral acc = 0.597,  inv-spectral acc = 0.582  → no gap
```

## Verdict

**The mismatch signal IS real and discriminative.** For inversion-parity, the raw-spectral
classifier fails (0.503 ≈ chance) while the pairwise-inner spectral succeeds perfectly
(1.000). The gap is 0.497 — more than large enough to detect. For parity-of-count, raw
spectral already hits 1.000 (no mismatch). For XOR, neither spectral approach works and
the gap is near-zero.

**But the routing rule failed.** The current rule required `P2a (power ratio) > 5.0`
to trigger mismatch detection. For inversion-parity, power ratio was 3.6x (below threshold).
So the router fell through to RELATIONAL (P4 was always high since nothing else worked).

The correct composition detection rule is:

    IF raw_spectral_acc < 0.70  AND  (inv_spectral_acc − raw_spectral_acc) > 0.20
    → COMPOSED (try pairwise-inner spectral)

This rule correctly identifies inversion-parity:
- raw_spectral_acc = 0.503 < 0.70 ✓
- gap = 1.000 − 0.503 = 0.497 > 0.20 ✓

And correctly rejects parity-of-count:
- raw_spectral_acc = 1.000 ≥ 0.70 → not a mismatch ✓

## Correction from XOR linear accuracy (0.781)

The XOR linear accuracy is higher than expected (~0.50) because of class imbalance.
With THRESH=2 on VMAX=5, P(bit=1) ≈ 4/6 ≈ 0.67. So XOR(b0,b1) is 0 with probability
0.67²+0.33²≈0.56 and 1 with probability ≈0.44. A trivial "predict 0 always" gets 56%;
a linear readout exploiting the marginals can reach ~0.78 without learning the interaction.
This is a label-imbalance artifact, not real linear separability of XOR.

## What this opens

The composition probe works; the routing rule needs a gap-based criterion rather than
a power-threshold criterion. The next step: generalize to candidate inner-quantity
enumeration — given that the mismatch is detected, enumerate candidate inner quantities
(raw count, inversion count, product count, max, etc.) and run spectral on each.
The composition detector then becomes a search: `argmax_{inner_Q} spectral_acc(Q)`.

See: `composed_discovery.md`, `spectral_discovery.md`.
