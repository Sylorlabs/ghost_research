# Phase C (#3) — the open inner-transform forge saturates at the substrate's family

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build inner-forge --release=fast` (~30 s).

## The decisive question

Phase B (`menu_growth.md`) fixed the arity at pairs; the wall relocated to triples. Phase C removes the
fixed arity and asks the question the whole #3 line turns on: with an **open** forge — unbounded degree,
any subset promotable — does iterated certified promotion **saturate** (bottom out, as wcore's atom-forge
did over its opcode VM) or **grow** unboundedly?

## Setup

- **Substrate (arity unbounded):** an inner transform is a centered-cell-subset monomial
  `φ_S(grid) = Π_{i∈S}(c_i − MID)`. Base atom set = the 8 singletons (degree 1). The forge may promote
  any subset, any degree (≤4 here only for runtime; nothing in the method caps it).
- **Target zoo:** monomial-sign predicates of degree 1–4 on hidden subsets (T1–T4), plus **parity-of-count
  (T5)** — deliberately *not* a monomial sign, the cross-family witness.
- **Objective (the algebraic-irreducibility driver):** promote `φ_S` iff it is **irreducible** to the
  current atoms (held-out reconstruction R² < 0.40) **and useful** (adding it lifts an unsolved target to
  ≥0.90 held-out test where the current set sat at chance). This fuses novelty (algebraic, provable) with
  usefulness (held-out) in one signal — the form wcore did not run.

## Results

```
round 0 (base singletons):  T1 0.52  T2 0.47  T3 0.48  T4 1.00*  T5 0.50   → 1/5 solved

round 1: T1 0.52 → DISCOVER φ(0x24, deg2) escape 1.00, irreducible R²=−0.09 → PROMOTE  (atoms 9)
round 1: T2 0.47 → DISCOVER φ(0x4A, deg3) escape 1.00, irreducible R²=−0.04 → PROMOTE  (atoms 10)
round 1: T3 0.48 → DISCOVER φ(0xB1, deg4) escape 1.00, irreducible R²=−0.14 → PROMOTE  (atoms 11)
round 1: T5 0.50 → best φ(0x18) escape 0.49 / R²=−0.09 → NO promotion (not certified)
round 2: a full pass promoted NOTHING → SATURATED.

final:  T1 1.00*  T2 1.00*  T3 1.00*  T4 1.00*  T5 0.50   → 4/5 solved; atom set 11 (started 8)
```

`0x24 = {2,5}`, `0x4A = {1,3,6}`, `0xB1 = {0,4,5,7}` — the forge discovered the **exact** hidden monomials
blind, by validation. R² ≈ 0 (slightly negative) means a degree-d monomial is genuinely not linearly
reconstructible from lower-degree atoms — strongly irreducible.

**Novelty-only contrast (promote the most-irreducible atom, target-agnostic):**

```
novelty round 1: promoted φ(0x5C, deg4, R²=−0.17) → target coverage 1/5
novelty round 2: promoted φ(0x3C, deg4, R²=−0.27) → target coverage 1/5
novelty round 3: promoted φ(0xB8, deg4, R²=−0.21) → target coverage 1/5
```

## Verdict

**Saturates at the monomial closure.** The open forge promoted exactly the monomials its targets needed
(degree 2, 3, 4 — covering 4/5), then a full pass promoted nothing. T5 parity is not a monomial sign, and
**no monomial at any degree the forge can promote escapes it** (best 0.49 = chance). The arity was
unbounded, yet promotion bottomed out at the substrate's *kind* — products of cells.

This **replicates wcore's atom-forge terminal result in a second, independent substrate**
(`alien_novelty_limit.md`: "composition down to whatever you fix as primitive; a fixed substrate always
has a bottom"). Two substrates, one law — the repo's gold standard of cross-thread replication, now
covering the inventable-primitive frontier.

**The objective changed the climb, not the bottom.** The algebraic-irreducibility+usefulness driver
promoted only certified, useful atoms (3 promotions, 0 wasted) and covered the monomial zoo efficiently.
The novelty-only driver promoted high-degree atoms that left coverage flat at 1/5 — wcore's
**novelty ↔ usefulness tension**, reproduced: pure novelty is diverse-but-useless, pure usefulness needs a
target. Fusing them sharpens the *climb* but both drivers bottom out at the *same* monomial closure. **The
bottom is the substrate's family, not the search budget and not the objective.**

## What it means — the boundary, measured

Crossing from monomials to parity needs a generator of a **different family** (the periodic/spectral one,
`spectral_discovery.md`) — which the monomial forge cannot mint by any amount of promotion. By the
Closure Principle, that generator must be *injected* from outside the substrate. The purist constraint
(no LLM, no external data) leaves only human-supply or enumeration-within-the-family, and enumeration is
exactly what the forge does — it composes, it does not cross families.

So **purist autonomous *unbounded* invention terminates here**, cleanly and on purpose. #3 delivered: a
certified menu-growth that escapes a named ceiling (Phase B), and an open forge that bottoms out at its
substrate's family (Phase C) — replicating wcore in a second substrate and pinning the exact boundary.
The next genuine step requires relaxing exactly one constraint: an out-of-substrate ingredient (real
data / a physical signal / a richer-closure model subordinated to the certifier). That decision is the
honest output of #3.

## Honest caveats

- **Monomials are one clean family.** The crispness of the saturation (a perfect step function, R² ≈ 0
  irreducibility) is *because* the substrate is a single well-understood family. A richer VM (wcore's
  opcodes) saturates less cleanly but at the same kind of bottom; the monomial substrate is the clearest
  possible witness, not a different law.
- **Degree capped at 4 for runtime**, not for the argument — parity is outside the monomial family at
  *every* degree (it is the full-degree symmetric XOR), so no degree cap hides an escape.
- Single seed; separations are 0.5/1.0 so seed noise is not load-bearing.

See: `menu_growth.md` (Phase B), `inventable_substrate_design.md` (the plan), `structure_discovery.md`
(Frontier 24), `spectral_discovery.md` (the family the monomial forge cannot reach),
`wcore/docs/research/alien_novelty_limit.md` (the terminal answer replicated here), repo-root
`CLOSURE_PRINCIPLE.md` and `RESEARCH_QUESTIONS.md` §J (the out-of-substrate path across the boundary).
