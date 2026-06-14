# The recursive loop — engine → successor → … run to its bound

**Status:** built, measured, run to termination (twice). Reproduce: `cd boundary_crossing && zig build recursive-loop --release=fast` (~20 s).

## What it is

The generational self-improvement loop, running autonomously: each generation is a better engine than the
last. Solve every target reachable with the current (library, budget); **promote** each solved program into the
library (so deeper targets collapse to shallow reuse — the engine inventing its successor); grow the budget when
stuck; and when even that plateaus, the **LLM injects the next out-of-closure primitive** from a queue it seeded.
When the queue is exhausted and structureless targets remain, terminate. Verification is **exact equivalence over
the full domain** (a proof, like superopt) — for deterministic program search there is no train/test split, only
correctness.

## The run (28-target battery, 7-primitive injection queue)

```
gen | cap   | action
 1  |  8/28 | ABSTRACTION CASCADE: solved 8 incl. the depth-6 target — all by promoting each solve, no injection
 2  |  8/28 | grow budget → 3   (no gain)
 3  |  8/28 | grow budget → 4   (no gain — budget is not the bottleneck)
 4  |  8/28 | PLATEAU → LLM injects mod5
 5  | 10/28 | mod5∧even, T8∨sq
 6  | 10/28 | PLATEAU → LLM injects is_prime
 7  | 13/28 | is_prime, prime∨T0, and T11∧T19 via the clever exact equivalent (is_prime∧mod3)∨T0
 8–10|       | inject is_cube → 14 ; inject is_fib → 17 (incl. pow2∨even solved as (sq∧fib)∨even — is_pow2 not needed!)
12–14|       | inject mod7 → 21 (mod7 targets + compounds mod5∧mod7, T8∧T16) ; inject is_triangular → 24
16  | 24/28 | inject is_pow2 — REDUNDANT (already covered by the clever equivalents); no gain
17  | 24/28 | TERMINAL: queue exhausted, 4 structureless targets remain

24/28 solved · library 3 → 34 atoms · 7 injections · the 4 unsolved are structureless (the hard ceiling).
```

## The dynamics — the honest answer to "engine invents its successor, and so on"

- **Abstraction climb (free self-improvement).** Generation 1 solves a depth-6 dependency chain *by itself*,
  because each solve is promoted and the next target reuses it. The engine gets genuinely better with no
  injection — recursive self-improvement is real.
- **Plateau.** It exhausts what its vocabulary can express; more budget buys nothing. The autonomous loop has
  reached its closure.
- **Injection step.** Only an out-of-closure primitive (the LLM) moves the ceiling. Each injection is a staircase
  step, and each injected primitive is then promoted, so the engine compounds past it autonomously.
- **Emergent cleverness — and shrinking need for injection.** Full-domain exact search finds *non-obvious exact
  equivalents*: `T11∧T19 ≡ (is_prime∧mod3)∨T0` (since `is_prime∧mod3 = {3}`), and `pow2∨even ≡ (is_square∧is_fib)∨even`
  (since `sq∧fib = {0,1,144}`). The second made the `is_pow2` injection *redundant*. As the library compounds, the
  engine's reach expands to cover targets a naive analysis would think need a new primitive — so it asks the LLM
  for **fewer** injections over time. The out-of-closure source is load-bearing, but compounding erodes its share.
- **Hard ceiling.** When the injectable closure is exhausted, the structureless targets remain forever
  uninventable — no program exists at any budget, with any vocabulary.

## The terminal result (and why it is the right one)

**Engine→successor→… is real, measured, and finite for a fixed injectable closure.** The loop climbs a staircase:
free abstraction segments, broken by injection steps, ending at a hard ceiling. To climb *forever* would require
an *unbounded* source to inject from — which is exactly the Closure Principle, one final time, now as a running
loop. Extending the closure (more primitive families, as we did from 16 to 28 targets) just makes the staircase
longer and the bound higher; it never removes the bound.

So the honest form of recursive self-improvement is: **keep injecting (LLM / data / problems), keep certifying
(exact equivalence / compression, cheat-proof), keep promoting — bounded, certified rungs that compose into a
climb that goes exactly as far as the injectable closure allows, and no further.** That is the ladder, run to its
end, and it is the same answer this whole project reached at every level — now demonstrated as an autonomous loop
inventing engine after engine until it hits the wall that nothing crosses.

## Honest scope

- The injection queue is Claude-seeded (a live API automates the request→seed step). The loop requests an
  injection only when it provably plateaus; the LLM is invoked at the frontier, not per step.
- Verification is exact full-domain equivalence — sound for these deterministic predicates (no overfitting; the
  earlier held-out version spuriously "solved" a target that was constant on the held-out half, which this fixes).
- The battery is graded to exhibit the dynamics cleanly (abstraction chain, injection-needers, compounds,
  structureless). It is finite; a truly open-ended loop would also *generate* its own targets (POET) — the same
  dynamics with an additional target-proposal step, bounded the same way.

See: `self_improve.md`, `autonomous_engine.md`, `compression_engine.md`, `llm_proposer.md`, `../README.md`,
repo-root `CLOSURE_PRINCIPLE.md`. Prior art: DreamCoder (2021), FunSearch (2023), POET (2019), AI-GAs (Clune 2019).
