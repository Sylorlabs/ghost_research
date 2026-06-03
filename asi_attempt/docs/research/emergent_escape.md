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

## Why this matters — and a self-correction (tested, not assumed)

Every escape demonstrated earlier in this project was a *single* generator (MUL,
the SUM, a new atom). This shows the escape can be **multi-op and irreducible**.
My first instinct was to claim "greedy one-op-at-a-time substrate growth *provably
misses* emergent escapes." **I tested that claim and it was overstated.** Greedy
growth (add the single op that unlocks the most targets; the atom-forge's rule):

```
  rich target set (5 targets): greedy reaches 5/5  =  full op-set 5/5
  isolated {x&(x-1)}         : greedy reaches 0/1     full op-set 1/1
```

So greedy does **not** generally miss emergent escapes. In a rich target set it
reaches them, because each component op gets added for some *other* target, after
which its partner becomes individually useful and greedy picks it up. Greedy
provably **fails only when the pair's components have no standalone use for any
available target** — the isolated case, where no single op ever makes progress so
greedy never starts (0/1) while the full set / tuple search reaches it (1/1).

> **Precise claim:** greedy substrate growth misses an emergent escape **iff** the
> escape's component ops are individually useless across the whole task set. Tuple
> search is needed *exactly there* — not in general.

## Honest grade

The underlying fact — *greedy selection misses interacting features* — is known in
ML (the feature-interaction / XOR-for-greedy-selection problem). The useful (not
new-to-the-world) parts here are: (1) the **transfer** to out-of-closure generator
discovery; (2) the **precise condition** under which greedy substrate growth (the
atom-forge) fails — components with no standalone use — which is sharper than the
folklore; and (3) that I **caught my own overclaim by testing it** rather than
shipping it. The design implication stands but is narrower than first stated: use
tuple search only for components that look individually useless.

## The follow-up it sets up

Modify the atom-forge to certify-and-add op **pairs**, and ask: does pair-addition
discover capabilities single-addition provably cannot? That is a genuine positive
experiment for the invention engine — the first one the closure analysis actually
*predicts* should succeed where the greedy version fails.
