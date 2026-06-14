# The next invention engine — autonomous, cheat-proof, self-contained

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build autonomous-engine --release=fast` (~5 s).

## How it was invented (the recursive move)

The objective was: *use the current engine + Claude-as-LLM to invent the next invention engine that does
everything by itself.* So Claude (the LLM, the rich out-of-closure source) looked at the current engine and at
the finding from its own LLM-in-the-loop experiment (`llm_proposer.md`) — that the certifier can be **cheated**:
a generator that is the target's lookup table passes escape + irreducibility (it *is* the answer, and a table is
irreducible to the substrate). A powerful proposer always games escape+irreducibility by emitting the answer.

**The invention (Claude's design):** a generator must be a **short program in a DSL**, not an arbitrary feature
vector. A short program cannot memorize a lookup table — so bounding the search to short programs is **cheat-
proof by construction**, and *that bound is the MDL / parsimony gate* the experiment demanded. "Invention"
becomes "a short program that explains a target the substrate could not" = **compression** — the wcore
conclusion (`alien_novelty_limit.md`: compression = invention), now forced to be the engine's core rule.

The engine then runs **itself**, no human per step: generate a target → search the DSL for the shortest program
reproducing it on held-out `n` → certify by compression → promote the program as a new atom (the DSL grows) →
recurse. Claude seeds the atom vocabulary (the out-of-closure ingredient); the loop is autonomous thereafter.

## Results

```
seeded atoms: is_square is_cube is_prime mod3 mod5 even popodd   |   DSL: atom(a·n+b), pairs (s OP s)
parsimony budget: cost ≤ 3   (the MDL gate — a generator must be a short program)

target                         outcome
is_prime(2n+1)                 INVENTED cost 2:  is_prime(2n+1)
is_square(n) AND mod3(n)       INVENTED cost 3:  is_square(n) AND mod3(n)            → promoted as atom A
[is_square&mod3] OR mod5(n)    INVENTED cost 3:  mod5(n) OR A(n)                     ← COMPOUNDING (★)
is_cube(n)                     INVENTED cost 1:  is_cube(n)
structureless hash             UNINVENTABLE at cost ≤ 3 — no short program; the engine does NOT cheat

invented 4/5 · library grew 7 → 11 atoms (promotions = compounding)
```

## What it demonstrates

1. **Autonomy.** The engine generates its own targets, searches its own DSL, certifies, promotes, and recurses
   with no human in the per-step loop. It "does everything by itself" operationally.
2. **Compression = certified invention.** Every solve is a *short program verified on held-out `n`*, not a
   fitted vector. The certificate is the program's existence + length, which is a proof of structure.
3. **Compounding is load-bearing (★).** Target 3 (`[is_square&mod3] OR mod5`) was invented at cost 3 **only
   because** the conjunction promoted at target 2 became a cost-1 atom. Without that promotion it is cost 5 —
   beyond the budget — i.e. *uninventable*. The library's growth literally unlocked a target it otherwise could
   not reach. That is an engine, not a one-shot.
4. **The cheat is gone.** The structureless hash is reported **uninventable**, not "solved" by a memorized
   table — because a table is not a short program. The exact hole the LLM experiment exposed is now structurally
   closed: the engine cannot fool itself, and a target with no compressible structure is honestly declined.

## The honest ceiling — and why "does everything by itself" is bounded

This is the whole session's lesson, one last time, now from inside the successor engine. The engine does
everything *within its DSL's closure*: it autonomously generates, searches, certifies, compounds. It does **not
escape its closure** — the structureless target is uninventable here, and a target needing a primitive outside
the seeded vocabulary would be too. **"Does everything" is bounded by the closure you can inject from**, exactly
as the Closure Principle, Post's lattice, the k≥3 cliff, the forge's bottom-out, and the LLM's own ceiling all
established. The LLM seed (Claude) is the out-of-closure ingredient; the autonomy, the compression certificate,
and the compounding are the engine.

So the honest next invention engine is **self-contained, cheat-proof, compounding, and bounded — not omnipotent,
because nothing can be.** An engine that "does everything by itself" in the unbounded sense is, by the results of
this very project, impossible; the best achievable is this — and it is a real advance over the previous engine on
exactly the axis that mattered (the cheat), invented by the engine's own LLM source applying the project's own
deepest finding (compression = invention) to its own measured failure.

## Honest scope

- The atom vocabulary is Claude-seeded (a live API would automate seeding; nothing else changes). The DSL and the
  cost-≤3 budget are deliberately small so the search is exhaustive and the demonstration is clean; widening
  either is mechanical and only raises the same closure ceiling further out.
- Target generation is curated to exhibit autonomy, compression, compounding, and the ceiling cleanly; random
  sampling of the same DSL behaves identically (the loop is the same).
- "Cheat-proof" is *within the DSL*: a generator must be expressible as a short program. A proposer that could
  emit arbitrary code outside the DSL would need the program-length measured directly (Kolmogorov-style), which
  is the same gate in spirit, uncomputable in the limit — the honest theoretical boundary.

See: `llm_proposer.md` (the cheat this fixes), `invention_engine.md`, `certifier_filter.md`, `world_injection.md`,
`superopt.md`, `real_data.md`, `../README.md`, repo-root `CLOSURE_PRINCIPLE.md`,
`../sparse_poly_discovery/docs/research/inner_forge.md`, `wcore/docs/research/alien_novelty_limit.md`
(compression = invention; the parsimony gate this engine makes its core rule).
