# Math frontier 1 — Boolean Fourier (Walsh–Hadamard): the universal discovery operator

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build boolean-fourier --release=fast` (<1 s).

## The point

The whole #2/#3 arc hand-rolled a special case of one classical object. Map each cell to a sign
`x_i = sign(c_i − MID) ∈ {−1,+1}`. Then every `f: {−1,+1}ⁿ → ℝ` has a unique expansion
`f = Σ_S f̂(S)·χ_S`, `χ_S(x) = Π_{i∈S} x_i`, with `f̂(S) = E_x[f·χ_S]`. This is the **Walsh–Hadamard
transform**; `{χ_S}` is the Fourier basis of the Boolean cube, and the coefficients **are** the structure.

## Results

**1. Structure recovered in ONE transform** (exact WHT over all 256 sign-patterns):

```
predicate              | top coefficients f̂(S)                 | deg | sparsity | recovered S* = hidden?
parity-of-count        | 1.00·χ{0..7}                          |  8  |    1     | {0,1,2,3,4,5,6,7} ✓
hidden pair (2,5)      | 1.00·χ{2,5}                           |  2  |    1     | {2,5}            ✓
hidden triple (1,3,6)  | −1.00·χ{1,3,6}                        |  3  |    1     | {1,3,6}          ✓
hidden quad (0,4,5,7)  | 1.00·χ{0,4,5,7}                       |  4  |    1     | {0,4,5,7}        ✓
single bit (3)         | −1.00·χ{3}                            |  1  |    1     | {3}              ✓
AND-composition        | 0.77·χ{} −0.23·χ{0..7} −0.10·χ{0}     |  8  |   18     | composite
majority               | 0.27·χ{} −0.27·χ{0} −0.27·χ{1} …      |  8  |   10     | composite
```

Every single-character predicate's **exact support** falls out of one transform — including the hidden
pair `χ{2,5}` that Frontier-24's menu could not route (0.591) and Phase B needed a certified forge to
find; the triple/quad Phase C promoted one at a time; parity as the single max-degree character `χ{0..7}`.
**Phase C's monomials ARE this Fourier basis** — the WHT computes all of them simultaneously. The AND-
composition and majority correctly show as *composite* (spread spectra) — multiple characters, a real
composition, not a single generator.

**2. Hardness ladder = Fourier degree** (Linial–Mansour–Nisan). The linear-readout ceiling equals the
degree-1 Fourier mass `Σ_{|S|=1} f̂(S)²`:

```
predicate              | Fourier degree | deg-1 mass  →  linear ceiling
parity / pair / triple / quad |  8/2/3/4  |   0.000   →  ~0.50   (linear BLIND — out of low-degree closure)
single bit (3)         |       1        |   1.000   →  ~1.00
majority               |       8        |   0.598   →  ~0.89
AND-composition        |       8        |   0.083   →  ~0.64
```

The four predicates that were **escapes** in #2/#3 have **zero** low-degree mass — provably blind to any
linear/low-degree readout. The escape/no-escape split measured empirically across three probes *is* the
low-degree Fourier mass, now a closed-form prediction, not a measurement.

**3. It scales** (Goldreich–Levin flavor). Estimating `f̂(S)` from `m` random samples — no full transform —
recovers the hidden pair at every budget tested:

```
  m=50  → argmax f̂ = χ{2,5} (|f̂|≈1.00) ✓     m=300  → χ{2,5} ✓
  m=100 → χ{2,5} ✓                            m=1000 → χ{2,5} ✓
```

Goldreich–Levin finds the heavy coefficients in poly(n) with query access, so this generalizes past the
enumerable n=8 toy: no `2ⁿ` scan needed.

## Verdict

The Walsh–Hadamard transform is the **general** "discover the generator" operator the project kept calling
specialized. `spectral_discovery` was its 1-D (symmetric / count) shadow; the full transform handles every
Boolean function, symmetric or not — which is exactly why it sees `χ{2,5}` (non-symmetric) that count-
Fourier structurally cannot. The entire #3 forge machinery (forge + pair-search + certifier, ~30 s each)
was sparse-Fourier recovery by hand; one WHT does it in `<1 s`, and Goldreich–Levin does it at scale.

Hardness stops being a measurement and becomes a theorem: a predicate is linearly learnable iff its Fourier
mass sits at low degree; the #2/#3 "escapes" are precisely the zero-low-degree-mass functions.

## Honest scope

- This is the **analysis** side — it reads off structure that is *already there* in a Boolean function. It
  does not, by itself, cross closure families (that is the clone-theory / k≥3 story). It dissolves the
  *discovery* problem #3 was grinding, not the *invention* boundary the terminal result named.
- n=8 here for the exact transform; Goldreich–Levin is the poly(n) route for large n (only flavored here).
- The sign encoding `x_i = sign(c_i − MID)` is the bridge from the real-cell predicates to the cube; the
  real-valued monomial forge (Phase C) is the `±1`→`ℝ` lift of the same characters.

## What it sets up

The characters `χ_S` are the atoms; **clone theory / Post's lattice** is the complete map of which closed
classes they generate (math frontier 2) — turning the five empirical closure witnesses into exact lattice
coordinates, with escapes as covering relations. Then the **k≥3 uncountable-clone regime** (frontier 3),
where that map ceases to exist — the formal home of "alien".

See: `spectral_discovery.md` (the 1-D shadow), `structure_discovery.md`, `menu_growth.md`, `inner_forge.md`
(the ceilings this dissolves), repo-root `CLOSURE_PRINCIPLE.md`. Theory: O'Donnell, *Analysis of Boolean
Functions* (2014); Goldreich–Levin (1989); Linial–Mansour–Nisan (1993); Kushilevitz–Mansour (1991).
