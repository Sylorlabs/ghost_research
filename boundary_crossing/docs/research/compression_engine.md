# Wider DSL + Kolmogorov-proxy compression certifier + live-LLM seed

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build compression-engine --release=fast` (~5 s).

The three obvious next steps after `autonomous_engine.md`, built together because they reinforce each other: a
wider DSL needs a principled length gate (the compression certifier), and when the autonomous loop hits its
closure the live LLM seeds the missing primitive.

## Results

```
DSL: atom(a·n+b), pairs, and now TRIPLES.  certify: matches held-out AND compression ratio = 2048/program_bits ≥ 8.

PASS A — seed vocabulary (affine DSL, 7 atoms; NO is_fib)
  square OR cube OR prime (triple)   INVENTED   10 bits, compression 197×:  is_square(n) OR is_cube(n) OR is_prime(n)
  is Fibonacci (quadratic)           UNINVENTABLE — no short program in this DSL (request a primitive)
  structureless hash                 UNINVENTABLE — no short program in this DSL

PASS B — Claude (the LLM) seeded the requested primitive is_fib (8 atoms)
  square OR cube OR prime (triple)   INVENTED   11 bits, compression 186×
  is Fibonacci (quadratic)           INVENTED    3 bits, compression 683×:  is_fib(n)
  structureless hash                 UNINVENTABLE
```

## The three steps, measured

**(1) Wider DSL / budget — ceiling moves out, never vanishes.** "square OR cube OR prime" is a *triple* —
unreachable at the previous cost-≤3 budget — and is invented now that the search reaches triples. But the
structureless hash is uninventable in *every* pass at *every* budget. Same shape, further out, never gone —
exactly what the Closure Principle predicts. Widening the DSL relocates the ceiling; it does not remove it.

**(3) Kolmogorov-proxy compression certifier — the rigorous MDL gate.** The crude "cost ≤ budget" rule becomes
a real one: a generator certifies iff it reproduces the target on held-out `n` **and** its description length
(program bits) is much shorter than the target's incompressible description (the lookup table, `table_bits`).
The **compression ratio = table_bits / program_bits** quantifies every invention — a short program is a 100–700×
compression of the table. The structureless hash admits *no* program, so its only description **is** the table
(ratio 1) → rejected. The cheat (`g = target`) is now rejected **quantitatively**, not merely by a budget cutoff.
Honest limit: true Kolmogorov complexity is uncomputable; this DSL program-length is the **computable proxy** —
the theoretical boundary of the gate, stated plainly.

**(2) Live-LLM-in-the-loop — the AI-generating-algorithm loop, closed.** "is Fibonacci" needs the *quadratic*
`5n²±4`, which is **outside** the seed's affine (`a·n+b`) DSL — so it is genuinely out of the seed's closure.
Pass A reports it **uninventable**: the autonomous loop hit its closure and "requested a primitive." Claude — the
LLM, the out-of-closure source — answered by seeding `is_fib`, and Pass B invents it at one atom (683×
compression, the highest, because a single powerful primitive captures structure the affine DSL would need the
whole table to express). **The LLM injects the out-of-closure generator exactly where the autonomous search is
stuck.** That is the whole arc in motion: *closure ceiling → certified out-of-closure injection → escape*, with
the LLM as the source and compression as the certificate.

## Why this is the end of the line (and an honest one)

These three together complete the engine and confirm its bound from inside:
- The DSL can always be widened, and the LLM can always seed new primitives — so the engine's reach is whatever
  closure you inject (DSL + LLM vocabulary). It compounds and self-extends.
- But every widening only **relocates** the ceiling (structureless stays uninventable), and the compression gate
  makes that boundary **quantitative and uncheatable**: invention is exactly compression, and a structureless /
  out-of-closure target has compression 1 — no free lunch, measured.
- The honest theoretical end: the perfect certifier is the Kolmogorov complexity, which is uncomputable. Every
  real engine uses a computable proxy (here, DSL program-length) and is therefore bounded by *that* proxy's
  closure. "Does everything by itself, unbounded" remains impossible — provably — and the best achievable is
  this: autonomous, compounding, self-extending via an out-of-closure source, cheat-proof by compression, and
  honestly bounded by the closure it can inject from.

## Honest scope

- The "live LLM" is Claude seeding `is_fib` between passes; a real API automates the request→seed step and
  changes nothing about the certifier. The Fibonacci case is the clean out-of-closure demonstration because the
  affine DSL provably cannot reach a quadratic transform.
- The compression ratio uses a simple bit model (atom-refs at `log2(#atoms)`, transforms/ops a few bits each)
  and a held-out-table memorize cost; it is a faithful proxy for description length, not a claim of exact
  Kolmogorov complexity (uncomputable).
- Search is bounded (singles, transformed singles, pairs, triples); deeper programs need a smarter search (the
  same FunSearch/MCTS extension), which only pushes the same ceiling further out.

See: `autonomous_engine.md` (the engine this extends), `llm_proposer.md` (the cheat the ratio gate kills),
`invention_engine.md`, `../README.md`, repo-root `CLOSURE_PRINCIPLE.md`,
`wcore/docs/research/alien_novelty_limit.md` (compression = invention, the principle made the gate).
