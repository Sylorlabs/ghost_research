# wcore

A **zero-bias invention engine** in Zig.

## What it does

Starting from nothing but a minimal type theory, the engine *discovers* the
natural numbers as a **W-type**, selecting it purely because it **minimizes
total AST node count** — never because anything told it about numbers,
arithmetic, or counting.

The library begins with exactly four base types (`Unit`, `Bool`, `Sensor`,
`Action`) and two combinators (`identity`, `composition`). There is no `Bottom`,
no `W`, and crucially no general recursion. A 2D grid world produces a sensory
stream of repeated-action runs; the wake phase encodes each run as a fully
*unrolled* program (the only thing it can do without recursion). The sleep phase
then:

1. **Anti-unifies** the batch to find repeated structure — generic detection of
   `App(head, App(head, … base))` chains. It does not look for "numerals".
2. **Blindly enumerates** every small W-type over the finite shapes in the
   library (`Unit`, `Bool`), trying each assignment of position type
   (`Unit` = one recursive subtree, `Bottom` = leaf) to each shape inhabitant.
3. **Accepts** whichever candidate lowers the total node count of
   (library + batch) the most. Nothing checks "is this Nat?".

Over `{Unit, Bool}` shapes, the only W-types that can host "a unary chain that
terminates" are the Bool-shaped ones with one leaf + one unary constructor —
which is exactly the natural numbers. The engine arrives there as the
node-count-minimal compressor, and only *then* labels the result for the human.

## Sandboxing, "its own universe", zero data, full logging

* **Sandboxed:** a single process, arena-allocated, no network, no filesystem
  access except writing its own run log. The world is a self-contained 32×32
  cellular universe; the only thing crossing its boundary is the agent's
  `(action, sensor)` stream.
* **Its own universe per seed:** `zig build run -- <seed>` spawns a distinct,
  fully reproducible universe (empty grid + seeded RNG → randomly scattered
  clusters). Different seeds ⇒ different worlds ⇒ different emergent counts.
* **Starts with zero data:** the grid begins entirely empty; the library begins
  with only the permitted primitives. Nothing about numbers exists anywhere.
* **Everything logged:** every run mirrors all telemetry to
  `logs/wcore_<seed>.log` — world seed, *every* agent step (action, position,
  moved/collected, 3×3 sensor), the run-length segmentation, the wake-phase
  search trace (every candidate + decoy with its denotation), every W-type
  candidate evaluation, the invention, and the behavioural verification.

## Real, not mocked

* **World:** real physics (`step`) — movement blocked by walls, resources
  collected, pushing, wall-building — driven by a real agent episode. The
  repetition counts are *emergent* from harvesting RNG-sized clusters, never
  handed to the engine.
* **Wake phase:** a genuine bounded search that *evaluates* each candidate
  program's denotation (and rejects malformed decoys), selecting the
  minimum-node program that reproduces each run. Not a hardcoded constructor.
  (Neural-guided MCTS over `History`-typed programs remains post-milestone.)
* **Invention:** accepted purely by node-count reduction, then **executed** —
  the invented `WRec` eliminator is run to fold each W-numeral back to a host
  integer and to regenerate the original chain. The engine only reports success
  when `original_chain == fold(W) == recursor_regen == observed_count` for every
  program. The compression is *proven by evaluation*, not just cheaper on paper.

Known honest limitation: the base type checker does not yet dependently
type-check `WIntro`/`WRec` (Section 11); their correctness is established by the
evaluator's behavioural verification instead.

## Not hardcoded to Nat — it invents whatever fits

The blind enumeration considers W-types of arity 0, 1, and 2. Run it over a
**different universe** (a tree-of-chambers topology explored depth-first) and the
*same* node-count rule invents **binary trees** instead of the naturals:

```sh
zig build run -- 42 4 4 branching
#   >> ENGINE INVENTED BINARY TREES (a DIFFERENT W-type, same blind rule) <<
```

