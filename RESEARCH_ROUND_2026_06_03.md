# Research Round — 2026-06-03: four directions off the Closure Principle

A single session testing four distinct research directions that fall out of the
[Closure Principle](CLOSURE_PRINCIPLE.md) and the external frontier-research report on
algebraic intelligence. Each is a controlled, falsifiable experiment in the repo's house
style; each ended with an honest verdict. Three were chosen to *probe* the principle from new
angles; one was an explicit attempt to *break* it.

**One-line summary:** the binding algebra is a real closure lever, but the specific upgrade
to Clifford is not what matters (a cheap real bind suffices); gradient cannot discover the
primitive parameter where grid search can; the open-atom-set loop covers a fixed substrate
rather than transcending it; and a hard attempt to falsify the closure principle failed and
made it *more* fundamental.

---

## A — Clifford binding (RQ A10): does changing the bind algebra move the closure?

**Built:** `asi_attempt/clifford_closure.zig` (`zig build clifford`).
**Doc:** `asi_attempt/docs/research/clifford_binding.md`.

Held the VSA recipe fixed (random role per cell, value filler, bind, bundle, linear readout)
and changed **only** the bind: XOR (GF(2)) vs a real Hadamard control vs a Cl(13,0) geometric
product with rotor fillers. All at 8192 features, same grids.

```
  substrate                         | sum>=K linear  (after fair standardization)
  XOR-VSA   (GF(2), 8192 bits)      |   0.503   (chance — ceiling SURVIVES standardization)
  Hadamard-R (real scale, 8192 d)   |   0.974
  Clifford-VSA (geo prod, 8192 d)   |   0.967
```

- **CONFIRMED** (escape corollary): switching the bind off GF(2) collapses the ceiling — the
  binding algebra alone moves the closure. The report's "change the algebra" thesis holds.
- **DEFLATION** (the load-bearing control): a plain real Hadamard bind reads the sum **as well
  as** the full Clifford geometric product. The generator is *"leave GF(2) for a magnitude-
  carrying real field,"* **not** the geometric product specifically. The control arm is what
  prevented the overclaim "Clifford cracks the band." Same pattern as the repo's recurring
  "the impressive structure wasn't load-bearing" finding.
- **Caveat:** the band is effectively one-sided for this mass distribution, so Clifford's
  grade-2 (pairwise) advantage is *untested* — that needs a genuine two-sided band.

## B — Open-atom-set loop (RQ A1–A3): does promotion transcend the substrate?

**Already built:** `wcore` atom-forge (`zig build run-invent -- atomforge`).
**Re-run, honest verdict confirmed.**

The iterated loop (novelty search → irreducibility certifier → promote → recurse) invents 8
atoms beyond the 5 base, each certified irreducible vs all prior. But its own verdict is the
honest one:

- minimal program-length per invented atom stays **flat/noisy** (5 5 2 3 3 5 5 6) → this is
  *coverage of a fixed repertoire toward saturation*, **not** unbounded complexity growth;
- every invented atom is a short composition of substrate opcodes, so *"the open-ended atom
  set does NOT escape claim C — it RELOCATES it... composition all the way down to whatever
  you fix as primitive."*

So the answer to "does iterated promotion terminate or grow unboundedly?" is: it covers the
fixed opcode VM and bottoms out there. Genuine unbounded invention needs a substrate whose
*primitives are themselves inventable* — a learned/physical substrate a fixed-opcode machine
cannot be. Consistent with the Clifford and falsification results: the substrate is the wall.

## C — Family discovery by gradient (RQ C23): can gradient learn the primitive parameter?

**Built:** `asi_attempt/family_gradient.zig` (`zig build family-gradient`).
**Doc:** `asi_attempt/docs/research/family_gradient.md`.

The forge grid-searches `(H,ω)` for `cos(ω·count)` to capture parity. Can gradient learn ω?

