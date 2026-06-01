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
| `getrecall` | recall solve-rate 0/8 (R=12) → 3/8 (R=6) → **8/8 (R=6 + memory-biased proposer)**; the "dead" K=20 → **6/8**; champion is the same `mem[key]` hash-table, held-out K=48 = 1.000 | reliability is **fixable** — register-coordination combinatorics, not a gradient |
| `corner` | with the levers, pure QD search reaches the top-right **4/4** (Phase 3: 0/4); corner holds held-out (parity L=256=1.000, recall K=48=1.000) and decomposes accumulator ⊕ hash-table | Phase-3 0/4 was a reliability artefact; corner = the union (P3 ✓ again) |

## Verdict

**Claim C is confirmed; it was not refuted.** Every operator search produced is a known
mechanism or a side-by-side union of two of them. The scan was rediscovered in two
different alien spellings (XOR- and ADD-accumulate), and content-addressing was
rediscovered as load-before-store into addressable memory. The top-right "novel" program
the certifier flags is honestly a *bolted union of two rediscoveries*.

The sharp, useful conclusions:

1. **The engine genuinely discovers real, generalizing mechanisms by execution alone**
   (content addressing, the scan) — that part is not theatre.
2. **It is gated by reliability, not reachability — and the reliability is FIXABLE.** A
   known mechanism is a low-complexity conjunction whose rarity is dominated by
   register-coordination combinatorics. Shrinking the register file (R=12→6) and biasing
   the proposer toward memory ops took recall from 0/8 to **8/8** (`getrecall`), and pure
   QD search from 0/4 to **4/4** on the top-right corner (`corner`) — closing the Phase-3
   negative as a reliability artefact. This is the Brick-A lesson, made concrete and fixed.
3. **Gambling/reliability buys the known answer, not novelty.** The reliable recall is the
   *same* hash-table; the reliably-reached corner is the *same* bolted union of the scan
   and the hash-table. Fixing reliability got us the corner — and confirmed it is a hybrid
   of two rediscoveries, exactly as C predicts.
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

## The pivot — a non-performance objective (`openended`), run

C was stated for *performance* fitness. The strongest test is to drop performance
entirely and reward **behavioural novelty** (Lehman & Stanley novelty search), with the
§20 fingerprint as the selection pressure. Result (TESTING.md §21):

- With **no task objective**, novelty search **rediscovered the accumulator** (XOR-scan,
  dist ~0) — the sparse functional point novelty is driven toward. Recall not reached;
  **0** of 41 far-from-anchor members near-solve any task. Convergence confirmed from a
  *third* independent angle (after forbidding and insufficiency).
