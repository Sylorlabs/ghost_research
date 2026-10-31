# Boundary crossing 2 — the invention engine: the closed inject → certify → promote loop

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build invention-engine --release=fast` (~5 s).

## What it is

`world_injection.md` proved a *single* certified crossing. This is the **engine**: a closed loop that streams
real mathematical targets and, for each, either **recombines** (the current library solves it) or **invents**
(the library fails → inject an out-of-substrate generator, certify it ESCAPES and is IRREDUCIBLE, promote it).
The library is cumulative, so later targets recombine *earlier inventions* — the compounding that makes this an
engine, not a one-shot.

- **library (substrate):** the bits of `n` — the low-degree algebraic substrate.
- **world pool (source):** divisibility primitives `{is_div_p : p prime ≤ 61}` — number theory, provably
  out-of-substrate (each `is_div_p` is Fourier-flat, `boolean_fourier.md`).
- **certify a promotion:** ESCAPE (adding the generator lifts held-out *balanced* accuracy on the target past
  the library) **and** IRREDUCIBLE (the generator is not reconstructible from the library — held-out R² < 0.40).
  Balanced accuracy is used so rare targets (`n%35`, primality) cannot be trivially "solved" by class imbalance.

## Results

```
  bit_5             bal 1.000  → COVERED by the substrate (recombination)
  Hamming-majority  bal 1.000  → COVERED by the substrate (recombination)
  n % 2 = 0         bal 1.000  → COVERED by the substrate (= bit 0)
  n % 3 = 0         bal 0.508  → INJECT  + mod_3 (escape 0.508→1.000, irreducible R²=−0.15) PROMOTE
  n % 5 = 0         bal 0.500  → INJECT  + mod_5 (escape 0.500→1.000, irreducible R²=−0.09) PROMOTE
  n % 15 = 0        bal 1.000  → COMPOUND ★ — solved by already-invented {mod_3, mod_5} (base alone 0.500)
  n % 7 = 0         bal 0.500  → INJECT  + mod_7 (escape 0.500→1.000, irreducible R²=−0.20) PROMOTE
  n % 35 = 0        bal 1.000  → COMPOUND ★ — solved by already-invented {mod_5, mod_7} (base alone 0.500)
  PRIMALITY         bal 0.873  → INJECT  + mod_11 + mod_13 (escape 0.873→0.951, each irreducible) PROMOTE

  final invented library: {mod_3, mod_5, mod_7, mod_11, mod_13}   (5 generators)
  3 recombined in substrate · 4 required invention · 2 recombined PRIOR INVENTIONS (compounding)
```

## What it demonstrates

1. **Recombination vs invention, separated mechanically with a certificate.** The substrate handles bit,
   majority, even (recombination). Divisibility-by-3/5/7 and primality are out of the algebraic closure
   (balanced accuracy ≈ 0.5 — chance) and enter *only* by certified injection of a world generator. This is
   exactly the original goal: more than recombination, **and you can prove which is which.**
2. **Compounding — the engine property (★).** `n%15` fell to the already-invented `{mod_3, mod_5}` and `n%35`
   to `{mod_5, mod_7}` — no new injection. The library is cumulative; inventions recombine. A one-shot crossing
   cannot do this.
3. **Assembly, and substrate reuse.** Primality assembled a sieve from prior inventions `{mod_3,5,7}` plus new
   `{mod_11,13}` — and crucially reused the *substrate's* `bit_0` for evenness, so it never needed to invent
   `mod_2`. The engine invents only what is genuinely out-of-closure and recombines everything else.
4. **The certificate is non-trivial.** Every promotion's irreducibility R² is ≈ 0 or negative — the
   divisibility generators are genuinely not reconstructible from the library (CRT independence). The certifier
   would *reject* a reducible candidate (R² ≥ 0.40); none of the real escapes are.

## Verdict

This is the invention engine the whole arc converged on. The terminal result proved no closed substrate
produces these generators by composition (they are Fourier-flat, outside every algebraic family). They entered
**only** by injection from an out-of-substrate source — real mathematics — and the certifier kept them **only**
because they provably escape the library and are irreducible to it. The loop is closed: stream → cover-or-inject
→ certify → promote → compound.

## Honest scope

- **Selection, not generation, of the world primitive.** The engine chooses from a fixed pool of divisibility
  primitives; it does not yet *generate* novel primitive forms. That is the next rung: a richer source whose
  primitives are themselves open-ended (real datasets; a verifiable external unknown; or an LLM subordinated to
  the certifier). The architecture is identical — only the source changes. Number theory is the purest first
  source, chosen so every "escape" is unambiguous and verifiable.
- The targets are a designed stream chosen to exhibit recombination, invention, and compounding cleanly. The
  claim is the *mechanism* (certified inject→promote→compound), demonstrated end-to-end, not a benchmark.
- Balanced accuracy + held-out split + irreducibility R² are the certificate; primality stops at the 0.95
  balanced threshold (it would climb further with more sieve primes), reported honestly, not inflated to 1.0.

## The roadmap (same loop, richer source)

The engine is source-agnostic. Swap the divisibility pool for: a **real dataset** (does its structure live in a
known family, or did the data inject something out-of-closure?); a **verifiable external unknown**
(superoptimization vs `-O3`, a small open conjecture — certified by Z3 in `04_verified_synthesis`); or an **LLM
as the generator**, subordinated to the certifier. Each is its own probe; the certified inject→promote→compound
loop is the engine underneath all of them.

See: `world_injection.md` (the single crossing this loops), `../README.md`,
`sparse_poly_discovery/docs/research/{inner_forge,boolean_fourier,clone_lattice,kary_frontier,family_closures}.md`,
repo-root `CLOSURE_PRINCIPLE.md`, `RESEARCH_QUESTIONS.md` §J. Method/prior art: FunSearch (Romera-Paredes et al.,
*Nature* 2023); AlphaEvolve (2025).