On linear data the engine even *considers* reading the chain as a degenerate
binary tree (which saves 18 nodes) but prefers the cheaper Nat encoding (34
nodes) — it rejects the tree interpretation purely on node count. And when the
data is too trivial to compress (e.g. all clusters size 1) it **declines to
invent anything**. See [TESTING.md](TESTING.md) for the full evidence.

## Minimal-bias variant: `wcore-pure`

The main engine still bootstraps from a small typed library. `wcore-pure` strips
the prior to the smallest substrate that still computes — the **SK-combinator
basis** (`S`, `K`, application) plus "minimize node count". No types, no
`Bool`/`Unit`, no `Sensor`/`Action`, no numbers; the abstraction library starts
empty. Driven by a stream it isn't told the structure of, it rediscovers the
**identity combinator** and the **Church booleans** from `S` and `K` alone,
purely by compression and verified by execution:

```sh
zig build run-pure                         # rediscovers I and Church booleans from S,K
zig build run-pure -- 42                   # a different stream
```

```
[SLEEP] discovered C0 = (S K)   -> Church FALSE / second-projection   (saves 27)
[SLEEP] discovered C1 = (C0 K)  -> identity combinator (I = \x.x)      (saves 11)
```

Note `C1` is built on top of `C0` — abstractions compound. On a noise stream the
savings are small and the abstractions are meaningless: it does not hallucinate
structure.

It also **learns over time**. With a persistent library across a sequence of
streams, prior discoveries get reused on new data and new abstractions are built
on old ones — from `S`/`K` it grows the tower `false → identity → duplicator`:

```sh
zig build run-pure -- 0xC0FFEE learn
#   C0 = (S K)        Church FALSE
#   C1 = (C0 K)       identity      (built on C0)
#   C5 = ((S C1) C1)  duplicator    (built on C1)   <- reuse collapses 220 -> 82 nodes
```

See [TESTING.md](TESTING.md) §8.

## Sensorimotor agent: `wcore-agent` (roadmap Stage 1)

An agent dropped into a grid world it knows nothing about, with dynamic
resources. It keeps an online model of its 3×3 sensor stream (starting empty)
and acts under a curiosity drive. From zero knowledge, the **description length
of its stream falls ~56%** (10.7 → 4.7 bits/observation) — genuine compression
learned from scratch, with ASCII maps logged along the way.

```sh
zig build run-agent                        # 6000 steps; watch bits/obs drop
```

Honest scope: this is greedy 1-step curiosity, *not* deep MCTS, and it does
**not** purposefully build machines — its action histogram is uniform and the
walls that appear are incidental. A pure "minimize description length" drive
degenerates (the dark-room problem), which is exactly why curiosity is used. See
[TESTING.md](TESTING.md) §9 for the full, honest roadmap status.

### Empowerment mode (Stage 2): fixing self-entrapment

```sh
zig build run-agent -- 0xC0FFEE 6000 compare
```

Swapping the drive to **empowerment** — control over the future,
`I(A;S') = H(S'|s) − E_a H(S'|s,a)` (not next-obs entropy, which is
noise-seeking) — measurably fixes the curiosity agent's self-enclosure:

```
walls built:  curiosity=48   empowerment=20   (it avoided boxing itself in)
```

Honest finding: in this world, building only ever *reduces* options, so an
empowerment agent rationally avoids it. Purposeful construction needs a world
where structure *increases* control — that's the real frontier, not a cleverer
agent. See [TESTING.md](TESTING.md) §10.

### Affordance mode (Stage 2.5): the first goal-directed work

```sh
zig build run-agent -- 0xC0FFEE 12000 affordance
```

Give the world an affordance — a **button that latches a gate open**, unlocking
the far half of a split room — and the empowerment agent (with a de-aliased
`(x,y,gate)` state and R-max optimistic exploration) **reliably presses the
button and then spends ~50–67% of its time in the region it unlocked**, across
every seed tried:

```
time in unlocked half: random=49%   local=0%   positional=60%
-> pressed the button to unlock the gate, then used what it unlocked.
```

This is the first **goal-directed physical work**: navigate to a structure,
manipulate it on purpose, exploit the result — from zero knowledge, no task
reward. Honest scope: it *uses* a given affordance, it does not yet *build* one;
it still uses a hand-given positional state and tabular model. Two upgrades were
both necessary, each forced by an observed failure (state aliasing; myopic
exploration) — see [TESTING.md](TESTING.md) §11.

### Law discovery (Stage 3): closing the symbolic↔embodied loop

```sh
zig build run-agent -- 0xC0FFEE 30000 law
```

The two halves of the project meet here. The agent lives, records
`(position, gate-state)` experience, and a sleep phase distils the shortest rule
explaining the dynamics — by the *same* "shortest description" objective that
invents ℕ:

```
discovered rule:  gate is open  <=>  x == 2 AND y == 2   (errors: 0/30000)
description length: rule = 11 bits  vs  per-cell table ~ 1024 bits
>> ENGINE DISCOVERED THE CAUSAL LAW OF ITS WORLD FROM EXPERIENCE <<
```

`(2,2)` is the button — found purely by compression, never told. Embodied
experience in, a compact symbolic law out. Honest scope: one law, one mechanism,
a small hand-chosen rule language — not open-ended physics. See
[TESTING.md](TESTING.md) §12.

## Primitive-inventing engine: `wcore-invent` ([PLAN_INVENTION_ENGINE.md](PLAN_INVENTION_ENGINE.md))

The same method (search + MDL + **execute-to-verify** + compounding library) with
a real body: it searches over **primitive math operations** (add, mul, dot, get,
tanh, …) assembled into 3-part programs (`Setup`/`Predict`/`Learn`, the
AutoML-Zero shape — so it invents the *learning rule* too). The PRIME DIRECTIVE:
**every candidate is scored only by running it on data and measuring held-out
accuracy — never by plausibility.** No LLM in the loop, no menu of known layers,
no proxy fitness.

```sh
zig build run-invent -- phase0   # verifier sanity gate: correct prog 1.0, garbage ~chance
zig build run-invent -- phase1   # evolution beats random; rediscovers the multiplicative gate
zig build run-invent -- phase2   # the ratchet: a reused library macro slashes evals-to-solve
zig build run-invent -- phase3   # does one primitive buy compositional reach? (no)
zig build run-invent -- phase4   # the tower: does the NEXT abstraction collapse the NEXT task? (yes)
zig build run-invent -- phase5   # can a warm-start curriculum climb a rung? (no — the trap is real deception)
zig build run-invent -- phase6   # quality-diversity (MAP-Elites) vs the trap (yes — escapes it)
zig build run-invent -- phase7   # the capstone: the engine climbs the tower BY ITSELF
zig build run-invent -- phase8   # reliability: regression grading makes the climb ~100x faster
zig build run-invent -- seq      # "beat attention's weakness": discovers a scan that length-generalizes
zig build run-invent -- frontier # research §20: the recall ↔ length-gen map (attention vs scan, opposite corners)
zig build run-invent -- novelty  # research §20: behavioural novelty certifier (catches a disguised scan)
zig build run-invent -- alien    # research §20: alien substrate — proves the empty top-right corner is reachable
zig build run-invent -- hunt     # research §20: QD search for a frontier-breaker (honest negative this budget)
zig build run-invent -- probe    # research §20: recall conjunction — dense-grading fix refuted
zig build run-invent -- curriculum # research §20: K-ladder REVISES it — addressing is discoverable but RARE (reliability)
zig build run-invent -- gamble   # research §20: gambling reaches the corner — but it's a UNION of two rediscoveries, not novel
zig build run-invent -- forbid   # research §20: forbid a known mechanism → re-spelled/known/wall, never novel
zig build run-invent -- fuse     # research §20: insufficiency task forces a known FUSION (RMW) search can't even reach
zig build run-invent -- getrecall # research §20: GET RECALL — smaller reg-file + biased proposer → 0/8 to 8/8 reliable
zig build run-invent -- corner   # research §20: the corner CLOSED — pure QD reaches top-right 4/4 (was 0/4), still the union
zig build run-invent -- openended # research §21: the pivot — novelty search rediscovers the accumulator; novelty bottleneck moves to the DESCRIPTOR
zig build run-invent -- infodesc # research §22: task-agnostic descriptor SEES more, but exposes the NOVELTY↔USEFULNESS tension (the deepest wall)
zig build run-invent -- coevo    # research §23: coevolution+transfer — FIRST POSITIVE: assembles the RMW counter direct search couldn't (reach, not novelty)
zig build run-invent -- oecoevo  # research §24: open-ended composition ladder ratchets to depth 3-4 — but deep solvers are novel COMPOSITIONS of known atoms, not new atoms
zig build run-invent -- irreducible # research §25: the irreducibility test — proves §24's "novel" solvers REDUCIBLE to known atoms (detects a true outsider, finds none); claim C, rigorously backed
zig build run-invent -- atomforge # research §26: open-ended ATOM SET (invent atoms, not compose) — the recursion runs but bottoms out at the substrate; composition all the way down (terminal answer)
```