```
  grid search over ω (the forge)      |  1.000   best ω=3.000 (π=3.142)
  gradient, random ω init (mean/40)   |  0.670   0/40 reached >0.95
  gradient, warm start near π (best)  |  0.728   0/40 reached >0.95
```

- **CONFIRMED negative**, and structurally so: the ω-gradient `∝ −count·sin(ω·count)`
  **vanishes at the optimum** (`sin(π·integer)=0`). ω=π is a measure-zero spike, not a basin —
  even warm-started gradient gets no pull and drifts off. Discovery is the *enumeration*, not
  the descent. "Learn the primitive parameter by gradient" does not close the loop for the
  parity family. The honest frontier (grow a non-enumerable primitive) remains open.

## D — Falsification hunt (RQ I53): can the XOR ceiling be broken?

**Built:** `asi_attempt/falsify_closure.zig` (`zig build falsify`).
**Doc:** `asi_attempt/docs/research/falsification_hunt.md`.

Attacked the XOR ceiling with a nonlinear MLP, and — decisively — with a training-free
information-theoretic test.

```
  PRIMARY (training-free):
    distinct grids                : 4000
    distinct XOR encodings        : 64     (<= 2^7 = 128 parity signatures; 64 because Σn_v=16)
    largest bucket                : 81 grids, sums spanning [29, 67]  (spread 54)
  SECONDARY (readouts):
    linear over XOR bits          : 0.481   (ceiling)
    MLP over XOR bits  (attack)   : 0.505   (chance)
    MLP over raw cells (control)  : 0.998   (the MLP CAN learn sum)
    linear over Hadamard (control): 0.976   (a real bind exposes sum)
```

- **PRINCIPLE SURVIVES — STRENGTHENED.** The encoder `s = (⊕P[i]) ⊕ (⊕_v (n_v mod 2)·V[v])`
  keeps **only per-value count parities**: 4000 grids collapse to 64 encodings, and the sum
  spans [29,67] *within a single encoding*. The sum is **information-theoretically destroyed**,
  not nonlinearly hidden — no readout, however strong, can recover it. The MLP attack at chance
  (while the same MLP cracks raw cells, and a real bind exposes the sum linearly) corroborates
  that the wall is the substrate. The attempt to break the principle made the ceiling *more*
  fundamental.

---

## Cross-cutting reading

All four point at the same place from different angles: **the substrate, not the search, is
the wall.**

| Direction | Probed | Honest outcome |
|-----------|--------|----------------|
| A Clifford | a richer binding algebra | algebra moves the closure, but *which* algebra (Clifford vs cheap real) doesn't matter here |
| B atom-forge | open-ended atoms | covers a fixed substrate; relocates claim C, doesn't escape it |
| C gradient | learn the generator's parameter | gradient is structurally blind where enumeration works |
| D falsify | break the ceiling by any readout | ceiling is information destruction, unbreakable for this encoder |

The repeated lesson — already the spine of `CLOSURE_PRINCIPLE.md` — is reinforced from four
new directions: expressiveness (what the substrate *keeps*) is prior to optimisation (how hard
you search). A, B, D say the substrate decides what is *recoverable*; C says even *finding* the
right generator presupposes a search structure the substrate/family must afford.

## What remains (the honest frontier, sharpened)

1. **Clifford's real test** — a genuine two-sided / relational predicate (pairwise products
   not reducible to the sum), where the geometric product's grade-2 might beat plain real
   binding. A's deflation is specific to mass-symmetric predicates; this is untested.
2. **Non-enumerable primitive discovery** — C shows gradient fails on oscillatory families;
   a periodicity-aware / spectral discovery operator is the open lever.
3. **A substrate with inventable primitives** — B's terminal answer: unbounded invention needs
   a substrate whose bottom is not a fixed opcode set. That is the deepest open problem and the
   one the external report also circles (open systems / learned substrates).

See `INDEX.md` for the full project map and `RESEARCH_QUESTIONS.md` for the question inventory.
