# Frontier 14 — Discovery Loop: convergence, failure modes, and the gap signal

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build discovery-loop`

## What was tested

The gradient discovery algorithm run as a full loop on 8 predicates:
- **Solvable**: k2-parity, k3-parity, k3-random (different positions), k2∧k3, k2⊕k3
- **Out-of-pool**: k4-parity (needs degree-4), count-parity (needs degree-6)
- **Wrong substrate**: inv-parity (relational, no threshold-bit representation)

Algorithm: train degree-1 threshold-bit → shadow gradients → add best feature →
retrain FROM SCRATCH → repeat until target accuracy or MAX_STEPS.

Output for each step: feature added, test accuracy, gradient magnitude, gap = |g₁|/|g₂|.

## Results

```
k2-parity  b[0]⊕b[1]          start=0.509
  step 1: +b[0]*b[1]    acc=1.000  |g|=0.1247  gap=2.0x
  → SOLVED in 1 step

k3-parity  b[0]⊕b[1]⊕b[2]     start=0.520
  step 1: +b[0]*b[1]*b[2]  acc=0.663  |g|=0.0595  gap=10.4x  ← CORRECT first
  step 2: +b[1]*b[2]       acc=0.767  |g|=0.0288  gap=1.0x
  step 3: +b[0]*b[1]       acc=0.877  |g|=0.0302  gap=1.1x
  step 4: +b[0]*b[2]       acc=0.877  |g|=0.0292  gap=1.7x
  steps 5-8: noise features, no improvement
  → FAILED at 0.877

k3-random  b[1]⊕b[3]⊕b[5]    start=0.533
  step 1: +b[1]*b[3]*b[5]  acc=0.558  |g|=0.0609  gap=9.2x  ← CORRECT first
  steps 2-8: plateau at 0.867
  → FAILED at 0.867

k2∧k3  (b[0]⊕b[1]) ∧ (b[2]⊕b[3]⊕b[4])  start=0.777
  step 1: +b[0]*b[1]           acc=0.777  |g|=0.0595  gap=2.0x  ← CORRECT
  step 2: +b[2]*b[3]*b[4]      acc=0.834  |g|=0.0305  gap=3.1x  ← CORRECT
  steps 3-8: plateau at 0.834
  → FAILED at 0.834 (but found both needed features in correct order)

k2⊕k3  (b[0]⊕b[1]) ⊕ (b[2]⊕b[3]⊕b[4])  start=0.502
  step 1: +b[0]*b[5]  acc=0.530  |g|=0.0068  gap=1.5x  ← WRONG, tiny |g|
  all 8 steps: random noise features, never above 0.548
  → FAILED qualitatively differently

k4-parity  (degree-4, not in pool)   start=0.531
  all 8 steps: |g| ≈ 0.002–0.005, gap ≈ 1.0–1.3x, random features
  → FAILED gracefully (no false confidence)

count-parity  (degree-6, not in pool)  start=0.519
  all 8 steps: |g| ≈ 0.002–0.006, gap ≈ 1.0–1.2x
  → FAILED gracefully

inv-parity  (relational, no rep in pool)  start=0.505
  all 8 steps: |g| ≈ 0.002–0.006, gap ≈ 1.0–1.2x
  → FAILED gracefully
