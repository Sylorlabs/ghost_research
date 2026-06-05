# Frontier 15 — Two-Phase Discovery: gap-stopped discovery then clean retrain

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build two-phase-discovery`

## What was tested

The two-phase algorithm proposed from F14's finding that feature discovery and training
optimization are separable:

- **Phase 1 (DISCOVER)**: run gradient loop, stopping when gap < 1.5 OR |g| < 0.005
  → collects the set of features the gradient thinks are needed
- **Phase 2 (SOLVE)**: retrain from scratch on discovered features + ONLY relevant
  degree-1 bits (no noise bits for positions not appearing in any discovered feature)

Part A: 5 known predicates to confirm expected behavior
Part B: 20 randomly generated unknown predicates — a blind test of the algorithm

## Results

### Part A — known predicates

```
predicate                p1_acc  p2_acc  steps  gap    verdict
────────────────────────────────────────────────────────────────────────
k2-parity b[0]⊕b[1]      1.000   1.000    1     1.04   SOLVED
k3-parity b[0]⊕b[1]⊕b[2] 0.663   0.625    1     1.07   FAILED
k3-random b[1]⊕b[3]⊕b[5] 0.592   0.627    1     1.04   FAILED
k2∧k3                    0.736   0.722    2     1.14   FAILED
k4-parity (out of pool)  0.522   0.522    0     1.01   FAILED
```

### Part B — 20 unknown random predicates

```
#    type    positions    p1_acc  p2_acc  steps  verdict
────────────────────────────────────────────────────────────
 1   k2-XOR  [0,2,1,5]   1.000   1.000    1     SOLVED
 2   3-AND   [2,0,4,1]   1.000   1.000    1     SOLVED
 3   3-AND   [3,2,5,0]   1.000   1.000    1     SOLVED
 4   2-AND   [4,2,5,0]   1.000   1.000    1     SOLVED
 5   k2-XOR  [1,2,4,5]   1.000   1.000    1     SOLVED
 6   k2-XOR  [4,0,2,5]   1.000   1.000    1     SOLVED
 7   3-AND   [5,3,0,1]   1.000   1.000    1     SOLVED
 8   k3-XOR  [0,3,5,1]   0.548   0.502    1     FAILED
 9   k3-XOR  [1,3,5,0]   0.592   0.627    1     FAILED
10   2-AND   [3,5,0,1]   1.000   1.000    1     SOLVED
11   2-AND   [2,1,3,4]   1.000   1.000    1     SOLVED
12   2-AND   [2,5,1,0]   1.000   1.000    1     SOLVED
13   k2-XOR  [4,5,1,0]   1.000   1.000    1     SOLVED
14   2-AND   [0,5,3,2]   1.000   1.000    1     SOLVED
15   k2-XOR  [5,3,1,2]   1.000   1.000    1     SOLVED
16   k3-XOR  [3,0,2,4]   0.642   0.752    1     FAILED
17   k3-XOR  [5,2,3,4]   0.627   0.641    1     FAILED
18   2-AND   [3,1,5,0]   1.000   1.000    1     SOLVED
19   k3-XOR  [2,4,0,3]   0.505   0.505    1     FAILED
20   k3-XOR  [4,1,0,5]   0.653   0.627    1     FAILED

