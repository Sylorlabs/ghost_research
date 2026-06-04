# The Invention Bridge: Inferring the Primitive Class a Target Needs

**Status:** built, measured. 6/6 known-class targets correctly diagnosed; out-of-ladder
target correctly flagged. Reproduce: `zig build order-stats -- diagnose`

## The Point

The project's recurring struggle was **feature discovery** — blind O(N²)/O(N³) pair/triplet
searches over a hand-built feature menu. The closure-lattice results
(`order_statistics_closure.md`, `basis_degree_control.md`) map *what kind of primitive* each
function class needs. This turns discovery from a blind flat search into a **principled
ascent of a short ladder**: given a target, find the minimal rung that captures it — that
rung IS the primitive class the target needs.

This is the bridge from *mapping* the lattice to *using* it: a system that, handed a target,
**infers the primitive class** rather than enumerating feature combinations.

## The Ladder (nested, symmetric, O(1)-scaled)

Each basis is a superset of the previous; all features are per-cell means so one learning
rate trains every rung:

| rung | adds | feature(s) | the closure it tests |
|------|------|-----------|----------------------|
| B1 | linear | `mean` | linear closure (degree-1 symmetric) |
| B2 | quadratic | `mean(x²)`, `mean²` | quadratic closure (incl. the two-sided band's `(Σx)²`) |
| B3 | extremal | `max`, `min` | + extremal order statistics |
| B4 | rank-1 | `median` | + one central rank feature |
| B5 | rank-2 | `Q1`, `Q3` | + a 2-D rank feature (quartile pair) |

## Inference Rule

Train each rung, get held-out accuracy. The needed primitive is where the **largest
marginal accuracy jump that crosses into high accuracy (≥0.9)** occurs — the rung that adds
the feature the target actually depends on. If no rung crosses, the target is **beyond the
ladder** (the system knows its own limits).

## Result (6/6, validated against known classes)

```
  target           |   B1    B2    B3    B4    B5  | inferred       (expected)
  -----------------+------------------------------+--------------------------
  sum>=K           | 1.00  1.00  1.00  1.00  1.00 | B1 linear      (B1 linear)     OK
  band |sum-C|<=R  | 0.50  0.91  0.89  0.89  0.89 | B2 quadratic   (B2 quadratic)  OK
  max>=T           | 0.68  0.74  1.00  1.00  1.00 | B3 +extremal   (B3 +extremal)  OK
  median>=T        | 0.83  0.83  0.85  1.00  1.00 | B4 +rank1      (B4 +rank1)     OK
  IQR>=T           | 0.48  0.78  0.79  0.79  1.00 | B5 +rank2      (B5 +rank2)     OK
  parity(count)    | 0.50  0.50  0.50  0.57  0.57 | beyond ladder  (beyond ladder) OK
```

Each target's needed primitive is localized by its jump: the band first separates at the
quadratic rung, `max` at the extremal rung, `median` at rank-1, `IQR` only at rank-2 — and
**parity-of-count never crosses** (it needs ~degree N, which the ladder does not provide),
so it is correctly flagged beyond the ladder rather than mis-attributed.

## Honest Grade

- **What it shows:** the closure lattice gives a *principled, short* ladder that correctly
  identifies the primitive class of a target in one ascent — replacing blind O(Nᵏ) feature
  search — and the system reports when a target is beyond its known primitives.
- **What it does NOT show:** this is a **diagnoser, not a generator** — the ladder of
  primitives is hand-built from the prior results; it does not *invent new* primitives. It
  is validated on targets whose class we already knew (not discovery of unknown structure);
  the contribution is the principled localization + the out-of-ladder flag, not novelty
  detection. Parity is flagged beyond, not solved.
- **Two engineering facts were load-bearing** (honest, because they nearly hid the result):
  (1) **feature scaling** — a raw `(Σx)²` feature (~10² scale) swamps the order-statistic
  features (~1) under a single learning rate, dropping even `max` to chance; per-cell-mean
  features fixed it. (2) **convergence** — the band is exactly quadratic-separable but
  logistic SGD needed more epochs/step to grow the weights enough to show it (0.85 → 0.91).
  Both are optimization artifacts, not closure facts; worth recording so they aren't
  mistaken for capability limits.

## Closing the Loop: Forge + Promote on Beyond-Ladder

Reproduce: `zig build order-stats -- forge`

The diagnoser flags parity-of-count **beyond** B1..B5. The invention step
(`RESEARCH_QUESTIONS.md` #1, the only place "yes it can invent" is possible): search a
**principled primitive family** for a member that crosses the target, then **promote** it.
Parity is periodic in the count `c`, so the family is count-Fourier features
`cos(ω · #{cells ≥ H})`, searched over a grid of `(H, ω)`:
```
  cos(0.2 · #cells>=5)  (low freq)  | 0.501
  cos(pi/2· #cells>=5)  (period 4)  | 0.482
  cos(pi  · #cells>=3)              | 0.524
  cos(pi  · #cells>=4)              | 0.544
  cos(pi  · #cells>=5)              | 1.000   <-- CROSSES -> promoted
  cos(pi  · #cells>=6)              | 0.503
```
The forge finds *exactly* the member matching the target's structure (`H=5, ω=π`, i.e.
`(-1)^c`) and promotes it; every decoy (wrong frequency, wrong threshold) fails. The
beyond-ladder target is now **in the extended closure**. This is the full loop:
**diagnose → beyond ladder → forge from a family → promote → captured.**

**Honest limit (the real frontier).** Three things make this a *demonstration of the
mechanism*, not full invention: (1) the family `cos(ω·count)` is chosen *knowing* parity is
periodic — a general forge would have to choose/grow the family too, from a large library or
a generative grammar. (2) it is a small **grid search** over `(H, ω)`, not **gradient
discovery** of `ω`; learning the parity frequency by gradient is the canonical hard case and
would likely fail (a useful future negative). (3) "promote" here just adds the feature; a
real open-atom-set loop would re-run the *whole* diagnoser with the enlarged basis and ask
whether the *next* round finds something irreducible to the enlarged set (#1–#6 of the
research agenda). So: the forge+promote *plumbing* works and is clean; the open problem is
forging primitives whose *family was not handed in advance*.

## Why It Matters / Next

This is the smallest honest version of "a system that knows which primitive a problem needs,
and forges a new one when stuck." The frontier above — discovering the primitive *family*
itself, and learning continuous primitive parameters by gradient where grid search won't
scale — is the line between this working demo and genuine open-ended invention.

See: `order_statistics_closure.md` (the lattice this ladder is built from),
`basis_degree_control.md`, `representation_discovery.md`, repo-root `CLOSURE_PRINCIPLE.md`.
