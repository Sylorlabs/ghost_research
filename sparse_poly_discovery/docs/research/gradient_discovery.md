# Frontier 12 — Gradient Discovery: failure gradient identifies the needed substrate

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build gradient-discovery`

## Hypothesis

When a classifier trained on an insufficient substrate fails, the residual gradient
with respect to candidate missing features IS the substrate discovery signal.

Shadow gradient: g_k = (1/N) Σᵢ errᵢ · f_k(xᵢ)

This is the gradient of the loss with respect to weight w_k if feature f_k were added
with weight 0. It measures: "if I added this feature, how much would it immediately help?"

## Setup

Predicate: k3-parity = XOR(b[0], b[1], b[2]) where b[i] = (c[i] ≥ THRESH)
Insufficient substrate: degree-2 threshold-bit features — b[i] and b[i]·b[j] (21 features)
Candidate extensions: all 20 degree-3 threshold-bit monomials b[i]·b[j]·b[l] for i<j<l

## Results

**Step 1:** degree-2 on k3-parity → accuracy 0.504 (near chance, as expected)

**Step 2:** shadow gradients for all 20 degree-3 monomials, ranked by magnitude:

```
  rank  monomial       |gradient|
  ─────────────────────────────────────────────
   1    b[0]*b[1]*b[2]  0.062299  ← CORRECT MONOMIAL
   2    b[2]*b[3]*b[5]  0.002155
   3    b[0]*b[3]*b[5]  0.001703
   4    b[0]*b[2]*b[5]  0.001435
   ...
  20    b[0]*b[1]*b[3]  0.000026

  Correct monomial b[0]*b[1]*b[2] ranked #1 out of 20
  Gap: 0.0623 vs 0.0022 — 29× larger than any other candidate
```

**Step 3:** greedy extension (add features by shadow-gradient rank):
```
  features_added  feature_added    accuracy
  ─────────────────────────────────────────
   1              b[0]*b[1]*b[2]   0.851  ← immediate large jump
   2..8           (other monomials) 0.851–0.871  ← plateau
```

**Step 4:** control — same features added in RANDOM order:
```
  features_added  accuracy
  ───────────────────────
   1              0.498
   2..8           0.498–0.525  ← stuck at chance
```

## Finding 1: The gradient IS the discovery signal — 29x gap

The correct monomial b[0]·b[1]·b[2] ranked #1 with shadow gradient 0.0623, versus
0.0022 for the next-best monomial — a **29× gap**. This is not a close call. The failure
gradient unambiguously identifies the missing substrate element.

**Why this works:** After training degree-2 to convergence on k3-parity, the model has
absorbed all information available from the 21 degree-2 features. The residual errors
are systematic: the model fails specifically on samples where b[0]=b[1]=b[2]=1 (all three
relevant bits set) or b[0]=b[1]=b[2]=0 (all three unset). These are the cases where the
degree-2 features provide no discriminative signal for the triple product.

The shadow gradient for b[0]·b[1]·b[2] is large and negative (the model underpredicts
k3-parity for these cases). All other degree-3 monomials involve at least one irrelevant
bit (b[3], b[4], b[5]) that is uncorrelated with k3-parity — their shadow gradients are
near zero because errᵢ is uncorrelated with those features.

## Finding 2: Adding the correct monomial jumps accuracy from 0.504 to 0.851

Adding b[0]·b[1]·b[2] as the first extension moves accuracy from chance (0.504) to 0.851.
The gap to 1.000 is because the degree-2 + b[0]·b[1]·b[2] combination needs more training
iterations to redistribute weights — the degree-2 features learned on the insufficient
substrate have some learned patterns that interfere with the new feature. Retraining from
scratch with the full degree-3 threshold-bit feature set gives 1.000 (as in F4/F10).

## Finding 3: Random feature selection stays at chance

Adding features in random order gives 0.498–0.525 accuracy after 8 additions — essentially
chance. The gradient is not just "better than random" — it is **categorically different**
from random. Without the shadow gradient, you would need to enumerate all combinations of
features to find the correct one, which is exponentially expensive.

## The algorithm this enables

```
GRADIENT_SUBSTRATE_DISCOVERY(predicate, substrate_base, candidates):
  1. Train logistic on substrate_base features
  2. Compute shadow gradients for all candidate extensions
  3. Add the highest-|gradient| candidate to the feature set
  4. Retrain
  5. If accuracy < threshold: repeat from step 2
  Return: extended substrate that achieves accuracy threshold
```

This is automatic substrate discovery — no human specification of which substrate to try.
The algorithm finds the right extension from data alone, guided by the failure gradient.

## What this opens

**Limitation: accuracy plateau at 0.851 after adding 8 features**
Adding more degree-3 monomials (ranked 2–8 by gradient) doesn't improve accuracy beyond
0.871. This suggests the degree-2 weights learned before the extension are interfering.
The fix: after adding the top-gradient feature, RETRAIN FROM SCRATCH (not warm-start from
the insufficient-substrate weights). The extension adds information; the old weights need
to be re-optimized in the new feature space.

**Extension to multi-predicate discovery**
The shadow gradient approach works for any predicate × substrate combination. For a new
unknown predicate: train the cheapest substrate (degree-1), compute shadow gradients for
degree-2 monomials, add top candidate, retrain. This is the outer loop of automatic
substrate discovery.

**Connection to active learning**
Shadow gradients identify which features to REQUEST, not just which to compute. In an
active learning setting where features are expensive to collect, the shadow gradient
prioritizes feature collection effort.

See: `predicate_tomography.md`, `symmetry_discovery.md`, `higher_order_closure.md`.
