# Emergent escape (#38) + closure-principle falsification (#53)

**Status:** built, measured, **exact** (full 256-input truth table, no sampling).
Reproduce: `zig build synergy`. Substrate: 2-register straight-line u8 programs
(r0=x, r1=1), affine base {XOR, SHL, SHR, NOT}, nonlinear ops {AND, OR, ADD, SUB,
MUL}, exhaustive search to length 3.

## #53 — try to falsify the closure principle

Can the **affine-only base** reach any nonlinear target, at any length ≤ 3?

```
  base affine -> x&(x>>1) : UNREACHABLE
  base affine -> x&(x-1)  : UNREACHABLE
  base affine -> x*x      : UNREACHABLE
  base affine -> x|(x<<1) : UNREACHABLE
  base affine -> x|(x*x)  : UNREACHABLE
  => 0/5 reached.
```

The closure principle **survives the falsification attempt**: affine grinding
reaches *zero* nonlinear targets (exactly, over all inputs), as GF(2)-affine closure
requires. A confirmed negative — but an honest one: I tried to break the principle
and couldn't.

## #38 — emergent escape (the genuine positive)

Is there a target reachable by `base+{X,Y}` but **neither** `base+{X}` **nor**
`base+{Y}`?

```
  EMERGENT: x&(x-1)  via base+{AND,SUB}  — not base+{AND}, not base+{SUB}
  EMERGENT: x|(x*x)  via base+{OR,MUL}   — not base+{OR},  not base+{MUL}
  => 2 emergent (irreducible-pair) escapes.
```

**Yes — some out-of-closure generators are irreducibly a *pair*.** `x&(x-1)` needs
both AND *and* subtraction; with only one of them, the target is exactly
unreachable at any length ≤ 3. Neither op alone makes *any* progress; only both
together cross the wall.

## Why this matters — an actionable refinement of the principle

Every escape demonstrated earlier in this project was a *single* generator (MUL,
the SUM, a new atom). This shows the escape can be **multi-op and irreducible**, and
that has a concrete consequence:

> **Greedy, one-op-at-a-time substrate growth provably misses emergent escapes.**

The wcore **atom-forge** grows its atom set exactly this way — it certifies and adds
**one** atom at a time. By the result above, it *cannot* discover a capability that
requires two new ops simultaneously, because neither op alone improves anything for
the certifier to latch onto. So the right fix for an invention engine is to search
**op tuples**, not single ops — the search must be willing to add a pair that looks
useless until completed.

## Honest grade

The underlying fact — *greedy selection misses interacting features* — is known in
ML (it's the feature-interaction / XOR-for-greedy-selection problem). What's
genuinely useful here is the **transfer**: the same fact, stated for out-of-closure
*generator discovery*, yields a specific, testable critique of greedy substrate
growth (the atom-forge) and a concrete design fix (tuple search). Not new to the
world; a real, actionable sharpening of the closure principle for this project.

## The follow-up it sets up

Modify the atom-forge to certify-and-add op **pairs**, and ask: does pair-addition
discover capabilities single-addition provably cannot? That is a genuine positive
experiment for the invention engine — the first one the closure analysis actually
*predicts* should succeed where the greedy version fails.
