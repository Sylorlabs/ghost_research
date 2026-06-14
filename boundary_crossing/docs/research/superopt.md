# Source B — verified superoptimization: a verifiable external unknown

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build superopt --release=fast` (~16 s).

## The point

The engine's loop is source-agnostic. Here the out-of-substrate ingredient is an **external spec** (a target
function given from outside, not forged), and the certifier is an **exhaustive equivalence check** — a sound
proof at small bit-width (all 256 inputs of a u8). The invention is a program provably equivalent to the spec
and **shorter than a naive baseline**; whether one exists is unknown in advance. This is the FunSearch /
superoptimization shape with no LLM and no SMT solver — the verifier is exhaustive enumeration, which *is* a
proof here.

## Results

ISA `{AND,OR,XOR,ADD,SUB,ANDNOT,NOT}` over u8, operands `{x,0,1,255,prev}`; IDDFS, minimal-first.

```
target                                  certified-minimal program (verified over all 256 inputs)        vs baseline
x & (x-1)   [clear lowest set bit]      v1=ADD(x,255); v2=AND(x,v1)            2 ops   (len-1 impossible)   3 → ✓
x & (-x)    [isolate lowest set bit]    v1=ADD(x,255); v2=ANDNOT(x,v1)         2 ops   (len-1 impossible)   3 → ✓
(x-1) & ~x  [trailing-zeros mask]       v1=ADD(x,255); v2=ANDNOT(v1,x)         2 ops   (len-1 impossible)   3 → ✓
```

The search rediscovered the Hacker's-Delight bit-tricks from nothing but the spec + the verifier, and proved
each **minimal** (it exhaustively checked that no length-1 program is equivalent). It even found `x & ~(x-1)`
for `x&-x` via `ANDNOT` — a different but exhaustively-verified equivalent — and discovered `+255 = -1 (mod 256)`
on its own (`ADD(x,255)` for `x-1`).

## Verdict

The external spec is the out-of-substrate ingredient; the exhaustive check is a sound verifier; the search
produces a **certified-minimal** artifact and **proves no shorter one exists** over the ISA, beating the naive
baselines. Same `inject → certify` loop as the number-theory engine — here the source is an external problem and
the certificate is a *proof of equivalence* rather than held-out accuracy. **Invention with a receipt:** a
provably-correct, provably-minimal program the search was not handed.

## Honest scope

- Exhaustive verification is a proof **only at this width** (u8 = 256 inputs). For wider words it becomes the
  Z3/SMT verifier already in `04_verified_synthesis` (CEGIS), and the search becomes the FunSearch outer loop —
  same architecture, heavier verifier.
- "Beats baseline 3" uses a naive hand-baseline; these particular tricks are known (Hacker's Delight). The
  *mechanism* (spec + sound verifier → certified-minimal artifact) is the result, demonstrated end-to-end; it
  is not a claim of a never-seen bit-hack (that is RQ #34, a longer search at larger length).
- MAXL=3 here; the targets resolve at length 2, so the minimality certificate is exact.

See: `invention_engine.md`, `world_injection.md`, `../README.md`, `04_verified_synthesis` (Z3 CEGIS for wide
words), `RESEARCH_QUESTIONS.md` §D #32–34. Method/prior art: superoptimization (Massalin 1987); FunSearch (2023).
