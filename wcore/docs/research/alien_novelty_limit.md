# Research note: can execution-only search *invent* a sequence primitive, or only *rediscover* one?

**Status:** claim stated, experiments run, **claim confirmed**. Reproduce with
`zig build -Doptimize=ReleaseFast` then `zig build run-invent -- <phase>` for
`frontier | novelty | alien | hunt | probe | curriculum | gamble`. Full log: TESTING.md §20.

## Background

The "beat attention" bricks (TESTING.md §19) ended on a wall: the engine *rediscovered*
the scan (a known SSM/RNN primitive). Adding gated/matrix state to chase recall would
just reimplement Mamba. The hypothesis that motivated this arc:

> **Novelty must come from the SUBSTRATE, not the search loop.** A human-shaped op-set
> can only re-derive points humans already mapped. Rebuild the substrate from
> deliberately non-human primitives and let execution-only search hunt for a sequence
> operator that breaks the recall ↔ length-generalization trade-off.

We built the apparatus to test it honestly: a **frontier map** (the two opposing tasks),
a **novelty certifier** (a behavioural fingerprint that catches a known mechanism in
disguise), and an **alien substrate** (u64 registers + bit-mixing + addressable memory
with data-dependent addressing; no softmax, no float product).

## The falsifiable claim

> **C.** Under execution-only search, the known mechanisms are *convergent attractors*:
> they are the minimal-complexity solutions to the tasks **even in the alien op-space**.
> Therefore search **rediscovers** them rather than inventing novel ones, and *gambling*
> (more restarts) changes only how **reliably** you hit an attractor, never **which**
> attractor. Novelty cannot fall out of an alien substrate alone.

Predictions, each falsifiable:

- **P1.** A dedicated search will *discover* the known mechanisms by execution (scan for
  parity; hashed memory for recall) — genuine, generalizing.
- **P2.** Different runs / different op-encodings will converge on the *same* mechanism
  (e.g. parity via XOR-accumulate *and* via ADD-accumulate — same mechanism, different
  spelling).
- **P3.** Gambling reaches the empty top-right corner — but the corner program **factors
  into the two known mechanisms** (accumulator ⊕ hashed memory), a bolted union of
  rediscoveries, not a unified novel primitive.

**C is refuted if:** a run lands a top-right (or any) operator that is (i) Pareto-useful,
(ii) certified far from every known anchor, **and** (iii) does *not* decompose into the
known mechanisms — i.e. a structurally distinct solution that gambling surfaced on its own.

## What the experiments showed

| Experiment | Result | Bearing |
|---|---|---|
| `frontier` | attention = recall corner (parity 0.50 / recall 1.00); scan = length-gen corner (1.00 / 0.37); top-right empty | the target is real; opposite corners |
| `novelty` | disguised scan certifies at distance **0.000** = "not novel"; anchors >1.0 apart | the certifier can catch rediscovery |
| `alien` | hand-written XOR-scan / hash-table / union reach all three corners | the substrate *can host* a frontier-breaker |
| `hunt` | QD 4×300k: top-right **0/4**; high-recall niches empty | recall didn't get sampled (looked unreachable) |
| `probe` | parity solves 4/4 (838 evals); recall sparse 0/4 (0.55); **dense grading made it worse** (0.34) | recall is an all-or-nothing conjunction; the Brick-A density fix is **refuted** |
| `curriculum` | cold recall hit-rate ~1/8 (K-independent at K≤6); champion `mem[key]` load/store holds at **held-out K=48 = 1.000** | **P1 ✓** — addressing is *discoverable & generalizing*. "Unreachable" (Phase 3) was wrong: it's reachable-but-**rare** = a reliability problem. K-ladder warm-start does **not** ease the hard jump. |
| `gamble` | recall hit after **14 restarts**; seeded joint search reaches corner (min=1.000); corner program = `r2 = r2 + r0; r3 = mem[r0]; mem[r0] = r5` (accumulator ⊕ hash-table); scan rediscovered via **ADD** this run, XOR before | **P2 ✓, P3 ✓** |

