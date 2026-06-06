# Frontier 18 — Extended Pool (degree-4 and degree-5)

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build extended-pool`

## What was tested

F17 left two predicates unsolved due to pool insufficiency:
- k4-parity: needs degree-4 monomial — not in the degree-3 pool
- k2∧k3: AND of two parities, requires degree-4 cross-terms

Pool extended to: deg1(6) + deg2(15) + deg3(20) + deg4(15) + deg5(6) = 62 features.

## Results

```
predicate            steps  feats  p2_acc   verdict
─────────────────────────────────────────────────────
k3-parity (sanity)   13     13     1.0000   SOLVED
k4-parity            7      13     0.9281   FAILED
k5-parity            1      6      0.5313   FAILED
k6-parity            0      0      0.5344   FAILED (correct rejection)
k2∧k3                8      13     1.0000   SOLVED
```

## Finding 1: k2∧k3 solved — degree-4 cross-terms found automatically

k2∧k3 = (b[0]⊕b[1]) ∧ (b[2]⊕b[3]⊕b[4])

The discovery trace:
1. b[0]*b[1]           — k2 sub-predicate monomial
2. b[2]*b[3]*b[4]      — k3 sub-predicate monomial
3-5. b[3]*b[4], b[2]*b[3], b[2]*b[4]  — k3 degree-2 support terms
6. b[0]*b[2]*b[3]*b[4] — degree-4 cross-term: k2 × k3 interaction
7. b[1]*b[2]*b[3]*b[4] — degree-4 cross-term: k2 × k3 interaction
8. b[0]*b[1]*b[3]      — additional cross-structure

Phase 2 reaches 1.0000 with these 8 features + 5 relevant degree-1 bits.

The AND operation between two sub-predicates creates cross-terms of degree
(deg_A + deg_B - 1) at minimum. The algorithm finds these automatically without
being told the predicate's compositional structure.

## Finding 2: k4-parity partially solved but pool pollution prevents full collection

k4-parity needs 15 features total:
- 1 degree-4 leading monomial: b[0]*b[1]*b[2]*b[3]
- 4 degree-3 support terms: all C(4,3) combinations
- 6 degree-2 support terms: all C(4,2) combinations
- 4 degree-1 terms: b[0], b[1], b[2], b[3]

The algorithm correctly finds the degree-4 monomial at step 1 (|g|=0.0294, gap=1.85x).
Then finds 4 of the 4 degree-3 terms but dual-stops at step 7 before collecting any
degree-2 terms. Phase 2 reaches 0.928 — better than the 0.522 random baseline and
better than F17's 0.877 ceiling for k3-parity, but not solved.

**Root cause**: the 62-feature pool dilutes the gradient signal. By step 6, correct
degree-2 candidates compete with irrelevant degree-4/5 monomials (60+ candidates)
at similar gradient magnitudes. The signal-to-noise ratio drops below the
threshold before all features are found.

## Finding 3: k5-parity — leading monomial found but support terms lost

Step 1 finds b[0]*b[1]*b[2]*b[3]*b[4] with gap=3.05x (clear). Then dual-stop fires
immediately — the degree-3/degree-1 support terms have |g| below 0.008 because
the 62-candidate pool spreads the gradient too thin. Phase 2 with only the degree-5
monomial + 5 degree-1 bits gives 0.531.

k5-parity needs 1 + 10 + 10 + 5 = 26 features total. The larger pool makes it
harder to collect the full support structure.

## Finding 4: Pool size and GRAD_MIN are coupled — pool pollution

F17's GRAD_MIN=0.008 was calibrated for a 41-feature pool. With 62 features:
- More irrelevant candidates compete with correct ones at each step
- Individual shadow gradients are smaller on average (budget spread over more candidates)
- Stopping fires before the complete feature set is assembled

The stopping criterion needs to scale with pool size. A pool of N features has
1/N times as many expected gradient "votes" per feature on average. GRAD_MIN
should scale as ~GRAD_MIN_base * sqrt(NCANDS_ref / NCANDS).

## What this opens

**Frontier 19**: scale-aware stopping + bottom-up pool construction.

Key insight from F18: the algorithm works best when the pool is **tightly matched** to
the predicate's degree. For k4-parity with 62 features, the degree-4 and degree-5
noise features dilute the degree-2/3 signal. A better strategy:

1. Run degree-3 discovery pass first (41 features) to find low-degree structure
2. Add degree-4/5 monomials at positions identified by step 1
3. Final adaptive retrain on the full assembled set

This "guided pool extension" avoids the signal dilution from having all higher-degree
monomials present during the low-degree collection phase.

See: `adaptive_retrain.md`, `dual_stop_discovery.md`, `two_phase_discovery.md`.
