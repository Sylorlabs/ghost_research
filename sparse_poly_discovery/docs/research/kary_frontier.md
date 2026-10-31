# Math frontier 3 — the k≥3 cliff: where the classification of closures ceases to exist

**Status:** built, measured + exposition. Reproduce: `cd sparse_poly_discovery && zig build kary-frontier --release=fast` (<1 s).

## The point

Frontier 2 showed the Boolean closure world is *fully mapped* (5 maximal clones, countable lattice, closure
questions = finite property checks). That completeness is **exactly why the purist-invention story terminated
cleanly** — every ceiling was a maximal-clone membership, every escape a covering relation. This frontier
shows the map is a privilege of the 2-element domain, and names the regime where it ends.

## Results

**k=2 is fingerprint-navigable.** Every binary op carries a 5-bit maximal-clone fingerprint; universality is
*exactly* an empty fingerprint (Post). Enumerating all 16:

```
  0x1 NOR   · · · · ·   UNIVERSAL          0x6 XOR   ✓ · · · ✓   (T0,L)
  0x7 NAND  · · · · ·   UNIVERSAL          0x8 AND   ✓ ✓ ✓ · ·   (T0,T1,M)
  → exactly 2/16 binary ops are universal (the Sheffer functions). The closure question is a 5-bit check.
```

**The combinatorial jump at k≥3** (raw structure — illustration, not the proof):

```
                         k=2        k=3          k=4
  binary ops  k^(k²)   :  16        19 683       4.3·10⁹
  idempotent  k^(k²−k) :  4         729          1.7·10⁷
  ternary ops k^(k³)   :  ~10²      ~10¹³        ~10³⁹
```

**The cliff (the theorems):**

```
                           | k=2 (Boolean)         | k≥3
  maximal clones           | 5  (Post 1941)        | finite, classified (Rosenberg 1970): k=3 → 18
  TOTAL # of clones        | ℵ₀  (countable)       | 2^ℵ₀  CONTINUUM (Janov–Mučnik 1959)
  finite closure fingerprint | YES (5 bits)        | IMPOSSIBLE — no finite property set separates 2^ℵ₀ clones
  closure-membership       | finite property check | decidable, but the lattice has infinite antichains
```

## Verdict

The complete map of closures — the thing that let purist invention terminate cleanly — exists **only at k=2.**
The *top* of the lattice (maximal clones) stays finite for every k (Rosenberg), but the lattice **itself**
jumps from countable to a **continuum** the instant k≥3 (Janov–Mučnik). No finite fingerprint, no Post diagram,
no navigable map can exist.

This is the precise mathematical content of "alien, no human would think of it." In the k≥3 regime, *"what lies
outside my closure"* is **not a finite question.** A 2-valued (true/false) substrate — every predicate engine in
this repo so far — is forever navigable, and therefore forever bounded: that is *why* the forge always bottoms
out and Post's lattice always names the escape in advance. Genuine unmappable novelty requires leaving the
Boolean cube for a **many-valued / continuous** substrate, where the closure structure is itself uncountable.

This **meets the terminal result from the opposite side.** Phase C concluded (from below) that a purist forge
composes down to its substrate's family; this frontier shows (from above) that the *space of families* is finite
and mapped only for k=2, and uncountable/unmappable for k≥3. Both say the same thing: escape needs an
out-of-substrate ingredient — and now we know precisely what richer substrate could even host unbounded
invention: one whose closure lattice is *not classifiable*, i.e. k≥3 / continuous, not Boolean.

## Honest scope

- The op-count explosion **illustrates** combinatorial vastness; it is **not** the proof of uncountability
  (k=2 also has astronomically many high-arity ops yet countably many clones). The uncountability is the
  structural Janov–Mučnik theorem (infinite antichains of clones), cited, not re-derived here.
- This frontier is exposition + a navigability demonstration, not a new engine. It tells you *where* to build
  if you want unbounded invention (the k≥3 / continuous regime), not how — that is open, and genuinely hard,
  precisely because it is unmappable.

## What it opens

The same closure question, asked in a *different algebra*: math frontier 4 (tropical / matroid) shows the
"families" the terminal result names are concrete algebraic structures (max-plus order statistics; matroid
closure of the irreducibility certifier) — several incomparable closures, none universal, which is the
finite-k shadow of this cliff.

See: `clone_lattice.md` (k=2, fully mapped), `inventable_substrate_design.md` and `inner_forge.md` (the terminal
result this meets from above), `boolean_fourier.md`, repo-root `CLOSURE_PRINCIPLE.md`. Theory: Janov–Mučnik
(1959); Rosenberg (1970); Lau, *Function Algebras on Finite Sets* (2006).
