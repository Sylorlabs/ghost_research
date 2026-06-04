# Frontier 5 — composed discovery: the closure principle applies recursively

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build composed-discovery`

## What this tests

All prior discovery experiments involved *single* primitive families — one unknown generator,
one discovery operator. This is the first test of **composed** primitives: two families
nested, where neither single operator suffices. Discovery must be STAGED.

## Family A — inversion-parity (CONFIRMED)

    S(grid) = #{pairs (i,j): i<j AND cell[i] > cell[j]}   (inversion count)
    y       = S mod 2                                       (parity of inversions)

This is "periodic in a relational statistic." The generator is ω=π applied to S, but S is
itself a relational quantity (pairwise order comparisons), not the raw cell count.

```
  operator                           | found ω  | test acc
  -----------------------------------+----------+---------
  spectral on raw cell count         |  1.3404  |  0.519   ← wrong domain, fails
  pairwise comparisons + linear      |    —     |  0.499   ← no period detection, fails
  spectral on inversion count S      |  3.1416  |  1.000   ← correct: step 2 only
  STAGED (sum pairs → S, spectral S) |  3.1416  |  1.000   ← full two-step pipeline
```

**Verdict:** Both single operators fail (chance). The staged pipeline — sum all pairwise
comparison bits to recover S, then apply the spectral operator to S — finds ω=π exactly
and achieves 1.000. The composition is the escape.

Note on the staged pipeline: the sum of pairwise comparison indicators equals the inversion
count by definition. So the "inner transform" (pairwise binary comparisons → S) is itself
the kind of relational binding explored in `clifford_relational.md` — the outer periodic
structure is then found by the spectral operator from `spectral_discovery.md`. Two known
single-step discoveries compose into one two-step discovery for a new family.

## Family B — product-parity (PARTIAL / sobering)

    P = cell[0] * cell[1]    y = P > K/2

Spectral on sum partially worked (0.829). Sum-squared features reached 1.000.

**Why sum² works:** (v0+v1)² = v0²+2v0v1+v1² contains the product v0v1 in its cross-term.
The product-parity predicate is a smooth threshold on P — the degree-2 polynomial in
(v0+v1) leaks enough information about P to hit 1.000. Family B is therefore NOT a clean
composed case: the inner transform (multiplication) is recoverable from degree-2 features
of the sum, and the outer structure (threshold) is smooth enough for polynomial approximation.

**Lesson:** composition hardness depends on whether the inner transform is *recoverable*
from out-of-closure features of the simpler domain. Here it is, so composition does not
create a genuine new ceiling. A harder Family B would require P to appear in a *periodic*
outer structure (e.g., P mod K > K/2 with K prime and values spanning full range), where
sum-polynomial approximation cannot mimic the product.

## The deep result

Family A confirms the structural claim: **the closure principle applies recursively**.

Each layer of a composed primitive is a separate closure barrier:
1. The raw cell count is in the closure of "count-above-threshold" (threshold function).
   But the inversion count S is NOT — it requires pairwise relational structure.
2. S mod 2 (parity of S) is not in the closure of S-linear readouts.
   It requires the spectral (period-detecting) operator applied to S.

Neither layer's operator can substitute for the other:
- Spectral on raw count finds the wrong ω (1.34, not π) and achieves chance.
- Pairwise linear captures the relational structure but cannot detect periodicity.
- Only the composition — extract S first, then apply spectral — succeeds.

This is the same "closure all the way up" conclusion as wcore Claim C and `family_gradient.md`,
now measured for a COMPOSED family rather than a single-level one.

## What this opens

The staged pipeline works here because we knew the decomposition: S is the inversion count,
and periodicity is the outer structure. The genuinely unknown next question:

**Can the decomposition itself be discovered?** Given a black-box composed predicate:
1. How does a discoverer infer that the relevant inner quantity is relational (not raw count)?
2. How does it infer the outer structure is periodic (not threshold or polynomial)?

A meta-discovery system would need to:
- Probe residuals: does applying spectral to raw count leave a structured residual?
- Enumerate candidate inner transforms: sum, max, inversion count, product, ...
- For each candidate, test whether the outer operator succeeds.

This is a search over (inner transform, outer operator) pairs — itself a closure problem
one level up. The discoverer of the decomposition requires its own out-of-closure generator.

See: `spectral_discovery.md`, `clifford_relational.md`, `family_gradient.md`,
`CLOSURE_PRINCIPLE.md`, `composed_discovery.zig`.
