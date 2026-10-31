# Math frontier 2 — Post's lattice: the complete classification of Boolean closures

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build clone-lattice --release=fast` (<1 s).

## The point

The Closure Principle, for Boolean functions, is not an empirical discovery — **Emil Post (1941) classified
every closed class.** A *clone* is a set of operations closed under composition (+ projections). Post proved
there are exactly **five maximal clones** over {0,1}, each a single preservation property:

`T0` 0-preserving · `T1` 1-preserving · `M` monotone · `D` self-dual · `L` affine (GF(2)-linear).

Two consequences make the repo's empirical closure work *exact*:
1. **Post's completeness criterion (a theorem):** a gate set generates *all* Boolean functions ⟺ it escapes
   all five maximal clones.
2. **Closure-membership is decidable** (open RQ #37, settled for the Boolean case): `g ∈ clone(F)` has a sound
   necessary test — every maximal clone containing `F` must contain `g`. The five preservation checks are
   the Pol–Inv / invariant-relation idea, computable.

## Results

**Each gate's maximal-clone memberships** (computed):

```
gate    | T0  T1  M   D   L
AND     |  ✓   ✓  ✓   ·   ·     ← monotone, not affine
XOR     |  ✓   ·  ·   ·   ✓     ← affine, not monotone
NOT     |  ·   ·  ·   ✓   ✓
MAJ3    |  ✓   ✓  ✓   ✓   ·     ← self-dual monotone, not affine
NAND    |  ·   ·  ·   ·   ·     ← escapes all 5
```

**Substrate completeness** (Post's criterion):

```
{XOR}              ⊆ T0∩L        limited   ← the GF(2)-linear mixer
{XOR, CONST1}      ⊆ L           limited   ← the affine mixer ceiling
{AND}              ⊆ T0∩T1∩M     limited   ← the Phase-C monomial substrate
{AND, XOR}         ⊆ T0          limited   ← needs a constant to escape T0
{AND, XOR, CONST1} ⊆ (none)      UNIVERSAL ← GF(2) ring with 1
{AND, NOT}         ⊆ (none)      UNIVERSAL
{NAND}             ⊆ (none)      UNIVERSAL ← Post's criterion confirms the folklore
{MAJ3}             ⊆ T0∩T1∩M∩D   limited
```

**The repo's ceilings ARE maximal-clone obstructions** (one-line, provable):

```
affine ceiling (05_meta_synthesis):  AND ∈ clone({XOR})?      NO — clone(F) ⊆ L,    AND ∉ L
Phase-C saturation (inner_forge.md):  XOR ∈ clone({AND})?      NO — clone(F) ⊆ T1∩M, XOR ∉ both
the escape:                           XOR ∈ clone({AND,NOT})?  YES — escapes all 5 ⟹ universal
```

## Verdict

Every empirical closure ceiling in the repo is **membership in a maximal clone**, and every escape is
**leaving one** — known in advance from the lattice, not discovered by a forge:

- the mixer's GF(2)-affine wall (`05_meta_synthesis`) = `⊆ L`; ADD/MUL escape = leaving `L`.
- Phase C's monomial forge could not reach parity = `clone({AND}) ⊆ M` while `parity ∉ M` (XOR(0,1)=1 >
  XOR(1,1)=0). **The 30-second saturation experiment of `inner_forge.zig` is this single lattice fact.**

**The grand unification of the whole #3 arc:** the "wall between families" every probe kept hitting is the
gap between the maximal clones **M** and **L**. The Fourier basis (`boolean_fourier.md` — characters `χ_S`,
parities) lives in **L** (affine); the monomial basis (AND-products) lives in **M∩T0∩T1**. Neither forge
could cross because `L` and `M` are *different maximal clones*. You can read that off Post's lattice before
running anything. "Can substrate S invent predicate P?" is, over {0,1}, a **finite property check, not a
search.**

## The catch — why this is not the end (and where "alien" lives)

This complete map exists **only for the 2-element domain.** Post's lattice is countable and fully drawn. By
**Janov–Mučnik (1959)**, for any domain with `k ≥ 3` elements there are **uncountably many** clones (2^ℵ₀) —
no Post-style classification exists or can exist. The *maximal* clones stay finite and classified for every
`k` (Rosenberg 1970), but the lattice in between explodes to a continuum with infinite antichains. That is
exactly where invention stops being navigable by any finite map — math frontier 3.

## Honest scope

- The five-property test gives **exact universality** (Post) and a **sound necessary** membership test; full
  `g ∈ clone(F)` membership is decidable but not always settled by the five maximal clones alone (the lattice
  has more clones than their intersections). For the repo's witnesses the obstruction is always one of the
  five, so the necessary test is conclusive here.
- This is *placement*, not new invention: it explains and predicts the ceilings rigorously. The terminal
  result (purist invention bottoms out) is unchanged — Post's lattice is *why* it bottoms out, mapped.

See: `boolean_fourier.md` (the basis that lives in `L`), `inner_forge.md` (the M-vs-L wall, forged the slow
way), `structure_discovery.md`, repo-root `CLOSURE_PRINCIPLE.md`, `RESEARCH_QUESTIONS.md` §E #37. Theory:
Post (1941); Rosenberg (1970); Lau, *Function Algebras on Finite Sets* (2006); the Pol–Inv Galois connection
(Geiger 1968; Bodnarchuk–Kaluzhnin–Kotov–Romov 1969).
