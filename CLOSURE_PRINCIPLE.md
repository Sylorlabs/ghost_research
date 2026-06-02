# The Closure Principle — one wall, four witnesses

A cross-thread synthesis of this repository's deepest recurring result. It unifies
findings that were discovered independently in three different subprojects
(BitForge mixer synthesis, the wcore invention engine, the asi_attempt control
agent) and states them as one principle, now backed by runnable controlled
before/after experiments in each domain.

## Statement

> **Closure Principle.** A search or learning process confined to a *closed*
> primitive set cannot produce a function outside the algebraic closure of that
> set. Grinding harder *within* the closure — more iterations, more search tiers,
> better optimisation, richer encodings — cannot escape it. The only escape is to
> inject a **generator outside the closure**.

Two testable corollaries:

1. **Ceiling corollary.** If the target predicate/behaviour lies outside the
   closure, performance plateaus at a bound set by the closure, *regardless of
   optimisation effort*. The plateau is a representational fact, not a tuning
   failure — provable, not empirical.
2. **Escape corollary.** Adding one out-of-closure generator collapses the
   plateau. The before/after gap is attributable to that generator alone (hold
   everything else fixed).

## The four witnesses

| domain | closed substrate | ceiling (proved/measured) | out-of-closure generator | escape evidence |
|--------|------------------|---------------------------|--------------------------|-----------------|
| **mixers** (BitForge thread 07) | GF(2)-affine (XOR/shift) | SAC-error = 0.5 exactly (theorem); PractRand failure | ADD (carry), MUL | `closure_escape_mixer`: 0.5 → 0.13 (ADD) → 0.02 (MUL) |
| **invention** (wcore Claim C) | fixed opcode VM | only encodings of known mechanisms; 0/7 deep solvers irreducible | a new atom | irreducibility certifier flags the true outsider |
| **control / world-model** (asi_attempt) | XOR/bundle VSA | band predicate unreadable: nearest-prototype 0.50, best linear 0.51 (chance) | the SUM (total mass) | `mb_mass`: 11.02 fail/1k — beats the hand-coded thermostat (20.80) |
| **search depth** (BitForge meta-engine) | fixed Tier-0 opcodes | reproducible 44–47 fitness ceiling; "more tiers" refuted | richer Tier-0 op/scoring axis | monotone+parallel+QD crossing only via new axis |

Each row is the same statement instantiated. The first three now have a runnable
controlled before/after; the fourth is the historical meta-engine ceiling work
(`docs/05`, `docs/06`).

## Why the witnesses are the *same* phenomenon

- In every case the substrate is closed under composition: XOR/shift programs
  stay GF(2)-affine; opcode-VM programs stay within the span of their opcodes;
  XOR/bundle encodings collapse a grid to a parity, and parities are closed under
  the readout's linear operations.
- In every case the *useful* target is provably outside that closure: avalanche
  independence is not an affine function; a genuinely new mechanism is not a
  composition of known atoms; total mass (a sum/threshold) is not a parity.
- In every case "optimise harder" was tried and failed by the same mechanism:
  more iters/tiers (meta-engine), better prediction and metric encoding
  (asi_attempt CP3 + ordinal), longer programs (mixer L24). All stay in the
  closure.
- In every case the fix has the same shape: add a generator the closure lacks —
  MUL, a new atom, the SUM.

## The sharpest single demonstration

`asi_attempt`'s control result is the cleanest, because the escape also yields a
*super-baseline learned agent*:

- The XOR/bundle substrate **provably** cannot classify "mass in band": a trained
  perceptron over all 8192 encoding bits scores 0.51 (chance), and metric
  (ordinal) encoding does not help, because cross-cell XOR-binding parity-collapses
  the grid (`zig build probe`).
- Every in-closure fix plateaus: prototype readout 162.94, +repulsion-fix 33.62,
  +ordinal 55.63 — all worse than the hand-coded thermostat (20.80).
- One out-of-closure feature — read the SUM — and the *same* agent learns control
  at **11.02**, beating the thermostat ~2× (`asi_attempt/docs/research/closure_escape_control.md`).

## Practical corollary for this repo (and any learner)

> **When a learner plateaus, first ask whether the target is even in the closure
> of its substrate. If not, no amount of optimisation, depth, or data will reach
> it — change the substrate. Expressiveness first, optimisation second.**

This reframes several earlier "failures" as correct closure ceilings (the
meta-engine 44–47 wall; CP3's "better prediction hurt control" on the trivial
task) and tells you the lever is always the generator, not the grind.

## The open frontier — and a partial answer

In the four witnesses above the out-of-closure generator was **human-supplied**
(we added MUL, defined a new atom, fed the SUM). The deepest question — the real
definition of "invention" — is whether a system can **discover the right
out-of-closure generator on its own**.

**Partial answer (selection-level), now measured.** A generic feature search in
the control domain — running the controller over candidate aggregates
{sum, max, first-cell, nonzero-count} and keeping the best, *without being told*
which matters — discovers the SUM autonomously (11.02 fail/1k, beating the
thermostat; decoys score 37–333). So the generator is **discoverable, not
inherently human-only** — *provided it is expressible in the candidate space*
(`asi_attempt/docs/research/feature_discovery.md`).

**Stronger answer (construction-level), also measured.** Unsupervised PCA on the
raw 16 cells — *no candidate library, no labels* — recovers the sum direction
almost exactly: `cosine(top principal component, uniform/sum) = 0.9987`. The
out-of-closure feature is **constructed**, not merely selected, because `charge`/
`rest` move all cells together so the sum *is* the dominant variance axis
(`asi_attempt/docs/research/feature_discovery.md`, construction block).

**The non-circular test (and a correction).** When the useful feature is made
*non-salient* (a single cell hidden behind a loud decoy block), the construction
result collapses: PCA recovers it with cosine **0.000** — the unsupervised result
above was circular, working only because the feature was the dominant variance
axis. Supervised credit-assignment recovers a non-salient *one-sided* feature
(0.999), but a *two-sided band* defeats linear supervision too (0.139): the band
is itself out-of-linear-closure, so discovery needs supervised direction-finding
**composed with** a nonlinear readout (`feature_discovery.md`, Level 3).

**What remains.** The honest discovery ladder — selection → unsupervised
construction (circular) → supervised construction (monotone only) → supervised +
nonlinear (the real case, not yet a closed loop) — is the closure question
re-asked at each rung: is the discoverer's inductive bias rich enough to express
the needed generator? That is exactly the wcore atom-forge conclusion (Claim C):
closure all the way up. There is no free escape; every level of "discover the
generator" presupposes a richer closure to search within.

## Reproduce

```
cd asi_attempt && zig build eval     # [BAND]: mb_mass 11.02 beats thermostat 20.80
cd asi_attempt && zig build probe    # band-readout ceiling: linear readouts at chance
cd 05_meta_synthesis && zig build -Doptimize=ReleaseFast && ./zig-out/bin/closure_escape_mixer
```

See: `asi_attempt/docs/research/{non_trivial_task,cp3_repulsion_floor,closure_escape_control}.md`,
`05_meta_synthesis/docs/07/{affine_closure_*,closure_escape_mixer}.md`, and the
wcore arc note `wcore/docs/research/alien_novelty_limit.md`.