## Verdict

**Claim C is confirmed; it was not refuted.** Every operator search produced is a known
mechanism or a side-by-side union of two of them. The scan was rediscovered in two
different alien spellings (XOR- and ADD-accumulate), and content-addressing was
rediscovered as load-before-store into addressable memory. The top-right "novel" program
the certifier flags is honestly a *bolted union of two rediscoveries*.

The sharp, useful conclusions:

1. **The engine genuinely discovers real, generalizing mechanisms by execution alone**
   (content addressing, the scan) — that part is not theatre.
2. **It is gated by reliability, not reachability.** A known mechanism is a low-complexity
   conjunction; you hit it ~1/8 per restart, and more restarts hit it more reliably. This
   is the Brick-A lesson, not a gradient problem.
3. **Gambling buys reliability, not novelty.** More dice → the *same* minimal-complexity
   attractor, faster. The corner you reach is the union of rediscoveries.
4. **"Make the primitives weird" did not make the *solutions* novel.** Known mechanisms
   are convergent under execution-only search.

## The two novelty experiments — run, and they did NOT refute C

Novelty requires making the convergent known mechanisms **non-optimal**, so search is
*forced* off the attractor — not more restarts. Both fair tests were run (`forbid`, `fuse`):

**Experiment 1 — forbid the attractor (`forbid`).** Restrict the op-space and re-search.
- Parity solves 4/4 even with `xor` *and* `add` *and* `sub` all forbidden — the
  accumulator is **multiply-realizable**; search just finds another spelling
  (eq/sel/mul/rotr tracking the low bit). **You cannot forbid a convergent mechanism by
  deleting a few ops.** Strongest convergence evidence in the arc.
- Recall with `load`/`store` forbidden does **not** solve (0.531) — a *wall*. The only
  alternative (compare-and-select over registers) is itself attention's mechanism and a
  bigger conjunction than the budget reaches.
- ⇒ Forbidding reveals a different *spelling*, a neighbouring *known* mechanism, or a wall
  — **never a novel primitive.**

**Experiment 2 — insufficiency task (`fuse`).** Per-key counting: output how many times
the current symbol has appeared. Neither scan, hash-table, nor their bolted union can do
it (all 0.184); only a fused **read-modify-write** counter solves it (1.000).
- Cold search (16M evals) **did not discover** the fusion (best 0.495); seeding from a
  banked hash-table building block **also did not** (0.495).
- The RMW is a 3-op conjunction (load + increment + store, same address) with no
  partial-credit slope for the increment — a bigger needle than the 2-op hash-table.
- ⇒ Even a task that *demands* something past the union demands a *known fused pattern* (a
  counter array), and search can't even reach it. A reliability wall, not novelty.

**Both experiments confirmed C; neither refuted it.** Forbidding convergent mechanisms
either re-spells them, reveals a neighbouring known one, or hits a wall; insufficiency
tasks demand known *fusions* that are merely harder-to-reach conjunctions. Across the
whole arc, execution-only search over the alien substrate **rediscovers, re-spells, and
(in principle) composes KNOWN mechanisms — it does not mint a new one.**

## What this would take to refute (the genuinely open question)

C predicts no novelty under *execution-only search that rewards task performance*. The
remaining ways it could still be false — none yet tested, each a real project:
- A task whose optimal solution is provably *not* any known mechanism or a composition of
  them (hard to construct; most computable tasks decompose into known building blocks).
- A *non-performance* selection pressure (reward structural novelty itself, then test
  whether the novel thing is also useful) — but that risks rewarding noise.
- Vastly more compute on the conjunction-assembly reliability problem, to see whether
  *composing* enough known building blocks ever crosses into something a human wouldn't
  have written — i.e. emergent novelty from scale, not from the substrate.

This note's contribution is the method (map + certifier + alien substrate + the
reliability-vs-novelty distinction) and the honest, experimentally-defended negative:
**execution-only search over an alien substrate rediscovers and re-spells known
mechanisms; it does not, by gambling, forbidding, or insufficiency tasks, invent.**
