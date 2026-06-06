# Frontier 17 — Adaptive Retrain

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build adaptive-retrain`

## What was tested

F16 found all correct features for k3-parity but the optimizer plateaued at 0.877.
Two retrain strategies compared against a shared dual-stop discovery phase:

- **Strategy A**: fixed 40000 iterations, LR=0.003 (long fixed schedule)
- **Strategy B**: adaptive LR halving — start LR=0.05, halve when loss doesn't improve
  for 500 consecutive steps, stop when LR < 1e-5 or 50000 total steps

## Results

### Strategy A — fixed low LR

```
predicate                         feats   acc      verdict
──────────────────────────────────────────────────────────
k2-parity b[0]⊕b[1]               3     1.0000   SOLVED
k3-parity b[0]⊕b[1]⊕b[2]          7     0.8563   FAILED
k3-random b[1]⊕b[3]⊕b[5]          7     0.8813   FAILED
k2∧k3                             13     0.8641   FAILED
k4-parity (out of pool)            0     0.5031   FAILED
```

### Strategy B — adaptive LR halving

```
predicate                         feats   acc      verdict
──────────────────────────────────────────────────────────
k2-parity b[0]⊕b[1]               3     1.0000   SOLVED
k3-parity b[0]⊕b[1]⊕b[2]          7     1.0000   SOLVED
k3-random b[1]⊕b[3]⊕b[5]          7     1.0000   SOLVED
k2∧k3                             13     0.8594   FAILED
k4-parity (out of pool)            0     0.5031   FAILED
```

### Part B — 20 unknown predicates, strategy B

**20/20 solved.** All k2-XOR, k3-XOR, 2-AND, 3-AND instances at random positions
reach 1.0000. Up from F15's 14/20 and F16's 18/20.

```
k3-XOR instances: 6/6 SOLVED (all reach 1.0000)
k2-XOR instances: 5/5 SOLVED
2-AND instances:  5/5 SOLVED
3-AND instances:  4/4 SOLVED
```

## Finding 1: Adaptive LR halving closes the k3-parity ceiling

Fixed low LR (Strategy A) gives 0.856–0.881 — worse than the F14 plateau, likely
because 40k small steps haven't reached the optimum either.

Adaptive halving (Strategy B) starts aggressive (LR=0.05), makes fast progress,
then repeatedly halves when it stagnates, allowing fine-grained convergence near the
optimum. This drives the coefficient ratios to the required 4:-2:-2:-2 pattern.

The 0.877 ceiling that persisted across F14, F15, F16 is **completely resolved** by
adaptive LR. It was never an algebraic or feature-selection problem — purely optimizer.

## Finding 2: k2∧k3 fails regardless — pool insufficiency, not optimizer

k2∧k3 = (b[0]⊕b[1]) ∧ (b[2]⊕b[3]⊕b[4])

Its polynomial expansion via AND(k2_poly, k3_poly) produces cross-terms up to degree 5:
e.g., b[0]*b[2]*b[3]*b[4], b[0]*b[1]*b[2]*b[3]*b[4] (degree 5). These are outside
the degree-3 candidate pool.

The algorithm collects 13 features greedily, approximating the predicate as best it
can within the pool, but 0.86 is the pool's ceiling for AND-of-parities — not an
optimizer failure. Fixed LR (0.8641) and adaptive LR (0.8594) give similar results,
confirming the ceiling is representational.

The dual-stop criterion doesn't cleanly reject k2∧k3 (it picks up 13 features) because
the partial approximation always has some gradient signal. This is a distinct failure
mode from k4-parity (cleanly rejected at step 0) — it's "representable in the pool's
approximation space" but not exactly representable.

## Finding 3: Complete algorithm for degree ≤ 3 threshold-bit predicates

The full pipeline (dual-stop discovery + adaptive retrain) now solves:
- All single-monomial predicates at any positions: k2-XOR, 2-AND, 3-AND
- All multi-monomial k3-family predicates: k3-XOR at any positions
- Correctly rejects out-of-pool predicates: k4-parity fires dual-stop at step 0

20/20 blind random test, covering all four classes, with positions unknown to the
algorithm at test time. This constitutes an automatic substrate discovery algorithm
for the degree-3 threshold-bit class.

## What this opens

**k2∧k3 and AND-of-parities**: requires a degree-5 pool extension. Does extending
the pool to degree-4 and degree-5 monomials allow the algorithm to find the exact
cross-terms? This tests whether the pipeline generalizes to higher degree automatically.

**k5-parity / k4-parity**: currently rejected because degree-4 monomials aren't in
the pool. Adding them makes k4 solvable; k5 then requires degree-5. The pattern
is: degree-k parity requires degree-k monomials as the leading term, plus all
lower-even-degree support terms.

**Algorithm summary** (complete as of F17):
```
1. Dual-stop gradient discovery:
   - Start with degree-1 threshold-bit features
   - Add highest-gradient candidate
   - Stop when: gap < 1.5 AND |g| < 0.008
2. Extract relevant degree-1 bits from discovered features (noise suppression)
3. Adaptive LR retrain on discovered + relevant bits:
   - LR init=0.05, halve when loss stagnates for 500 steps
   - Continue until LR < 1e-5 or 50k steps
```

See: `dual_stop_discovery.md`, `two_phase_discovery.md`, `discovery_loop.md`.
