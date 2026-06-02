# The closure principle on a real problem: k-sparse parity

**Status:** built, measured. Reproduce: `zig build parity`. This applies the
method to a *canonical, un-invented* learning-theory problem rather than a toy I
designed — the honest test of whether the closure principle generalises.

## Why parity

Parity (`y = XOR` of k specific input bits) is the textbook out-of-linear-closure
function: for k ≥ 2 every individual bit is statistically independent of `y`, so a
linear model has *zero* signal and provably sits at chance. It is the learning-
theory twin of `affine_closure` (mixers can't get avalanche) and the band-readout
ceiling (XOR/bundle can't read the sum). If the closure principle is real, it
should predict (a) exactly where the ceiling appears and (b) what escapes it.

## Results (16 bits, 20000 train / 5000 test)

```
  k | linear(raw) | MLP(raw) | linear(+ product monomial)
  --+-------------+----------+---------------------------
  1 |    1.000    |   1.000  |          1.000
  2 |    0.505    |   1.000  |          1.000
  3 |    0.520    |   1.000  |          1.000
  4 |    0.500    |   1.000  |          1.000
```

- **The ceiling is exactly at k ≥ 2,** as the theorem says. k=1 parity is a single
  bit (in the linear closure → 1.000); k ≥ 2 collapses linear to chance.
- **Escape 1 — a nonlinearity.** A small MLP (16→32 ReLU→1) solves every k → 1.000.
- **Escape 2 — the explicit generator.** Append the *product monomial* of the
  relevant bits and a *linear* model solves it (1.000): the product is the
  out-of-closure generator that makes parity linear in the lifted space — the
  direct analogue of MUL for mixers and the SUM for control.

## Honest placement

Parity-hardness for linear models is a *known* result (it's the standard example
of linear inseparability). The contribution here is not the fact; it is that the
**same** closure principle that organises `affine_closure`, the band-readout
ceiling, and wcore's Claim C *predicts this real problem's ceiling and its
generator without modification.* Parity becomes a fifth witness, and the only one
that is a textbook problem rather than a repo artefact.

## The real frontier it points at

At this scale even k=4 is solved by the MLP, because 20000 samples is plenty to
find a 4-bit interaction in 16. The genuine hardness — an actual open research
topic — is **large-k sparse parity**: as k grows and the relevant subset hides
among many irrelevant bits, SGD on a generic MLP needs exponentially many samples
to *find* the interaction. That is the same wall one level up: the generator (the
right monomial) exists in the MLP's closure but is exponentially hard to *locate*.
"Discovering the generator" is easy when it is cheap to find and hard exactly when
it is not — the discovery ladder of `feature_discovery.md`, now on a real problem.
