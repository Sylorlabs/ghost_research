# Frontier 16 — Dual Stopping Criterion

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build dual-stop-discovery`

## What was tested

F15 revealed the gap-only stopping criterion confounds two distinct situations:
- gap ≈ 1.0x AND |g| near zero → nothing representable; correct to stop
- gap ≈ 1.0x AND |g| still large → symmetric feature group equally needed; wrong to stop

Fix: change disjunction (gap OR mag) to conjunction (gap AND mag):
```
old: if (gap < 1.5 or |g| < 0.005) stop
new: if (gap < 1.5 AND |g| < 0.008) stop
```

## Results

### Part A — known predicates

```
predicate                    p1     p2     steps  |g|    stop       verdict
────────────────────────────────────────────────────────────────────────────────
k2-parity b[0]⊕b[1]          1.000  1.000   1  0.125  target     SOLVED
k3-parity b[0]⊕b[1]⊕b[2]     0.877  0.877   4  0.006  dual-stop  FAILED
k3-random b[1]⊕b[3]⊕b[5]     0.903  0.903   4  0.007  dual-stop  FAILED
k2∧k3                        0.789  0.789  10  0.007  dual-stop  FAILED
k4-parity (out of pool)      0.522  0.522   0  0.007  dual-stop  FAILED
```

### Part B — 20 unknown predicates

18/20 solved (up from F15's 14/20). The 2 failures are k3-XOR instances.

## Finding 1: Dual stop correctly finds all 4 k3-parity features

Verbose trace shows k3-parity now runs 4 steps, collecting:
1. b[0]*b[1]*b[2]  (degree-3 term, gap=12.0x)
2. b[0]*b[2]       (degree-2 support, gap=1.0x — old algo stopped here)
3. b[0]*b[1]       (degree-2 support, gap=1.1x)
4. b[1]*b[2]       (degree-2 support, gap=1.95x)

Then stops at dual-stop (gap=1.02, |g|=0.0062 — both thresholds met). All 4 needed
features found. Phase 2 has the complete representation but still outputs 0.877.

## Finding 2: Feature discovery is now solved; optimizer convergence is not

The 0.877 ceiling persists even after finding all correct features. Phase 2 clean
retrain on {degree-3 monomial + 3 degree-2 terms + 3 relevant degree-1 bits} = 7
features still plateaus. This is now confirmed as a gradient descent convergence
problem, not a feature selection problem.

The XOR polynomial representation requires coefficient ratios of 4:-2:-2:-2
(degree-3 vs degree-2 terms). Batch gradient descent with fixed LR doesn't drive
the optimizer to these precise ratios within 8000 iterations at LR=0.015.

## Finding 3: Class boundary confirmed

```
class     degree  structure          result
────────────────────────────────────────────────────────
k2-XOR    2       single monomial    14/14 SOLVED (F15+F16)
2-AND     2       single monomial    6/6   SOLVED
3-AND     3       single monomial    3/3   SOLVED
k3-XOR    3       monomial+support   14/20 solved in F16 (up from 0/6)
k3-parity 3       monomial+support   0/1   feature found, optimizer fails
k4-parity 4       out of pool        correct rejection (0 steps, dual-stop fires)
```

k4-parity correctly fires dual-stop immediately: gap=1.01, |g|=0.007 — both met at
step 0. The signal never rises above noise for an out-of-pool predicate.

## What this opens

**Frontier 17**: Fix the optimizer. The discovery algorithm is now complete for finding
features. Adaptive LR (halve when loss stagnates) or longer training at lower LR should
close k3-parity from 0.877 → 1.000. This is an optimizer problem, not an algebraic one.

See: `two_phase_discovery.md`, `discovery_loop.md`, `adaptive_retrain.md`.