- **The novelty problem RELOCATED from the substrate to the DESCRIPTOR.** Novelty search
  is only as novel as its behaviour metric. A descriptor built from known-task behaviour
  can only surface *recombinations* of known capabilities; a genuinely new mechanism is
  invisible to it (tell: the RMW counter reads as dist ~0 — the metric can't see counting).
  **You cannot get out novelty your behaviour metric cannot represent.**

## The information-theoretic descriptor (`infodesc`), run — and the deepest wall

§21 said novelty is bounded by the descriptor. So we built a black-box, task-AGNOSTIC
descriptor (entropy / memory-depth / richness / determinism on a canonical stream — no
"correct answer") and re-ran novelty search in it. Result (TESTING.md §22):

- **It sees what the task descriptor couldn't:** the counter, dist 0.21 (task, blind) →
  1.54 (info, visible). Novelty search now explores long-range temporal structure
  (37/116 archive members). §21's descriptor bottleneck is real and **movable.**
- **Yet still no novelty-that-works:** parity 1.00 is the accumulator rediscovered *again*;
  recall and counting were not reached even though the descriptor sees them (rare
  conjunctions — reliability); the diverse, memory-deep behaviours it found solve nothing.
- **The deepest wall, named — the NOVELTY ↔ USEFULNESS TENSION.** A task-agnostic metric
  gives diverse-but-useless novelty; pinning usefulness needs a task, which reintroduces
  the convergent attractor. **One fitness gives open-ended novelty OR task-grounded
  usefulness — not both.**

The arc's structure is now a clean three-level descent: the novelty problem is not the
**substrate** (§20), not the **descriptor** (§21), but the **objective itself** (§22) — you
cannot simultaneously reward "be different" and "be useful" from one signal.

## Coevolution with transfer (`coevo`) — the first POSITIVE, run

The §22 frontier (couple novelty + usefulness via a coevolving task population, POET-style)
was built and tested on its sharpest consequence: does cross-task **transfer assemble a
conjunction direct search can't?** Target = `pk_add`, the per-key counter (3-op RMW) that
§20's `fuse` never found in 16M evals. Result (TESTING.md §23):

- **Independent search:** `pk_add` solved 0/4 (reproduced 0/4, 0/4, 0/4, 1/4 across seeds).
- **Coevolution:** `pk_add` solved **via transfer**, reliably across all seeds.
- **The bridge:** `pk_xor` (a per-key RMW with no constant) *is* findable; transferring its
  `load→op→store` shape to `pk_add` assembles the counter direct search couldn't reach.

**This is the first lever in the whole arc to beat fixed-task search on a hard mechanism.**
The §22 coupling pays off — for **reach**. Honest: the assembled mechanism is the *known*
counter, so coevolution buys reach / reliability, **not** a novel primitive. It beats the
conjunction reliability wall; it does **not repeal C**.

## Open-ended composition ladder (`oecoevo`) — the strongest attack, run

The one avenue the `coevo` positive made plausible — emergent novelty from an ever-moving
task distribution — was built and pushed hard: tasks *generated* by composing stages without
bound, mutation deepening them, transfer carrying solvers up the ladder. Result (TESTING.md §24):

- **Big reach.** The ratchet climbs to **depth 3–4 reliably** (10–14 solved rungs across
  seeds) — transfer *chains*, far past anything fixed-task search reached.
- **But composition, not new atoms.** 5–9 deep solvers per run read "novel" to the
  certifier — but that only means *not a single known atom*, which any composition satisfies
  (the §22 blind spot). Hand-decomposition of the deepest solver confirms it every time: an
  accumulator stacked with addressed memory (e.g. memory used as a delay to make a *delayed*
  parity). A **novel composition of known atoms — not a new primitive.**

**Capstone:** even the open-ended ratchet — the SOTA recipe for open-endedness — composes
the same atoms ever more deeply and never mints a new one. **C holds against the strongest
attack available.** Novelty-by-search is novelty of *composition*, bounded by the atom set
the substrate provides.

## The irreducibility test (`irreducible`) — built, and C now rigorously backed

The instrument the arc kept lacking is built (`inv_coevo.reducible`): is a solver's behaviour
reproducible by a composition of KNOWN atoms (the stage set, searched to depth 4, ≥0.95
agreement)? Match → reducible; no match → irreducible relative to the atom set. Result
(TESTING.md §25):

- **It can detect a true outsider:** distinct-count (a global set-cardinality) is flagged
  IRREDUCIBLE; known atoms and compositions reduce. The test is *not* vacuous.
- **Applied to §24's deep solvers:** the fingerprint certifier called 7 "novel"; the
  irreducibility test finds **0 irreducible, 7 false positives** — every "novel" solver is
  REDUCIBLE to a known-atom composition.

**So C is now backed by an instrument that could have said otherwise.** Open-ended search
produces novel *compositions*, never a new *atom* — confirmed rigorously, not by hand.

## The atom-forge (`atomforge`) — the last frontier, run, and the terminal answer

The one avenue left was a substrate whose atom set is itself open-ended. `inv_atomforge.zig`
builds it by composing the arc's two instruments: novelty search generates behaviours, the
irreducibility test (now over a growing program library) certifies which are irreducible
relative to the current atoms, a certified one is invented, and irreducibility recurs.
Result (TESTING.md §26):

- **The mechanism runs:** 8 atoms invented across 8 rounds, each certified irreducible vs all
  prior. The kill-test holds (distinct-count is a new atom; adding it makes it reduce).
- **But honestly:** the bar is weak (the 5 base atoms omit most substrate ops, so any
  behaviour using and/or/mum/popcnt/… is trivially irreducible relative to them); minimal
  length stays flat/noisy (5 5 2 3 3 5 5 6) — coverage of a fixed repertoire, not unbounded
  complexity growth; and every invented atom is itself a short **substrate-op program**.
- **The deep close:** the open-ended atom set does **not escape** C — it **relocates** it. The
  recursion bottoms out at the fixed opcode VM; relative to the substrate primitives,
  everything is composition. A fixed substrate always has a bottom, and at the bottom search
  composes — it does not invent.

## Terminal conclusion

Across 16 phases — fixed-task search, forbidding, insufficiency tasks, novelty search, a
task-agnostic descriptor, coevolution, an open-ended composition ladder, an irreducibility
test, and an open-ended atom set — **C holds, instrument-backed at every level**:
**invention-by-search is composition down to whatever you fix as primitive; a fixed substrate
always has a bottom, and at the bottom, search composes — it does not invent.** Genuine
unbounded invention would require a substrate whose *primitives are themselves inventable*
(an infinite regress, or a learned/physical substrate), which a fixed-opcode machine cannot
be. What execution search *does* do — reliably discover, compose, and (via coevolution)
assemble known atoms far past direct search — is real, demonstrated, and reproducible.

This note's contribution is the method (map + certifier + alien substrate + the
reliability-vs-novelty distinction) and the honest, experimentally-defended negative:
**execution-only search over an alien substrate rediscovers and re-spells known
mechanisms; it does not, by gambling, forbidding, or insufficiency tasks, invent.**