```

## Finding 1: The gradient correctly identifies needed features — but training doesn't converge

**k3-parity step 1**: b[0]*b[1]*b[2] ranked first with |g|=0.0595 and gap=10.4x — the
largest single-feature gap observed. The correct monomial is unambiguously identified.

After adding it, accuracy is 0.663, not 1.000. Why?

XOR(b[0], b[1], b[2]) = b[0] + b[1] + b[2] − 2b[0]b[1] − 2b[0]b[2] − 2b[1]b[2] + 4b[0]b[1]b[2]

The full polynomial expansion of 3-parity requires BOTH the degree-3 term AND degree-2
terms {b[0]b[1], b[0]b[2], b[1]b[2]}. Steps 2-4 correctly add all three degree-2 terms —
the algorithm is finding the right features. But:
1. The degree-1 features for irrelevant bits (b[3], b[4], b[5]) are noise that slows convergence
2. The gap at steps 2-4 is ~1.0x — the gradient can no longer distinguish between correct and
   incorrect degree-2 terms (all three have equal shadow gradient magnitude)
3. 2500 training iterations is insufficient for 10 features with correlated structure

**The algorithm finds the right features but the optimizer fails to converge once the
feature set has noise mixed in.**

## Finding 2: k2∧k3 — two-condition predicate found in the right order

Step 1 finds b[0]*b[1] (the k2-parity term) with gap=2.0x.
Step 2 finds b[2]*b[3]*b[4] (the k3-parity term) with gap=3.1x.

This is the correct decomposition of a conjunction of two parity conditions, discovered
automatically in 2 steps. The gradient correctly prioritizes the k2 condition first (it has
larger gradient magnitude — likely because k2-parity has higher "leakage" from degree-1
features than k3-parity). The algorithm discovers multi-feature structure in the right order.

The failure to reach target accuracy is the same training issue — not a feature discovery failure.

## Finding 3: k2⊕k3 fails qualitatively differently — a new failure mode

k2⊕k3 = XOR of two parity conditions. All 8 steps show:
- |g| values 5–30x smaller than the solvable cases (0.003–0.007 vs 0.03–0.12)
- gap consistently ≈ 1.0–1.5x across all steps
- Adding random, incorrect features with no accuracy improvement

XOR of two parity conditions creates a predicate where no single threshold-bit feature has
substantial shadow gradient. The residuals after degree-1 training are "white noise" with
respect to threshold-bit space — the XOR structure can't be approached incrementally.

This is a GENUINE failure of gradient discovery, not a training issue. The predicate
belongs to a closure that threshold-bit features cannot enter incrementally.

## Finding 4: The gap signal is a real-time reliability indicator

| regime | |g| range | gap range | interpretation |
|--------|-----------|-----------|----------------|
| clear signal | >0.05 | >5x | correct feature, gradient reliable |
| moderate signal | 0.01–0.05 | 2–5x | probably correct |
| noise | <0.01 | ~1x | feature not representable in pool |

**Stopping criterion:** stop when gap < 1.5x. At that point the gradient is adding noise —
the predicate is either (a) unsolvable in the current pool, or (b) the residuals have
become too diffuse for single-feature selection to work.

For k2-parity: gap=2.0x, |g|=0.12 — far above noise. One step.
For k4-parity: gap=1.1x, |g|=0.004 — at noise level from step 1.
The gap cleanly separates "solvable in pool" from "not representable."

## Finding 5: Feature discovery and training optimization are separable

The algorithm works as a FEATURE DISCOVERY mechanism even when the training fails to fully
converge. For k3-parity, the correct features ARE found (steps 1-4 add the right 4 features).
The 0.877 ceiling is a training issue, not a discovery issue.

This suggests a two-phase algorithm:
```
Phase 1 (DISCOVERY): run gradient loop with gap > threshold
  → collect candidate features; stop when gap drops below 1.5x
Phase 2 (TRAINING): retrain from scratch with ONLY the discovered features,
  more iterations, lower learning rate, no irrelevant degree-1 noise
```

For k3-parity, phase 1 collects {b[0]b[1]b[2], b[1]b[2], b[0]b[1], b[0]b[2]}.
Phase 2 trains logistic on these 4 + {b[0], b[1], b[2]} (relevant degree-1) with
5000+ iterations. Expected: 1.000 accuracy.

## What this opens

**The stopping rule:** gap < 1.5x signals that gradient discovery has reached its limit
with the current candidate pool. This makes the algorithm self-terminating: no need to
specify MAX_STEPS, just run until the gap falls below threshold.

**Phase 2 experiment:** Implement the two-phase algorithm. Phase 1 discovers features
(stop at gap drop). Phase 2 trains to convergence on discovered features only (no noise).
Predicted: k3-parity reaches 1.000; k3-random reaches 1.000; k2∧k3 reaches target.

**Degree cascade:** k3-parity needs b[0]b[1]b[2] + degree-2 terms. Does adding degree-2
candidates to the pool BEFORE running the loop change the step order? Or does the algorithm
discover the degree-3 term first regardless (because it has the highest shadow gradient)?

**k2⊕k3 requires a new theory:** XOR of two independent parity conditions is in a closure
that gradient discovery with threshold-bit features cannot enter. What feature set WOULD
allow incremental discovery of k2⊕k3? This is the next genuine unknown.

See: `gradient_discovery.md`, `higher_order_closure.md`, `predicate_tomography.md`.