> Research note on the novelty limit: `docs/research/alien_novelty_limit.md` —
> execution-only search over an alien substrate *rediscovers* known mechanisms;
> it does not, by gambling, invent.

> The `hunt`/`probe` phases run a real search; build `ReleaseFast`
> (`zig build -Doptimize=ReleaseFast`) before running them — Debug is ~30× slower.

* **Phase 1** (reproduction, ~AutoML-Zero): on `y = sign(x0·x1)`, evolution beats
  random search (4/5 vs 2/5 solves) and rediscovers the gate in forms a human
  wouldn't write — a *division* gate and a *vector-scaling* gate, verified at 1.0.
* **Phase 2** (the compounding library — the bet): the engine abstracts its gate
  into one callable macro `C0(i,j)` and reusing it on new gate tasks collapses each
  to a single `CALL` — **100–200×+ fewer** evaluations, solving tasks flat evolution
  misses. ([TESTING.md](TESTING.md) §13.)
* **Phase 3** (does compounding buy *reach*?): one primitive gives huge *same-arity*
  acceleration (K=1: 4/4 in ~18 evals) but **not** compositional reach — a 2-product
  task is **0/4** even with `C0`, blocked by a real ~70% partial-credit trap. (§14.)
* **Phase 4** (the tower): adding the *next* abstraction `C1` (a composition macro
  built on `C0`) makes the K=2 task `C0` couldn't reach collapse to **4/4 via a
  single call** — **reach compounds, one rung at a time**. ([TESTING.md](TESTING.md) §15.)
* **Phase 5–6** (escaping the trap): warm-start curriculum **fails** (0/4 — the trap is
  genuine deception), but **quality-diversity (MAP-Elites) escapes it** — solving K=2
  by grounded search alone (2/4) where greedy search gets 0/4. (§16–17.)
* **Phase 7** (the capstone): the engine **climbs the tower by itself** — QD solves K=2,
  the MDL extractor **auto-abstracts and execution-verifies `C1`** from that solution
  (no hand-built rung), and QD then solves K=4 with the self-built `{C0, C1}` (champion
  invoking its own `C1` twice). ([TESTING.md](TESTING.md) §18.)

Honest scope: a complete, grounded demonstration that execution-checked compounding
can build its own abstraction tower — **not** a discovered primitive that beats
attention, on a toy family, and the rung-climb is *unreliable* (K=2 ~1-in-4, so the
loop closes only intermittently). Every number is reproducible from `run-invent`.

## Run it

