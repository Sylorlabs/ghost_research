# Math frontier 4 — tropical & the family map: the "families" are concrete incomparable closures

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build family-closures --release=fast` (<1 s).

## The point

Phase C's terminal result said a purist forge "composes down to the substrate's **family**." Frontiers 2–3
named those families as clones. This probe makes them tangible: four ALGEBRAS, four predicates each native to
one algebra, held-out accuracy. If the families are real incomparable closures, the matrix is diagonal.

| target | native algebra / closure | characteristic reader |
|---|---|---|
| `max(c) ≥ θ` | **tropical** (max-plus semiring) | max/min aggregate |
| `sum(c) ≥ K` | **real-affine** (linear) | `Σ cᵢ` |
| parity-of-count | **GF(2)-affine** (Boolean Fourier) | `χ_[n] = Π sign(cᵢ−µ)` |
| `sign((c₂−µ)(c₅−µ))` | **multilinear** (degree-2 monomial) | pairwise products |

## Results

```
target  \  family    | REAL-AFFINE | TROPICAL    | GF(2)/FOURIER | MONOMIAL  | chance
max(c) ≥ 5           |   0.783     | 1.000 ◄     |   0.762       |  0.754    | 0.762
sum(c) ≥ 20          |   1.000 ◄   | 0.695       |   0.553       |  0.523    | 0.553
parity-of-count      |   0.493     | 0.489       |   1.000 ◄     |  0.490    | 0.515
sign((c₂−µ)(c₅−µ))   |   0.518     | 0.478       |   0.496       |  1.000 ◄  | 0.505
```

Diagonal. Each algebra reads **only** its native predicate near 1.0 and sits at chance on the others. The one
off-diagonal bleed (tropical↔affine on max/sum, 0.78/0.70) is honest — both are "size" aggregates, so they
correlate. No family is universal.

## Verdict

The "families" the terminal result named are **not a metaphor** — they are concrete, incomparable **closures**:
max-plus (tropical), real-affine, GF(2)-affine (the Fourier characters of frontier 1), and multilinear
(monomials). A search closed under one algebra reaches exactly that algebra's closure and no further — Phase C,
restated in algebra. Crossing to another family needs an out-of-family generator.

**Tropical earns its name.** `(ℝ∪{−∞}, max, +)` is the algebra the project's order-statistic and power-mean
work (`concentration_control.md`, `representation_discovery.md`) was already using without naming it: `max` is
the tropical sum, a power-mean `p→∞` is the tropical limit. Here it's a first-class family, and it cleanly owns
the order-statistic predicate that affine/Fourier/monomial all miss.

This is the **finite-domain shadow of the k≥3 cliff** (frontier 3): finitely many incomparable families here,
uncountably many in the wild. And the irreducibility certifier that policed every escape in Phase B
(`menu_growth.zig`) is a **matroid closure operator** — independence = not-reconstructible, rank = basis size,
and a **circuit** (a set dependent as a whole but independent in every proper subset) is exactly an *emergent
escape* (`emergent_escape.md`: a target needing `{X,Y}` but neither `{X}` nor `{Y}`). Matroid theory is the
exact formalism for "which generators are needed."

## The whole arc in one sentence

Across the four math frontiers: **a search closed under an algebra reaches exactly that algebra's closure** —
the Walsh–Hadamard basis *reads* the closure (frontier 1), Post's lattice *classifies* it for k=2 (frontier 2),
Janov–Mučnik shows the classification *dies* at k≥3 (frontier 3), and the family matrix shows the closures are
concrete and incomparable (frontier 4). The repo's entire empirical invention story — closure ceilings,
escapes, the forge bottoming out — is one theorem in universal algebra, now named, mapped, and measured.

## Honest scope

- Each family is represented by its *characteristic aggregate*, not its full clone, so the matrix shows the
  natural reader of each algebra, not a completeness claim. The diagonal is the point: the aggregates do not
  substitute for one another.
- The tropical↔affine bleed is real and expected (both monotone size statistics); it does not undermine
  incomparability (each still strictly owns its native target; neither reads parity or the pair-product).
- Matroid is stated as the correct formalism (with the existing `emergent_escape`/`menu_growth` results as its
  instances), not re-derived as a new computation here.

See: `concentration_control.md`, `representation_discovery.md` (the tropical work, now named), `menu_growth.md`
(the matroid certifier), `emergent_escape.md` (circuits), `boolean_fourier.md`, `clone_lattice.md`,
`kary_frontier.md`, repo-root `CLOSURE_PRINCIPLE.md`. Theory: Maclagan–Sturmfels, *Introduction to Tropical
Geometry* (2015); Oxley, *Matroid Theory* (2011).
