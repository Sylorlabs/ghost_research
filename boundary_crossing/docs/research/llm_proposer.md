# Claude IS the generator — the LLM-in-the-loop experiment

**Status:** built, measured, and iterated (Claude playing the proposer). Reproduce: `cd boundary_crossing && zig build llm-proposer --release=fast` (~20 s).

## What this is

No external API. The model writing this file (Claude) plays the FunSearch **proposer** directly: for a battery
of number-theoretic targets that the fixed bit-substrate provably cannot read, Claude proposes generators from
its own mathematical knowledge, and the closure certifier (replicated escape + irreducibility) judges each. It
tests the central claim of the whole arc — *an LLM is a genuine out-of-closure source* — with a real, fallible
LLM in the proposer seat, and it answers the question this session opened with: **is an LLM more than a
recombiner, and can you prove which proposals are genuine?**

It was run iteratively, as a real proposer would: the first run left **twin-prime unsolved** (the imbalanced
log-loss readout won't exploit a partially-predictive feature), so the proposer composed `is_prime(n) AND
is_prime(n+2)` explicitly; and **power-of-two** showed a substrate artifact, so it was swapped for perfect cube.
That iteration loop *is* the experiment.

## The certification matrix

substrate = 14 bits of `n`; `sub` = substrate-alone balanced accuracy (≈0.50 ⇒ blind); ✓ = the generator
certifies (replicated held-out escape + irreducible to the substrate).

```
target \ generator       sub  is_sq is_sq8 is_fib is_cube popc%2 mod3 is_pr twin CHEAT
perfect square           0.50   ✓
triangular               0.50          ✓
Fibonacci                0.50                 ✓
perfect cube             0.50                        ✓
Thue-Morse (popcnt odd)  0.49                               ✓
prime                    0.50                                      ✓     ✓
divisible by 3           0.50                                   ✓
twin-prime lower         0.50                                            ✓
odd #divisors            0.50   ✓
structureless hash       0.50                                                  ✓
              Claude got a certified generator for 10/10 targets.

per-PRIMITIVE generality:  is_square → 4   prime → 2   is_cube/popcount/divis → 1   cheat → 1 (opaque)
```

## Findings

**Q1 — the LLM is a genuine out-of-closure source.** Every structured target the substrate could not read
(`sub ≈ 0.50`) was solved by a Claude-proposed generator. The LLM supplies primitives — `is_square`, `is_prime`,
`popcount`, `is_cube`, divisibility — that the fixed bit-substrate has no access to. This is the claim the whole
arc rested on, now demonstrated with the LLM actually in the loop.

**Q2 — generality (reuse) is the signature of invention, and the LLM shows real insight.** One primitive,
`is_square`, certifies on perfect-square, triangular, Fibonacci, **and** "odd #divisors" — reused 4× via the
transforms `n`, `8n+1`, `5n²±4`, and an identity. The last is the sharpest: *odd number of divisors* is,
non-obviously, **exactly** *perfect square* (divisors pair up except the root), so the same generator solves a
target that never mentions squares. That is mathematical **insight** — applying hidden structure — not surface
pattern-matching. Reuse across targets is the practical signature that separates a genuine invented primitive
from a one-off.

**Q3 — compounding works with the LLM as proposer.** Twin-prime-lower falls to `is_prime(n) AND is_prime(n+2)` —
a composition of a reusable primitive, no new atom. The library compounds exactly as the number-theory engine
did, but now the compositions come from the LLM's reasoning.

**Q4 — the two boundaries, and they are the important results:**

- **The cheat.** The structureless hash is solved **only** by the CHEAT generator — Claude proposing the target
  itself. It passes ESCAPE + IRREDUCIBLE (it *is* the answer, and a hash is irreducible to low bits), so **the
  certifier as built cannot distinguish a memorized answer from an invention.** A powerful proposer can always
  game escape+irreducibility by emitting the answer. The discriminator that survives is **generality/parsimony**:
  the cheat certifies for exactly one target and reuses nothing; genuine primitives reuse (is_square 4×, prime
  2×). *A parsimony/description-length gate is the missing certifier rule against a powerful proposer* — the same
  conclusion the wcore arc reached (compression = the real invention signal), now forced by an LLM that can cheat.

- **The ceiling.** Drop the cheat and the hash is **unsolved** — even the LLM cannot propose a short generator
  for a structureless target. The LLM's closure is vast but **bounded**: it recalls and recombines known
  mathematics, and a target with no mathematical structure defeats it too. This is the precise, honest answer to
  the original goal. An LLM-as-generator is *more than recombination of the fixed substrate* (it injects genuine
  out-of-closure primitives, certified) — but it is *still a recombiner of its own training closure*. Genuinely
  alien structure, outside all known mathematics, would defeat the LLM exactly as it defeats the symbolic forge.

## The honest bottom line (for the original question)

"Can we build something that does more than an LLM that recombines?" This experiment sharpens the answer the
whole repo has been circling:

1. The certifier + an LLM proposer **does** produce certified invention beyond any fixed substrate — for any
   target with mathematical structure the LLM can recall or compose. The certified-real escapes are genuine.
2. But the LLM is itself **closure-bounded** (the hash ceiling), and it can **cheat** a weak certifier (the
   memorized-answer problem). So the engine's power is exactly: *the LLM's (vast) closure*, fenced by a certifier
   that must include **parsimony** to stay honest.
3. Going beyond the LLM's closure — true alien novelty — needs the same thing it always needed: an ingredient
   from outside *that* closure (real data / physical measurement / an open problem with a verifier), or a
   compression-driven search that builds genuinely new primitives rather than recalling them.

So "more than an LLM" is not a different *kind* of engine — it is **this** engine (certified inject→promote) with
a **parsimony gate** and a source richer than the LLM where it matters. The certifier is the invariant; the LLM
is a powerful, bounded, occasionally-cheating source that the certifier makes safe — and the honest frontier is
unchanged: invention is bounded by the closure you can inject from, all the way up.

## Honest scope

- "Claude proposes" = the generators in `llm_proposer.zig` are written by the model; a live API would automate
  the proposing but change nothing about the certifier or the findings.
- The cheat detector here is *generality* (reuse count), a proxy; the rigorous version is description-length /
  program size (the cheat is incompressible, a true primitive is a short program). Implementing an MDL gate is
  the clean next step and the wcore connection.
- Small domain (n < 2¹⁴) so primality/cubes/Fibonacci are dense enough to measure; the readout's class-imbalance
  limitation (why twin needed an explicit conjunction) is real and reported, not hidden.

See: `certifier_filter.md` (the certifier and its replication fix), `invention_engine.md` (the closed loop),
`world_injection.md`, `superopt.md`, `real_data.md`, `../README.md`, repo-root `CLOSURE_PRINCIPLE.md` and
`wcore/docs/research/alien_novelty_limit.md` (compression = invention; the parsimony gate this experiment
demands). Method/prior art: FunSearch (Romera-Paredes et al., *Nature* 2023).
