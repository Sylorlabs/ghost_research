# Parity Phase Boundary (#41) + Hard Parity

**Status:** built, measured, exact.
Reproduce: `zig build parity`

## Setup recap

`parity_closure.zig` (from the main `parity_closure.md` document) demonstrates
that k-sparse parity is provably at chance for linear models and solved by MLPs.
This extends it with two questions:

1. **#41 (easy parity phase boundary):** at what (k, n_train) does the MLP stop
   finding sparse parity when the relevant bits are always the first k?
2. **Hard parity:** when relevant bits are RANDOM (C(N,k) possible subsets), how
   many samples does the MLP need?

Both use N=16 input bits, H=32 hidden units (easy) / H=64 (hard), 3 seeds (max).

---

## #41: Easy parity phase boundary (fixed relevant bits)

```
  n_train -> |    100    500   2000   8000  20000 
  k          |
  -----------+-----------------------------------
  k=1        | 1.000. 1.000. 1.000. 1.000. 1.000. 
  k=2        | 1.000. 1.000. 1.000. 1.000. 1.000. 
  k=3        | 1.000. 1.000. 1.000. 1.000. 1.000. 
  k=4        | 1.000. 1.000. 1.000. 1.000. 1.000. 
  k=5        | 0.950. 1.000. 1.000. 1.000. 1.000. 
  k=6        | 0.512  1.000. 1.000. 1.000. 1.000. 
```

**Phase boundary: (k=6, n_train ∈ (100, 500))**. For k≤5, even 100 samples suffices.
For k=6 with n=100, the MLP fails (0.512 ≈ chance). With 500 samples, it recovers.

**Caveat (important):** the relevant bits are always bits 0..k-1. The MLP only needs
to learn WHAT to do with those bits — it doesn't need to discover WHICH bits matter.
This is the easy version. The hard version (unknown relevant bits) should be harder.

---

## Hard parity: random relevant bits

H=64 neurons, 300 epochs. The k relevant bit indices are fixed per seed but randomly
chosen — the MLP must discover WHICH k bits among 16 matter.

```
  n_train -> |    500   2000   8000  20000 
  k          |
  -----------+----------------------------
  k=1        | 1.000. 1.000. 1.000. 1.000. 
  k=2        | 1.000. 1.000. 1.000. 1.000. 
  k=3        | 1.000. 1.000. 1.000. 1.000. 
  k=4        | 1.000. 1.000. 1.000. 1.000. 
```

**Null result:** the hard version (random relevant bits) is NOT harder than the easy
version at N=16, k≤4. The MLP solves all cases with 500 samples.

**Why this contradicts the prediction:** I predicted hard k=2 should need ~N² = 256
samples (the statistical-query lower bound). This was wrong. The SQ lower bound applies
to algorithms that observe only E[f(x,y)] queries; SGD directly sees (x,y) pairs and
can detect correlations across samples. For k=2, the relevant bits appear in every sample
and their contribution to the label is detectable — with 500 samples over 16 bits, the
MLP has enough signal to find 2 relevant bits without exhaustive search.

**What would make it genuinely hard:**
- N=64+ (many more irrelevant bits to mask the signal)
- k ≥ N/4 (large fraction relevant, exponential search space)
- Or a model without hidden layers (no nonlinearity to exploit)

At N=16 and k≤4, the search space C(16,4) = 1820 is too small to expose the phase
transition. The experiment is not hard enough to see the floor.

---

## What this means for the closure principle

The easy parity is the right illustration of the closure principle: linear models
provably fail for k≥2 (the ceiling is a theorem), and the MLP escapes via its
product structure (the nonlinear generator). The hard parity experiment was designed
to find the sample-complexity wall — but N=16 is too small for the wall to appear.

The genuine research question — "how many samples does SGD need to find k sparse
parity in N bits?" — requires N ≫ k, where N=64-128 and k=4-8 would expose the
true phase boundary. That is a longer experiment (not run here).

**Honest grade:** The easy parity boundary (k=6 fails at 100 samples) is a real
but unsurprising result — it just reflects that 100 < 2^6 = 64 combinations. The hard
parity null result is more interesting: it shows that for small N, feature discovery
(which bits matter?) is easier than theory suggests when you have direct pair supervision.
