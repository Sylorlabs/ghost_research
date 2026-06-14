# Boundary crossing 1 — real mathematics as the out-of-substrate ingredient (certified)

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build world-injection --release=fast` (~2 s).

## Why this is the first genuine escape in the whole arc

Every prior result *relocated* a closure; none escaped one. The terminal result
(`sparse_poly_discovery/docs/research/inner_forge.md`) + Post's lattice (`clone_lattice.md`) proved why: a
purist symbolic forge composes down to its substrate's family and stops. The Closure Principle says the only
escape is to **inject a generator from outside any fixed substrate.** This probe does that, with no LLM, and
certifies it — the FunSearch shape (external source + verifier) in its most purist form: the source is **real
mathematics**, the verifier is the project's own closure diagnostic.

## Method

The substrate is the bits of `n`; the algebraic closure is the low-degree / sparse **Walsh–Hadamard (Fourier)**
basis (`boolean_fourier.md`). Two steps:

1. **Closure diagnostic.** For real Boolean functions of `n`, transform and classify: *IN* the closure
   (discriminative low-degree mass, or a few dominant characters — the world re-using known algebra) vs *OUT*
   (Fourier-flat — structure no algebraic forge contains). The `deg1-2 mass` excludes the constant `∅` bias, so
   it measures *discriminative* low-degree structure, not class imbalance.
2. **Certified crossing.** For a Fourier-flat target (primality), show the algebraic reader is blind, a
   number-theoretic generator the world provides (divisibility / the sieve) captures it, and that generator is
   irreducible to the algebra.

## Results

```
sequence         | deg1-2 mass | max deg | sparsity | deg≤2 readout (adv) | low-deg Fourier?
Thue-Morse       |   0.000     |   13    |    1     |  0.500 (+0.000)     | IN  (sparse character = χ_[13])
bit_6            |   1.000     |    1    |    1     |  1.000 (+0.500)     | IN  (low-deg learnable)
n mod 3 = 0      |   0.000     |   13    |   93     |  0.667 (+0.000)     | OUT (Fourier-flat — periodic)
n mod 7 = 0      |   0.000     |    9    |   88     |  0.857 (+0.000)     | OUT (Fourier-flat — periodic)
Hamming majority |   0.567     |   13    |  106     |  1.000 (+0.291)     | IN  (low-deg learnable)
Rudin-Shapiro    |   0.010     |    0    |    0     |  0.506 (−0.002)     | OUT (Fourier-flat — the textbook flat spectrum)
squarefree       |   0.494     |   13    |   49     |  0.858 (+0.250)     | IN  (low-deg learnable)
PRIMALITY        |   0.066     |   13    |    8     |  0.875 (+0.000)     | OUT (Fourier-flat)
```

```
── certified crossing on PRIMALITY ──
  ALGEBRAIC reader (degree-≤2 Fourier)      : 0.875   (= base rate → advantage +0.000)   BLIND
  WORLD generator (sieve: divisibility/24p) : 0.997   (held-out → advantage +0.123)      CAPTURES IT
  irreducibility — low-deg Fourier on mod-3 : 0.667   (= base → advantage +0.000)        SIEVE ∉ algebra
```

## Verdict — boundary crossed, certified

The algebraic substrate is provably **blind** to primality (degree-≤2 advantage +0.000 — no structure). A
generator **real mathematics provides** — divisibility by small primes, the sieve — captures it at 0.997
held-out. And the sieve is **irreducible** to the algebra: low-degree Fourier cannot reconstruct even a single
sieve primitive (`n mod 3`, advantage +0.000). The escape did not come from composing the substrate; it came
from **outside** it, and the certifier (held-out accuracy + irreducibility) keeps it only because it provably
escapes. This is the first result in the arc that escapes a closure rather than relocating it.

The diagnostic also shows the **honest other half**: not all of mathematics is out-of-closure. Thue–Morse *is*
a Fourier character (the world recombining known algebra); Hamming majority and squarefree are low-degree
learnable. Invention is exactly the **OUT** rows — structure the substrate could never have forged. The
periodic rows (`mod 3`, `mod 7`) are OUT of *low-degree Fourier* specifically (they live in the cyclic family);
primality is the deep one, flat against the algebraic basis and captured only by the multiplicative/sieve
structure of the integers.

## Honest scope

- "OUT" means **out of the low-degree/sparse Fourier closure**, the specific algebraic family tested — not out
  of *all* possible algebra (e.g. `mod 3` is periodic, simple in the cyclic family). The rigorous claim is the
  certified primality crossing: blind algebra + capturing world-generator + irreducibility.
- The sieve reader is a *fitted* logistic over 24 divisibility features; 0.997 (not 1.000) reflects the small
  primes ≤ 90 missing a few large-factor composites and the prime-self edge cases — real, reported, not hidden.
- This is a **single** certified crossing, not yet the closed engine. It demonstrates the architecture; the
  loop (below) is the engine.

## The engine (next)

`world_injection.zig` proves one crossing. The invention engine is the closed loop **inject → certify →
promote**: stream real mathematical targets, run the closure diagnostic, keep the certified-OUT generators,
grow a library, recurse. Same certifier, swappable source — real datasets, a verifiable external unknown
(superoptimization vs `-O3`, an open conjecture), or (if ever wanted) an LLM subordinated to the certifier.
The terminal result proved no closed substrate produces this alone; the out-of-substrate ingredient is what
makes it invention rather than recombination.

See: `../README.md`, `sparse_poly_discovery/docs/research/{inner_forge,boolean_fourier,clone_lattice,kary_frontier}.md`,
repo-root `CLOSURE_PRINCIPLE.md`, `RESEARCH_QUESTIONS.md` §J. Method/prior art: FunSearch (Romera-Paredes et
al., *Nature* 2023); AlphaEvolve (2025).