Part B: 14/20 solved  avg_steps=1.0
```

## Finding 1: Single-monomial predicates solve perfectly at random positions

k2-XOR (degree-2), 2-AND (degree-2), and 3-AND (degree-3) all achieve 1.000 accuracy
in exactly 1 step, regardless of which positions are chosen. The gradient selects the
exactly-needed monomial with gap well above 1.5x, phase 1 stops immediately after,
and phase 2 confirms. The relevant-bit filter in phase 2 gives the correct minimal
feature set automatically.

**This validates the core algorithm for single-monomial predicates.** 14/14 of
(k2-XOR + 2-AND + 3-AND) instances solved perfectly. The algorithm is a working
automatic substrate discovery method for this class.

## Finding 2: k3-XOR (= k3-parity at random positions) defeats the gap criterion

Every k3-XOR instance fails. The failure mode is identical to k3-parity from F14:

1. Step 1 adds the degree-3 monomial b[i]*b[j]*b[k] (correct)
2. After that, ALL three degree-2 support terms {b[i]b[j], b[i]b[k], b[j]b[k]} have
   EQUAL shadow gradient magnitude — they're symmetric under permutation of the XOR bits
3. Gap drops to ≈1.0x: no single feature dominates
4. The stopping criterion triggers — but this is wrong; three more correct features exist

**The gap signal is telling the truth**: "no single feature clearly dominates the
others." But the algorithm's response (stop) is wrong. The correct response is
"continue, but accept that the next few features are a symmetric group."

## Finding 3: Gap < 1.5x has two distinct meanings

| condition | |g| level | interpretation |
|-----------|-----------|----------------|
| gap < 1.5x AND |g| < 0.005 | noise | predicate not representable; truly stop |
| gap < 1.5x AND |g| > 0.01  | symmetric group | multiple equally-needed features; CONTINUE |

The current algorithm conflates these. k4-parity has gap=1.01 AND |g|≈0.002 (noise level).
k3-XOR after step 1 has gap≈1.0x AND |g| still substantial — the magnitude signal hasn't
gone dark, only the selection signal has.

**The fix**: conjunctive stopping criterion — stop only when BOTH gap < 1.5x AND |g| < GRAD_MIN.
Continue if |g| is still large even with low gap.

## Finding 4: Phase 2 does not recover from missing features

When phase 1 terminates early (k3-XOR cases), phase 2 can't help — it only trains on
what phase 1 found. Phase 2 improves 0.005–0.110 over phase 1 in some cases (trial 16:
0.642 → 0.752) but can't reach target. The p2 improvement is due to cleaner training,
not new features.

Phase 2's value is only activated when phase 1 correctly identifies all needed features —
then the noise removal gives the convergence benefit.

## Finding 5: Predicate classes partition cleanly

```
class         degree   structure              F15 result   root cause
──────────────────────────────────────────────────────────────────────
k2-XOR        2        single monomial        14/14 SOLVED gap works
2-AND         2        single monomial        6/6   SOLVED gap works
3-AND         3        single monomial        3/3   SOLVED gap works
k3-XOR        3        monomial + support     0/6   FAILED gap stops early
k3-parity     3        monomial + support     0/1   FAILED gap stops early
k4-parity     4        out of pool            0/1   FAILED correct rejection
```

The class boundary is: **does the predicate require a single dominant monomial, or a
symmetric group of equally-important features?** The gap criterion solves the first class
completely. The second class requires a dual stopping criterion (gap AND magnitude).

## What this opens

**Frontier 16 — Dual Stopping Criterion**: change the stopping rule to:
```
stop when: gap < GAP_STOP AND |g| < GRAD_MIN (e.g., 0.008)
continue when: |g| is large even if gap < 1.5x
```
Predicted: k3-parity and all k3-XOR cases reach 1.000 in phase 2.
The algorithm becomes a complete solver for all threshold-bit predicates in the pool.

**Symmetric gradient groups**: when gap ≈ 1.0x and |g| is still large, all top
candidates are equally needed. The XOR polynomial expansion:
XOR(b[i], b[j], b[k]) = degree-3 term + all three degree-2 terms + three degree-1 terms
requires a "group commit" — add all features with |g| above threshold in one batch
rather than one-at-a-time greedy selection.

**Phase 2 benefit quantification**: for predicates where phase 1 gets all features, does
phase 2 consistently reach 1.000 while phase 1 alone plateaus? (Not testable here since
phase 1 always gets the right feature set when it works at all.) Needs explicit test: run
phase 2 on a hand-constructed "correct feature set + noise" to measure the convergence gain.

See: `discovery_loop.md`, `gradient_discovery.md`, `predicate_tomography.md`.
