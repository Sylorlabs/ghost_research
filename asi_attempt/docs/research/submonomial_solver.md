# Frontiers 19-21 — Guided Pool, Online Refinement, Sub-Monomial Force-Add

**Status:** built, measured. Reproduce:
- F19: `cd asi_attempt && zig build guided-pool`
- F20: `cd asi_attempt && zig build online-guided`
- F21: `cd asi_attempt && zig build submonomial-solver`

## Background

F18 extended the pool to degree-5 and solved k2∧k3 but k4-parity reached only 0.928.
Root cause (confirmed F19-F20): degree-2 and degree-3 support terms' shadow gradients are
suppressed by multicollinearity once the leading degree-4 monomial is in the model.
The gradient criterion cannot collect the full 15-feature expansion of k4-parity.

## F19 — Guided Pool (pre-filter by pass-1 positions)

Strategy: pass-1 runs on degree-3 pool only, identifies relevant bit positions from what
it finds, then pass-2 runs on a pool filtered to those positions.

**Results:**
- k3-parity: SOLVED (positions {0,1,2} → 7-feature pool, clean)
- k4-parity: FAILED — pass-1 finds nothing (k4-parity has exactly zero degree-3
  Fourier coefficients), so position mask = 0, filtered pool is empty
- k5-parity: same failure
- k2∧k3: SOLVED — pass-1 finds positions {0,1,2,3,4}, pass-2 finds degree-4 cross-terms

**Key finding**: the guided approach works for compound predicates (whose sub-components
are representable in the lower pool) but fails for pure k-parity with k > pool_degree
because the lower-pool signal is algebraically zero.

## F20 — Online Refinement (narrow pool after each discovery)

Strategy: start full pool (62 features), after first discovery narrow to features that
only use positions already seen.

**Results:**
- k3-parity: SOLVED
- k4-parity: gets 0.87 — better than random, but degree-2 gradients still suppressed
- k5-parity: 0.517 — dual-stop after finding degree-5 + one degree-4 sub
- k2∧k3: BROKEN — step 1 finds b[0]*b[1], narrows to positions {0,1}, excludes the
  k3 component entirely. Online narrowing is wrong for compound predicates.

## F21 — Sub-Monomial Force-Add (the right fix)

**Core insight**: for k-parity, once the degree-k leading monomial is discovered, the
complete feature expansion is known by combinatorics — it's exactly all C(k,j) subsets
for j=2,...,k-1. No gradient needed; force-add them all.

Algorithm modification: on discovering a degree-k monomial (k≥3), immediately activate
all C(k,2) degree-2 + C(k,3) degree-3 + ... + C(k,k-1) degree-(k-1) sub-monomials.

### Results

```
predicate                          steps  feats  final_acc  verdict
────────────────────────────────────────────────────────────────────
k3-parity (sanity)                  4     31     1.0000     SOLVED
k4-parity b[0]⊕b[1]⊕b[2]⊕b[3]      3     47     1.0000     SOLVED
k4-parity random b[1]⊕b[3]⊕b[4]⊕b[5] 4  48     1.0000     SOLVED
k5-parity b[0]⊕...⊕b[4]            1     32     0.9125     FAILED
k2∧k3 (compound)                   9     38     1.0000     SOLVED
```

**k4-parity solved at any positions**: step 1 discovers the degree-4 monomial with
|g|≈0.030, gap≈1.9x. Force-add immediately adds all 10 sub-monomials (6 degree-2 +
4 degree-3). Adaptive retrain reaches 1.0000.

**k2∧k3 still works**: the force-add doesn't break compound predicates because it only
fires on discovered high-degree monomials, not at all positions. The gradient correctly
finds degree-2 components first (b[0]*b[1], b[2]*b[3]*b[4]), then degree-4 cross-terms,
and force-adds the appropriate sub-monomials at each step.

**k5-parity at 0.9125**: all 31 needed features are present (C(5,1)=5 degree-1 +
C(5,2)=10 degree-2 + C(5,3)=10 degree-3 + C(5,4)=5 degree-4 + 1 degree-5). The
failure is optimizer convergence — k5-parity's leading polynomial coefficient is 16
(vs 8 for k4, 4 for k3). The logistic function requires very large weights to
saturate at 0 and 1. 60k adaptive steps not sufficient.

## Complete Algorithm (as of F21)

```
1. Pool: degree-5 threshold-bit monomials (62 features)

2. Dual-stop gradient discovery:
   Start with degree-1 features active.
   Each step: compute shadow gradients, add best candidate.
   On discovering degree-k monomial (k ≥ 3): force-add all C(k,j)
     sub-monomials for j=2,...,k-1 at those positions.
   Stop when: gap < 1.5 AND |g| < 0.008.

3. Adaptive retrain on all discovered+force-added features:
   LR init=0.05, halve on stagnation, min LR=1e-5, max 60k steps.
```

### Coverage

| predicate class | pool needed | solved? |
|----------------|-------------|---------|
| k2-XOR (degree-2) | degree-2 pool | YES, 1 step |
| 2-AND (degree-2) | degree-2 pool | YES, 1 step |
| 3-AND (degree-3) | degree-3 pool | YES, 1 step |
| k3-XOR/parity | degree-3 + force-sub | YES |
| k4-parity | degree-4 + force-sub | YES (F21) |
| k5-parity | degree-5 + force-sub | 0.91 (optimizer gap) |
| k6-parity | degree-6 (out of pool) | not attempted |
| k2∧k3 | degree-4 cross-terms | YES (F18, F21) |

## Open: k5-parity optimizer gap

Features: complete (31 features found and confirmed).
Problem: the coefficient ratio for k5-parity is 16:-8:+4:-2:+1 (degree-5 vs 4 vs 3 vs 2
vs 1). The logistic regression needs output logits >> 1 to assign probability near 0 or 1.
The adaptive optimizer runs 60k steps — might need 200k+ or a different optimizer
(L-BFGS, Newton's method) for the extreme coefficient ratios of k≥5 parity.

See: `adaptive_retrain.md`, `extended_pool.md`, `dual_stop_discovery.md`.
