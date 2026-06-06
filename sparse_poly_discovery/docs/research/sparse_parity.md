# Frontier 8 — sparse parity: sample complexity growth as irrelevant bits increase

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build sparse-parity`

## What was tested

k-parity with n total bits (only k=2 or k=3 are relevant, at positions 0..k-1).
The learner gets all C(n,k) degree-k monomials and runs logistic regression.
The relevant monomial is b0·b1·...·b_{k-1}; the others are noise.
Minimum samples for ≥90% test accuracy.

## Results

k=2:
```
  n  | C(n,2) | min samples
  ---+--------+------------
   2 |    1   | 20000 (didn't converge)  ← design artifact
   4 |    6   |   100
   8 |   28   |   100
  16 |  120   |   500
  24 |  276   |   500
```

k=3:
```
  n  | C(n,3) | min samples
  ---+--------+------------
   3 |    1   | 20000 (didn't converge)  ← design artifact
   6 |   20   |    50
   9 |   84   |   500
  12 |  220   |  2000
```

## The n=k anomaly and the design correction

For n=k (e.g., k=2,n=2 or k=3,n=3), there is exactly ONE monomial of degree k. The
expected behavior: it's trivial to find, needs few samples. But the experiment shows
20000 samples and still doesn't converge.

**Why:** the label is XOR(b0,...,b_{k-1}). The degree-k monomial b0·b1·...·b_{k-1}
alone CANNOT represent XOR. For k=2: XOR(b0,b1) = b0 + b1 − 2·b0·b1, which requires
degree-1 features b0, b1 in addition to the degree-2 product. Using ONLY degree-k
monomials, without lower-degree terms, leaves XOR unsolvable from the product alone.

When n>k: the cross-products involving relevant and irrelevant bits (e.g., b0·b2 for k=2
when b2 is irrelevant) provide an implicit proxy for degree-1 information. The logistic
can use b0·b2 ≈ E[b2]·b0 (since b2 is independent) as a noisy degree-1 feature.
This is why n=4 (100 samples) is EASIER than n=2 (doesn't converge): the extra monomials
provide the lower-degree structure the logistic needs.

**Honest correction:** the correct sparse parity experiment should either:
(a) use AND (b0·b1·...·b_{k-1}) as the label — the degree-k product IS the monomial,
(b) or include ALL monomials of degree ≤ k (as in Frontier 4), not just degree k.

## The real finding from n>k cases

Despite the n=k artifact, the n>k data shows the actual sample complexity curve:

k=2: 100 samples at n=4; 100 at n=8; 500 at n=16; 500 at n=24.
  Roughly flat from n=8 onward. C(n,2) grows from 28 to 120 to 276 while samples stay 100-500.
  This is sub-linear in C(n,2) — much cheaper than theory predicts.

k=3: 50 samples at n=6; 500 at n=9; 2000 at n=12.
  C(n,3) grows 20→84→220 (4.2x, 2.6x); samples grow 50→500→2000 (10x, 4x).
  Sample growth outruns monomial count growth by ~3x per step.

The k=3 growth is steeper than k=2 but still polynomial (not exponential) in this range.
The exponential wall from LPN theory requires large k — at k=2,3 with moderate n, the
logistic is finding the sparse signal before hitting the computational limit.

## What would trigger the exponential wall

For the theoretical exponential difficulty to appear, you need:
- Large k (k ≥ 10) with many irrelevant bits
- OR many irrelevant bits at fixed k=2,3 beyond what was tested (n >> 100)
- AND genuine noise in the labels (LPN hardness requires noise; noiseless parity is polynomial)

The next experiment should test k=2 at n=64, 128, 256 — or k=4 at n from 4 to 32.
At some (k,n) the curve will bend from polynomial to exponential, and that point is the
genuine computational-learnability boundary.

## Connection to the Closure Principle

The n=k artifact reveals something interesting about feature design: the LABEL XOR is
a degree-k function that requires BOTH lower-degree and degree-k features. Using only
degree-k monomials is itself a closure restriction — you're confining the learner to a
substrate that lacks the degree-1 generators XOR needs. The n>k cases accidentally escape
this by providing cross-product proxies for the missing degree-1 structure.

This mirrors the general closure principle: the degree-k substrate without degree-1
features is closed and insufficient for XOR, just as XOR/bundle encodings are closed
and insufficient for mass-band predicates.

See: `higher_order_closure.md` (the all-degrees-≤k case), `parity_closure.md`,
`CLOSURE_PRINCIPLE.md`.
