# Frontier 3 — Clifford's bivector earns its keep: oriented predicate, shared-basis encoding

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build antisymmetric-relational`

## The gap this closes

`clifford_binding.md` (A10) and `clifford_relational.md` (F1) both found Clifford tied real
pairwise. The deflation verdict named a precise untested prediction: "Clifford pulls ahead
ONLY on an oriented/non-commutative relation." This is the constructive proof of that claim.

## Why Clifford deflated before

The prior experiments used **random per-cell roles**: each cell gets a different random
multivector basis Pᵢ. With that encoding, the geometric product geo(C0,C1) has a grade-2
component whose *magnitude* scales as cos(θv0)·cos(θv1) or sin(θv0)·sin(θv1) — both
**symmetric** in the values. The sign of the bivector flips under cell swap, but the
predicate (XOR, mass sum) was also symmetric, so the sign-flip was structurally unused.

## The correct encoding: shared-basis angle

All cells use the **same** grade-1 basis {e₁, e₂}:

    Cᵢ = cos(θvᵢ)·e₁ + sin(θvᵢ)·e₂

In Cl(2,0) (Euclidean, e₁²=e₂²=1, e₁e₂=e₁₂, e₂e₁=−e₁₂):

    grade-0[geo(C0,C1)] = cos(θv0)cos(θv1) + sin(θv0)sin(θv1) = cos(θ(v0−v1))  [SYMMETRIC]
    grade-2[geo(C0,C1)] = cos(θv0)sin(θv1) − sin(θv0)cos(θv1) = sin(θ(v1−v0))  [ANTISYMMETRIC]

Real pairwise C0⊙C1 = (cos(θv0)cos(θv1), sin(θv0)sin(θv1)) — both components **symmetric**.

## Result

Oriented predicate: y = sign(v1 − v0), θ = 0.40, VMAX = 6, 4000 samples

```
  feature                     | dim | test acc
  ----------------------------+-----+---------
  bundle Σ Cᵢ                 |   4 | 0.561   ← chance
  real pairwise sym  C0⊙C1    |   4 | 0.583   ← chance (symmetric, orientation-blind)
  Clifford grade-2  geo[e12]  |   1 | 1.000   ← WINS (bivector = sin(θ(v1−v0)))
  first-order ordered [C0;C1] |   8 | 1.000   ← also works (identity preserved)
  ground truth sin(θ(v1−v0))  |   1 | 1.000
```

Cross-check on SYMMETRIC XOR predicate:

```
  Clifford grade-2  on XOR    |   1 | 0.510   ← correctly near-chance
  real pairwise sym on XOR    |   4 | 0.836   ← symmetric product works for symmetric predicate
```

## Verdict

**Clifford wins, exactly where predicted.** The grade-2 bivector is `sin(θ(v1−v0))` — it
IS the oriented feature. A single scalar read from the grade-2 blade achieves 1.000 on the
oriented predicate, while real pairwise sits at chance (0.583). Correctly, the same grade-2
blade is near-chance (0.510) on the symmetric XOR predicate — the bivector encodes orientation
but not symmetric relational structure.

## The structural lesson (now with a formula)

Clifford earns its keep when **encoding algebra matches predicate algebra**:

| encoding     | predicate     | bivector result |
|--------------|---------------|-----------------|
| random roles | symmetric     | deflation (tied) |
| random roles | antisymmetric | deflation (magnitude-symmetric in values) |
| shared basis | symmetric     | grade-2 near-chance (correctly useless) |
| shared basis | antisymmetric | grade-2 = exact feature (WINS) |

The useful structure is not "Clifford" in the abstract — it is the specific algebraic
alignment between the encoding's unit circle and the predicate's orientation axis. When the
cell encoding maps values to angles on the SAME circle, the bivector becomes the sine of
the angular difference, which is exactly the oriented predicate's generator.

## Honest caveats

- `[C0; C1]` concatenation (first-order ordered features) also hits 1.000. So Clifford is
  not the ONLY way to read orientation — it's the way when cells are pooled symmetrically
  and identity is lost. If the system has access to per-cell ordered features, the bivector
  adds nothing. Clifford is specifically valuable when encoding symmetrises over cells
  (as in bundle/pool architectures) but the predicate breaks symmetry.
- This is a 2-cell result. With NCELL > 2, pooling all pairs geo(Cᵢ,Cⱼ) loses which pair
  matters. Clifford's orientation advantage is preserved only if the relevant pair (0,1) is
  somehow privileged in the pooling scheme.
- The oriented predicate here is linear in the angle difference. For a truly non-monotone
  oriented predicate (e.g., `sign(sin(φ(v0−v1)))` for large φ), the grade-2 feature would
  need a nonlinear readout.

See: `clifford_relational.md` (random-role deflation), `clifford_binding.md` (mass deflation),
`CLOSURE_PRINCIPLE.md` (the generator-algebra alignment principle).