```sh
zig build run                              # default linear universe (seed 0xC0FFEE)
zig build run -- 42                        # a different universe
zig build run -- 42 4 6 linear             # seed, count, max-size, mode
zig build run -- 42 4 4 branching          # branching universe -> binary trees
zig build run -- 1 0                        # empty universe -> refuses to invent
zig build run-pure                         # the minimal-bias SK engine
zig build run-pure -- 0xC0FFEE learn       # cumulative learning (growing library)
zig build run-agent                        # curiosity sensorimotor agent (Stage 1)
zig build run-agent -- 0 6000 compare      # curiosity vs empowerment (Stage 2)
zig build run-agent -- 0 12000 affordance  # goal-directed affordance use (Stage 2.5)
zig build run-agent -- 0 30000 law         # discover the world's causal law from experience (Stage 3)
zig build run-invent -- phase0             # primitive-inventing engine: verifier sanity gate
zig build run-invent -- phase1             # evolution vs random search (rediscovers the gate)
zig build run-invent -- phase2             # the compounding library (the ratchet)
zig build run-invent -- phase3             # does one primitive buy compositional reach?
zig build run-invent -- phase4             # the tower: the next abstraction collapses the next task
zig build run-invent -- phase5             # warm-start curriculum vs the deceptive trap (fails)
zig build run-invent -- phase6             # quality-diversity (MAP-Elites) escapes the trap
zig build run-invent -- phase7             # the capstone: the engine climbs the tower by itself
zig build run-invent -- phase8             # rung-climb reliability (regression grading is ~100x faster)
zig build run-invent -- seq                # beat attention's weakness: discover a length-generalizing scan
zig build run-invent -- frontier           # §20 alien arc: recall↔length-gen map (opposite corners)
zig build run-invent -- novelty            # §20 alien arc: behavioural novelty certifier
zig build run-invent -- alien              # §20 alien arc: alien substrate reachability proof
zig build run-invent -- hunt               # §20 alien arc: QD frontier-breaker search (honest negative)
zig build run-invent -- probe              # §20 alien arc: dense-grading fix for recall is refuted
zig build run-invent -- curriculum         # §20 alien arc: K-ladder — addressing is reachable but rare (reliability)
zig build run-invent -- gamble             # §20 alien arc: gambling reaches the corner but it's a union of rediscoveries
zig build run-invent -- forbid             # §20 alien arc: forbid a known mechanism → re-spelled/known/wall, never novel
zig build run-invent -- fuse               # §20 alien arc: insufficiency task forces a known fusion search can't reach
zig build run-invent -- getrecall          # §20 alien arc: get recall reliably (reg-file + biased proposer): 0/8 → 8/8
zig build run-invent -- corner             # §20 alien arc: corner closed — pure QD reaches top-right 4/4 (was 0/4)
zig build run-invent -- openended          # §21 the pivot: novelty search rediscovers the accumulator; bottleneck → the descriptor
zig build run-invent -- infodesc           # §22 task-agnostic descriptor sees more, but exposes the novelty↔usefulness tension
zig build run-invent -- coevo              # §23 coevolution+transfer: FIRST POSITIVE — assembles the RMW counter direct search couldn't (reach)
zig build run-invent -- oecoevo            # §24 open-ended composition ladder: ratchets to depth 3-4; novel COMPOSITIONS of known atoms, not new atoms
zig build run-invent -- irreducible        # §25 the irreducibility test: §24's "novel" solvers all REDUCIBLE to known atoms; claim C rigorously backed
zig build run-invent -- atomforge          # §26 open-ended atom set: recursion runs but bottoms out at the substrate — composition all the way down (terminal)
zig build test                             # all tests across all engines
```

Requires Zig 0.14.1. Standalone; no dependency on sibling projects.

Example output:

```
[INIT] Library size: 4 base types, 2 combinators. Total nodes: 28.
[CHECK] identity : (Unit -> Unit) verified; (identity unit) reduces to UnitIntro.
[WAKE] Batch of 4 programs collected (unrolled counting patterns). Run lengths: [1, 2, 3, 4]
[SLEEP] Evaluating W-type proposals...
  Candidate Shape=Unit, Pos=[Bottom] -> Rejected (cannot host iteration: needs one leaf + one unary constructor)
  Candidate Shape=Unit, Pos=[Unit]   -> Rejected (cannot host iteration: needs one leaf + one unary constructor)
  Candidate Shape=Bool, Pos=[Bottom,Bottom] -> Rejected (...)
  Candidate Shape=Bool, Pos=[Unit,Bottom]   -> hosts pattern, saves 11 nodes
  Candidate Shape=Bool, Pos=[Bottom,Unit]   -> hosts pattern, saves 11 nodes
  Candidate Shape=Bool, Pos=[Unit,Unit]     -> Rejected (...)
[ACCEPT] Best proposal: W_Type_0x7
[MILESTONE] New type invented: W_Type_0x7 - node count saved: 11
>> ENGINE INVENTED THE NATURAL NUMBERS <<
[TELEMETRY] Compression ratio improved from 1.00 to 1.18.
[FINAL] Library: 6 types, 3 combinators, 45 total nodes.
```

## Modules (`src/`)

| File | Role |
|------|------|
| `types.zig` | `Type` nodes (`Unit`/`Bool`/`Bottom`/`Sensor`/`Action`/`Fun`/`Pair`/`Univ`/`W`) |
| `terms.zig` | `Term` nodes (de Bruijn; `WIntro`/`WRec` for invented W-types) |
| `nodecount.zig` | `nodeCountType` / `nodeCountTerm` — the sole objective function |
| `library.zig` | the growing stock of types + combinators; starts with only the permitted primitives |
| `checker.zig` | total type checker for the base system (STLC + Unit/Bool/Pair) |
| `evaluator.zig` | call-by-value evaluator (beta + projection) |
| `world.zig` | 32×32 grid sandbox: real physics, seeded universe, sensorimotor episode |
| `mcts.zig` | wake phase: bounded objective-guided search over programs (evaluates candidates) |
| `antiunify.zig` | generic repeated-application detection for the sleep phase |
| `wpropose.zig` | W-type enumeration + node-count cost-benefit + behavioural verification |
| `telemetry.zig` | logging and milestone markers |
| `logger.zig` | mirrors all output to `logs/wcore_<seed>.log` |
| `main.zig` | the sandboxed world→wake→sleep→verify pipeline |
| `sk.zig` | **wcore-pure:** SK-combinator substrate + reducer |
| `sk_compress.zig` | **wcore-pure:** compression-by-abstraction + behavioural classification |
| `sk_gen.zig` | **wcore-pure:** structured, noise & curriculum stream generators |
| `sk_learn.zig` | **wcore-pure:** persistent-library reuse + reference expansion (learning over time) |
| `pure_main.zig` | **wcore-pure:** the minimal-bias pipeline (single-stream + `learn` curriculum) |
| `agent.zig` | **wcore-agent:** online sensor-stream model + curiosity action selection + code-length telemetry |
| `empower.zig` | **wcore-agent:** learned transition model + empowerment `I(A;S')` planner (Stage 2) |
| `affordance.zig` | **wcore-agent:** value-iteration empowerment + R-max exploration; goal-directed affordance use (Stage 2.5) |
| `law.zig` | **wcore-agent:** induces the world's causal law from experience by MDL (Stage 3) |
| `agent_main.zig` | **wcore-agent:** sensorimotor loop (curiosity / empower / compare / affordance / law modes) |

## Status

**Baseline milestone complete**: the sleep-phase invention of the natural
numbers via W-type compression, driven solely by node-count reduction, with a
clean build and passing tests.

Post-milestone work (Section 11 of the design): real neural-guided MCTS over
`History`-typed programs, full dependent type-checking of `WRec`, a
`self_modify` action, E-graph law discovery, and category-theory emergence.
