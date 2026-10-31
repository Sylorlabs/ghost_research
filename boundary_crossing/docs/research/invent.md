# The front-end — loose human intent in, certified invention out

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build invent --release=fast -- 31 255 1000`.

## What it is

The piece Micah asked for: you say *one loose line* and the engine fills in every formal detail and hands back
a certified invention in your terms — you never touch the math or the code. It is the **with-LLM** front-end;
`autonomous_inventor.md` is its **no-LLM** counterpart.

The division of labour, made explicit in the probe:

- **The neural layer (the LLM, me)** does the one irreducible thing: *understand the intent*. "make computing
  x^n cheap" → *that is minimizing multiplications → the shortest-addition-chain problem* → build the target,
  the cost model, the verifier. The human specified none of it.
- **The engine (sound search)** certifies: a complete iterative-deepening search proves the minimum, an
  independent verifier re-checks the chain, and the result is translated back into a plain multiplication recipe.

## Result

```
"make computing x^31 cheap"  →  certified 7 multiplications (vs 8 by hand), PROVABLY minimal:
    x^2=x·x  x^4=x^2·x^2  x^8=x^4·x^4  x^10=x^2·x^8  x^20=x^10·x^10  x^30=x^10·x^20  x^31=x^1·x^30
"make computing x^255 cheap" →  certified 10 (vs 14 by hand)
"make computing x^1000 cheap"→  certified 12 (vs 14 by hand)
```

Five words in, a provably-optimal recipe out — no target, cost model, verifier, or code supplied by the user.

## The honest mechanic

The "understanding" is the LLM, by design — it understands the loose line *the way a person would*. For a
standalone box you run *without* the LLM in the loop, you either (a) state the objective formally and drop the
neural layer entirely (that is `autonomous_inventor`), or (b) wire a live LLM into this slot. The engine
certifies whatever can be soundly verified; where no sound verifier exists it proposes but says so, never
bluffing a certificate.

See: `autonomous_inventor.md`, `dial_three.md`, `real_invention.md`, `../README.md`, `../CLOSURE_PRINCIPLE.md`.
