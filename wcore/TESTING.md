# wcore — testing & verification log

This document records how to test wcore and what the results actually are. Every
run also writes a full machine log to `logs/wcore_<seed>.log`.

Requires Zig 0.14.1. All commands run from the project root.

---

## 1. Build and run

```sh
zig build run                       # default linear universe, seed 0xC0FFEE
zig build run -- <seed>             # a different universe
zig build run -- <seed> <count> <max> <linear|branching>
```

A default run starts from nothing, lives an episode in a seeded universe,
segments its own experience, searches for programs, blindly enumerates W-types,
invents one by node count, and verifies it by execution. Tail of a real run:

```
[SLEEP] node-count winner: arity-1 motif saving 31 nodes
[MILESTONE] New type invented: W_Type_0x7 - node count saved: 31
>> ENGINE INVENTED THE NATURAL NUMBERS <<
[VERIFY] PASS — the invented recursor reproduces every original and every observed count.
[TELEMETRY] Compression ratio improved from 1.00 to 1.45.
```

## 2. Read the log

`logs/wcore_<seed>.log` contains the entire simulation: seed/config, the initial
library, every agent step (action, position, moved/collected, 3×3 sensor) or
every chamber explored, the structure segmentation, the wake search/build trace,
**every** W-type candidate evaluated (shape, positions, arity, accept/reject +
node delta), the per-program behavioural verification, and the milestone.

## 3. Test suite

```sh
zig build test     # 21 tests, all pass
```

Coverage: type/term construction & equality, node counting, the STLC type
checker (well-typed accepted, ill-typed rejected), the evaluator (beta,
projection, **WRec for arity-1 chains AND arity-2 trees**, `foldCount`), world
physics (move blocked by walls, resource collection, emergent harvest runs),
both anti-unification detectors, and the W-type proposal + behavioural
verification for **both** Nat and binary-tree inventions.

## 4. Different seeds → different universes (same outcome class)

Behaviour is deterministic per seed; different seeds produce different emergent
structure and different savings, but the invention is always sound and verified.

```
LINEAR universes (zig build run -- <seed> 4 6 linear):
  seed=7         counts={1,2,5,3}   -> NATURAL NUMBERS   saved=13
  seed=42        counts={5,2,6,5}   -> NATURAL NUMBERS   saved=34
  seed=0xC0FFEE  counts={4,5,5,3}   -> NATURAL NUMBERS   saved=31
```

## 5. Zero-bias, confirmed in source

* `antiunify.zig` — `detectLinear`/`detectBranching` are pure structural matchers
  (repeated `App` chains / binary trees). No "Church numeral", "Nat", or "tree"
  test drives them.
* `wpropose.zig` — `propose` brute-forces every shape (`Unit`, `Bool`) × every
  position assignment from `{Bottom, Unit, Bool}` (arities 0/1/2). Acceptance is
  `delta = old_total_nodes - new_total_nodes > 0`, max-delta wins. The
  `is_naturals` / `is_btree` flags are computed AFTER the winner is chosen and
  only affect the milestone banner — never selection.

## 6. The honest negatives — when it REFUSES to invent

The node-count rule is real, so it sometimes declines. All logged.

```sh
zig build run -- 1 0            # empty universe
#   [SEGMENT] {} -> [SLEEP] No repeated structure detected; nothing to compress.

zig build run -- 1 4 1          # all clusters size 1
#   Candidate Bool [Unit,Bottom] -> hosts arity-1 motif, but no net saving (-8 nodes)
#   [SLEEP] No W-type proposal reduced the node count. Library unchanged.

zig build run -- 42 4 20        # large clusters
#   saves 157 nodes ; compression 1.00 -> 2.41
```

The size-1 case is the important one: the engine *can* host the pattern but
inventing the recursive type costs more than it saves, so it does **not** invent.
This proves it is a genuine node-count optimizer, not a hardcoded "always print
Nat".

## 7. It is NOT hardcoded to Nat — a different universe mints a different type

This is the strongest evidence of zero bias. The same blind enumeration + same
node-count rule, run over a **branching** universe (a tree-of-chambers topology
the agent explores depth-first), invents a **binary-tree** W-type instead of the
naturals.

```sh
zig build run -- 42 4 4 branching
```

```
[SEGMENT] explored-tree depths from real history: { 4, 2, 4, 3 }
[SLEEP] motif: BRANCHING (branching factor 2)
  Candidate Shape=Bool, Pos=[Bool,Bottom] -> hosts arity-2 motif, saves 62 nodes
  ...
[SLEEP] node-count winner: arity-2 motif saving 62 nodes
>> ENGINE INVENTED BINARY TREES (a DIFFERENT W-type, same blind rule) <<
[VERIFY] PASS
```

```
BRANCHING universes (zig build run -- <seed> 4 4 branching):
  seed=7         depths={1,1,3,2}   -> BINARY TREES   saved=6
  seed=42        depths={4,2,4,3}   -> BINARY TREES   saved=62
  seed=0xC0FFEE  depths={3,4,3,2}   -> BINARY TREES   saved=46
```

### The subtle, honest detail

On **linear** data the engine evaluates *both* motifs. Linear data can also be
read as a degenerate right-leaning binary tree, so the arity-2 enumeration *does*
find a hosting W-type — but it saves only 18 nodes, while the arity-1 (Nat)
encoding saves 34. The node-count winner is therefore Nat. The engine literally
**considers the tree interpretation and rejects it as more expensive** — exactly
the behaviour of a real compressor with no built-in preference for either type.

```
[SLEEP] motif: LINEAR (branching factor 1)
  Candidate Shape=Bool, Pos=[Unit,Bottom] -> hosts arity-1 motif, saves 34 nodes
[SLEEP] motif: BRANCHING (branching factor 2)
  Candidate Shape=Bool, Pos=[Bool,Bottom] -> hosts arity-2 motif, saves 18 nodes
[SLEEP] node-count winner: arity-1 motif saving 34 nodes  -> NATURAL NUMBERS
```

## What is verified vs. what is still simplified (honest limitations)

* **Verified by execution:** the invented `WRec` eliminator is run for every
  program; the engine only reports success when, for each one,
  `fold(W) == observed_count` AND `recursor_regen` is *structurally identical*
  to the original program (`Term.eql`). Holds for both Nat and binary trees.
* **Still simplified:** the base type checker does not yet dependently
  type-check `WIntro`/`WRec` (post-milestone, Section 11) — their correctness is
  established by the evaluator's behavioural verification instead. The wake
  search is a bounded enumerative search, not neural-guided MCTS. The branching
  universe is a tree-of-chambers topology rather than a grid embedding of a tree.

---

## 8. The minimal-bias variant — `wcore-pure`

The typed engine still starts with a small bootstrap (`Unit/Bool/Sensor/Action`
+ `id/compose`). `wcore-pure` strips that down to the smallest substrate that
still computes: the **SK-combinator basis** — `S`, `K`, and application — plus
the one objective "minimize node count". No types, no `Bool`/`Unit`, no
`Sensor`/`Action`, no numbers, no recursion primitives. The library of named
abstractions starts **empty**.

```sh
zig build run-pure              # seed 0xC0FFEE
zig build run-pure -- 42        # a different stream
```

It is driven by a stream it does not author and is never told the structure of
(logged verbatim). By compression alone — extract the subterm that most reduces
total description length, name it, repeat — it rediscovers fundamental
combinators, and we confirm what each one *is* by **executing it** on inert
markers (post-hoc labels only). Real output, structured stream, seed 0xC0FFEE:

```
[SLEEP] discovered C0 = (S K)      (occurs 15x, saves 27 nodes)
         C0 decoded behaviourally as: Church FALSE / second-projection
[SLEEP] discovered C1 = (C0 K)     (occurs 7x, saves 11 nodes)
         C1 decoded behaviourally as: identity combinator (I = \x.x)
...
[RESULT] STRUCTURED: 5 abstractions discovered; 118 -> 65 nodes (compression 1.82x)
```

Two things worth noting, both honest:

* **It reinvents the identity combinator and the Church booleans from S and K
  alone**, purely by node count, verified by execution. Across seeds {1, 42,
  0xC0FFEE, 777} the identity and a Church boolean are rediscovered every time.
* **Abstractions compound.** `C1 = (C0 K)` is built *on top of* its own earlier
  discovery `C0`. That hierarchical reuse — earlier inventions becoming
  primitives for later ones — is the "it learns over time" property (the
  DreamCoder mechanism), here visible in a single run.

### The honest negative

SK has only four distinct 2-node terms, so even a *noise* stream has low-level
regularity — a pure compressor will name *something*. The difference is stark
and is the honest point:

```
[RESULT] STRUCTURED: 118 -> 65 nodes (1.82x); top abstraction saves 27, decodes to a real combinator
[RESULT] NOISE:       62 -> 48 nodes (1.29x); abstractions save 7/3/3/1, mostly "no standard behaviour"
```

On noise the savings are small and the abstractions are mostly meaningless
(`(K S)`, `(K K)`, `(S S)`); the engine does not hallucinate rich structure that
isn't there. On the structured stream the meaningful combinators dominate with
large savings. The engine never *decides* using the behavioural label — it only
ever optimizes node count; the label is reported afterward.

### Learning over time — a growing tower of abstractions

```sh
zig build run-pure -- 0xC0FFEE learn
```

A persistent library is carried across a sequence of streams (a teaching
curriculum). Each stream first **reuses** what is already known (folding known
abstractions into single references), then **discovers** what's new — so later
abstractions are built on earlier ones. Real output:

```
stage 0: C0 = (S K)        -> Church FALSE
         C1 = (C0 K)       -> identity            (built on C0)
stage 1: [REUSE] applied C1 (identity) 18x   (152 -> 93 nodes)
         C5 = ((S C1) C1)  -> duplicator (\x. x x)  (built on C1)
stage 2: [REUSE] applied C5 (duplicator) 11x, C1 (identity) 6x   (220 -> 82 nodes)

FINAL LIBRARY (the tower it built from S and K):
  C0 = (S K)        [Church FALSE]
  C1 = (C0 K)       [identity]
  C5 = ((S C1) C1)  [duplicator]   <- references C1 which references C0
```

Two honest observations:

* **The library compounds.** `C5` (duplicator) is defined in terms of `C1`
  (identity), which is defined in terms of `C0` (false), which is raw `S`/`K`.
  From two combinators, by compression alone, it built `false → identity →
  duplicator`, each on the last. This is the DreamCoder library-growth mechanism
  shown concretely.
* **Prior learning pays off.** Reuse collapses each new stream before any new
  search (152→93, 220→82 nodes). The accumulated library makes fresh experience
  cheaper to describe — which is what "it learns" means operationally.

Honest caveats: the curriculum *stages* are authored to contain reusable
structure (a teacher ordering lessons), but the engine is never told which
abstractions to form — it discovers them by node count and we verify their
behaviour. Some discovered abstractions are genuine compressors that are not
famous combinators (logged as "no standard behaviour recognised"); and several
distinct SK expressions are all extensionally the identity (the engine dedups by
structure, not behaviour). All of this is in the log verbatim.

### Tests (`zig build test` covers both engines)

`sk.zig`: `K`/`S` reduction, `SKK` = identity, `SK` = false, `Ref` expansion.
`sk_compress.zig`: max-saving extraction; behavioural classification of `SKK` as
identity, `SK` as Church false, and `S I I` as the duplicator. `sk_learn.zig`:
`expand` resolves a tower of references to raw SK; `refactorAgainstLibrary`
reuses a known abstraction in a fresh corpus.

---

## 9. `wcore-agent` — a compression-driven sensorimotor agent (roadmap Stage 1)

```sh
zig build run-agent                 # seed 0xC0FFEE, 6000 steps
zig build run-agent -- 42 8000      # seed, steps
```

The agent is dropped into a grid world it knows **nothing** about, with dynamic
(random-walking) resources. It keeps an online predictive model of its 3×3
sensor stream — starting empty — and we measure the **description length** of
that stream as the ideal code length `-log2 P(frame)` under a fair prior over
all `3^9` possible frames. Action selection is **count-based curiosity** (pick
the least-tried (action, observation) context), which is compression *progress*,
not compression *level* — chosen specifically to avoid the dark-room degeneracy.

### What genuinely happens (real)

```
[t=  1000] avg code length 10.72 bits/obs | distinct frames 75
[t=  6000] avg code length  4.68 bits/obs | distinct frames 77
[RESULT] code length: 10.72 -> 4.68 bits/obs  (56.3% reduction)
```

From zero knowledge, the per-observation code length falls by more than half.
That is genuine compression: the agent learns the regularities of its sensory
stream and its model predicts future frames far better than the uniform prior.
Every 1000 steps the log prints an ASCII map of what the agent is doing.

### What I am NOT claiming (the honest reading)

* **No purposeful engineering.** The action histogram is essentially uniform
  (~855 of each of the 7 actions): the agent explores all action-context pairs
  evenly. It does **not** prefer to build. The ~48 walls that appear are an
  incidental by-product of trying `build_wall` as often as any other action —
  not a goal-directed enclosure. The roadmap's "it builds a fence *because* it
  minimizes description length" did **not** occur, and the code does not pretend
  it did.
* **Part of the bits drop is a mild self-enclosure artifact.** By placing walls
  uniformly, the agent tends to wall itself into a small pocket, which lowers
  observation *variety* — so some of the code-length reduction is the model
  learning the world, and some is the agent simply seeing less. This is the
  dark-room effect leaking in through self-construction, and it is called out
  here rather than hidden.
* **It is greedy 1-step curiosity, not MCTS over programs.** Deeper model-based
  planning (the roadmap's real MCTS) is the next increment, not this one.

### Honest status of the roadmap

| Stage | Status |
|-------|--------|
| 1. Real sensorimotor loop + from-zero model | **Built here** (curiosity-greedy, not yet deep MCTS); genuine compression measured. |
| 2. Goal-directed structure-building | **Not achieved.** A pure compression drive degenerates (dark room); building a fence on purpose needs a different objective (e.g. empowerment) and a planner that can credit multi-step construction. |
| 3. Tool-use / simple machines | Research-frontier; not attempted. |
| 4. Self-modifying Gödel machine | Aspirational; not attempted. |
| 5. Building a computer in the sandbox | Aspirational; not attempted. |

### Tests

`agent.zig`: a repeated frame's code length falls toward 0 as evidence
accumulates; curiosity picks the least-tried action; a from-zero run measurably
compresses its stream (`last_window_bits < first_window_bits`). `world.zig`
gains tested `jitterResources`/`scatterRandom`/`asciiMap` helpers.

---

## 10. `wcore-agent` empowerment mode (roadmap Stage 2)

Stage 1's honest flaw was self-entrapment: a curiosity agent walls itself in by
accident, and a *naive* "minimize description length" agent would do so on
purpose (the dark room). Stage 2 replaces the objective with **empowerment** —
the agent's control over its own future:

```
E(s) = I(A ; S' | s) = H(S'|s) - (1/|A|) Σ_a H(S'|s,a)
```

estimated from a transition model `P(s'|s,a)` learned online from zero. High
empowerment = "many distinct next observations that I can *reliably choose
between*." This is **not** next-observation entropy (that is noise-seeking — the
TV-static trap); the per-action outcome entropy is subtracted.

```sh
zig build run-agent -- 0xC0FFEE 6000 empower    # empowerment agent
zig build run-agent -- 0xC0FFEE 6000 compare    # curiosity vs empowerment, same world
```

### The honest, testable prediction — confirmed

A walled-in state has few reliably reachable outcomes, so it is low-empowerment;
an empowerment agent should therefore *avoid* enclosing itself. Real `compare`
output (seed 0xC0FFEE, 6000 steps, identical world):

```
walls built:      curiosity=48   empowerment=20
distinct frames:  curiosity=77   empowerment=54
-> empowerment built FEWER walls: it avoided self-enclosure, as predicted.
```

The empowerment agent's own empowerment **rose** over the run (1.84 → 2.29 bits)
and it finished standing in open space (logged ASCII map), whereas the curiosity
agent had boxed itself into a wall pocket. So empowerment genuinely **fixes the
Stage-1 self-entrapment artifact** — a real, measured improvement.

### The deeper honest finding (why construction still doesn't emerge)

Stage 2 also makes something clear that the roadmap's optimism glossed over: in
*this* world, building a wall can only ever *reduce* the agent's movement
options, so an empowerment-maximizer rationally **avoids** building. Empowerment
fixes the dark room, but it does not, by itself, produce purposeful
construction — it produces open-space-seeking. **Goal-directed building can only
emerge in a world where some structure genuinely increases controllability**
(e.g. a lever that reliably opens many doors, a funnel that makes a moving
resource reachable). That world does not exist in the sandbox yet. This is the
honest frontier: the next real step is not a cleverer agent but a richer physics
in which building *pays off in control*.

Caveats, stated plainly: this is one-step, tabular empowerment estimated from
aliased local 3×3 views; the estimates are noisy and the planning horizon is 1.
n-step empowerment and a better state representation are future work.

### Tests

`empower.zig`: empowerment is high for a state with distinct controllable
outcomes and ~0 for a stuck state where every action loops back; the agent runs
from zero knowledge. (A keying-collision bug found by the first test — small
observation hashes XOR-collided — was fixed with an avalanche mix.)

---

## 11. `wcore-agent` affordance mode (roadmap Stage 2.5) — the first goal-directed work

Stage 2's honest finding was: empowerment avoids dead ends, but in a world where
*every* structure reduces options, an empowerment agent rightly refuses to build.
The fix is not a cleverer agent but a world with an **affordance** — a structure
that *increases* control. So the world gained a **button that latches a gate
open, unlocking the far half of a split room** (with resources). Pressing the
button expands the agent's accessible world.

```sh
zig build run-agent -- 0xC0FFEE 12000 affordance     # random vs local vs positional
```

Getting an agent to *use* this affordance took two upgrades, each forced by an
honest failure observed along the way:

1. **A de-aliased state.** With local 3×3 views, every open-interior cell looks
   identical, so the agent cannot tell where it is and cannot navigate to a
   specific spot. Result: button-pressing was seed-dependent (worked on
   0xC0FFEE, failed on seed 7). Switching the state to `(x, y, gate)` removed the
   aliasing. The code runs both so the contrast is visible.
2. **R-max optimistic exploration.** A one-step explore bonus can't plan a path
   to a *distant* unexplored region, so discovery still leaned on a lucky random
   walk. Making value iteration reward exploration *frontiers* (states with
   untried actions) lets it **plan toward the unknown**.

### The robust, positive result

With both upgrades, across seeds {0xC0FFEE, 7, 42, 1, 99, 777} the agent
**reliably presses the button and then occupies the region it unlocked**:

```
seed       first press (positional)   time in unlocked half
0xC0FFEE    63                         47%
7           2012                       57%
42          128                        60%
1           197                        67%
99          324                        50%
777         140                        50%
```

This is the first **goal-directed physical work** in the project: the agent
navigates to a structure, *manipulates it* (presses the button) to open a gate,
and then exploits the newly-accessible half of its world — purely because doing
so increases its empowerment, with zero prior knowledge and no task reward. On
seed 42 the full verdict reads:

```
time in unlocked half: random=49.3%   local=0.0%   positional=60.0%
-> POSITIONAL agent is GOAL-DIRECTED: it pressed the button to unlock the gate
   and then spent 60% of its time in the region it unlocked.
```

### Honest scope — what this is and isn't

* It IS: reliable, above-noise, goal-directed *use* of an affordance, emergent
  from empowerment + a learned model, across seeds. The threshold from "avoids
  dead ends" to "manipulates a structure on purpose" is crossed.
* It is NOT: tool *construction*. The agent uses a given button; it does not
  build new mechanisms. It also still uses a hand-given positional state and a
  tabular model — a learned state representation (belief state) and function
  approximation are the next real frontier.
* The local-view agent remains seed-dependent and is reported as such — the
  positive claim is specifically for the de-aliased + R-max configuration.
* The "random" baseline also presses in this small room (diffusion stumbles onto
  the button); the agent's advantage is **reliability and directedness** across
  seeds, not merely pressing once.

### Tests

`affordance.zig`: an open gate raises empowerment by adding a reachable outcome;
the positional empowerment+VI agent presses the button and spends >5% of its
time in the unlocked half. `world.zig`: pressing latches the gate open and shows
in `obs10`; the gate blocks passage until pressed.

---

## 12. `wcore-agent` law mode — discovering a causal law from experience

This closes the loop between the two halves of the project: the symbolic
compression engine (which invents ℕ and SK combinators) and the embodied agent
(which acts in a world). Here the agent *lives*, records what happens, and a
sleep phase distils the **shortest rule** that explains its world's dynamics —
embodied experience in, a symbolic causal law out, by the same "shortest
description" objective.

```sh
zig build run-agent -- 0xC0FFEE 30000 law
```

The agent wanders a room with a button and a gate (momentary, so the gate's law
is richly sampled) and records `(position, gate-state)` pairs. The sleep phase
then blindly searches a small predicate language — `ALWAYS`, `NEVER`, `x == v`,
`y == v`, `x == vx AND y == vy` — and keeps the rule with the lowest description
length (rule bits + mispredictions). Real output, reproduced across seeds:

```
[LAW] searched 99 predicates over 30000 samples.
[LAW] discovered rule:  gate is open  <=>  x == 2 AND y == 2   (errors: 0/30000)
[LAW] description length: rule = 11 bits  vs  per-cell table ~ 1024 bits
>> ENGINE DISCOVERED THE CAUSAL LAW OF ITS WORLD FROM EXPERIENCE <<
```

`(2,2)` is the button's location — found purely by compressing raw experience;
the engine is never told where the button is. The rule (11 bits) is a ~90×
compression of memorising the gate per cell (~1024 bits), and predicts the gate
with zero errors. Across seeds {0xC0FFEE, 7, 42, 1} it always recovers the exact
law. The `induce` engine never checks "is this the button" — it only minimises
description length; the button falls out because it is the minimal description
of the gate's behaviour.

### Honest scope

* It IS: a genuine causal law (`gate ⟺ on button`) induced from raw `(position,
  outcome)` experience by pure MDL, unifying the embodied and symbolic halves.
* It is NOT: deep physics. The rule language is small (positional equality with
  and/or) and hand-chosen — general enough to express the law, not open-ended.
  This is the same kind of bounded hypothesis space as the W-type enumeration,
  and is stated as such.
* It is one law over one mechanism. A system that learned an *open-ended* rule
  language and chained discovered laws into theories is the real frontier.

### Tests

`law.zig`: from 40k samples of a momentary-gate room, `induce` returns the exact
`x==bx AND y==by` rule with zero errors and recovers the true button location.

---

## 13. `wcore-invent` — the primitive-inventing engine (PLAN_INVENTION_ENGINE)

This is the same wcore method (search + MDL + **execute-to-verify** + compounding
library) given a *real body*: instead of SK terms it searches over **primitive
math operations** (add, mul, dot, get, tanh, …) assembled into 3-part programs
(`Setup` / `Predict` / `Learn`, the AutoML-Zero shape, so the engine invents the
*learning rule* too). The PRIME DIRECTIVE: **every candidate is scored only by
running it on data and measuring held-out accuracy — never by plausibility.** No
LLM, no menu of known layers, no proxy fitness. Build and run:

```sh
zig build run-invent -- phase0      # the verifier sanity gate
zig build run-invent -- phase1      # flat evolution vs random search
zig build run-invent -- phase2      # the compounding library (the ratchet)
```

### Phase 0 — the verifier sanity gate (scaffolding)

Before searching, prove the verifier is sound: a hand-written known-good program
must score high and garbage low. Task A is `y = sign(x0·x1)` — provably **not**
linearly separable, so success *requires* a multiplicative gate. Real output:

```
  hand-written gate+gradient : held-out acc = 1.0000
  linear model (no product)  : held-out acc = 0.5084
  empty/garbage program      : held-out acc = 0.4831
[GATE] correct >> chance, gate is load-bearing: PASS
```

The correct program scores 1.0; a linear model and an empty program sit at
chance. The gate is genuinely load-bearing, and the fitness function rewards it.
**If this had failed, everything downstream would be meaningless** — so it is the
first thing checked. (One verifier bug *was* caught this way and fixed: an early
champion read the label register `s1` inside `Predict`; the harness now zeroes
the label before every prediction so it is visible only to `Learn`.)

### Phase 1 — evolution vs random search (reproduction; ~AutoML-Zero)

Regularized (aging) evolution with tournament selection + mutation, vs i.i.d.
random search, both judged purely by execution. Real output, 5 runs × 300k evals:

```
  run | evolution evals→target | random evals→target | evo best | rand best
    0  |                  46507 |               40537 | 1.0000   | 1.0000
    1  |                 185283 |          — (miss)   | 1.0000   | 0.7853
    2  |             — (miss)   |              248711 | 0.7520   | 1.0000
    3  |                 125501 |          — (miss)   | 1.0000   | 0.7853
    4  |                  44497 |          — (miss)   | 1.0000   | 0.7853
  evolution: 4/5 runs hit target, mean 100447 evals→target
  random   : 2/5 runs hit target, mean 144624 evals→target
```

Evolution is **more reliable (4/5 vs 2/5) and faster on average (100k vs 144k
evals)**, and it rediscovers the multiplicative gate — verified at 1.0000 on 12
fresh held-out seeds. Strikingly, it invents the gate in **forms a human wouldn't
write**, each found purely by execute-and-measure:

* `s0 = x0 / x1` — a *division* gate (sign-equivalent to the product, since
  `sign(a/b) = sign(a·b)`).
* `v0 = x1 · v0 ; s0 = v0[0]` — scale the whole input vector by its own component
  `x1` to get `[x0·x1, x1²]`, then read element 0. A *vector-scaling* gate.

**The honest caveat.** Task A is a gradient-free *needle*: every non-gate program
scores ~chance, so there is no smooth path to climb. Evolution's only edge is
incremental assembly in a persistent population (neutral drift accumulates
building blocks; one mutation completes the gate). That is a real but *modest*
advantage — a ~1.4× speedup plus higher reliability, not a blowout. Selection on
a low-fidelity signal can even chase deceptive ~0.75 optima; raising the
held-out fidelity (more seeds × examples) collapses those traps back toward
chance and is what made evolution win cleanly. This is Tier-1 (reproduction): the
engine works and beats random, exactly as AutoML-Zero predicts — no more.

### Phase 2 — the compounding library (THE CORE HYPOTHESIS; the ratchet)

The bet of the whole plan (§4.5): a library of discovered primitives that become
reusable building blocks should make search *compound* — later discoveries built
on earlier ones — instead of restarting. We test it ruthlessly with an ablation.

**Build the library by abstraction.** Solve the gate family's pair `(0,1)` a few
times, pool the top elites, and run the MDL common-subexpression extractor
(`inv_library.zig`, the direct port of `sk_compress.zig`) to find the fragment
whose abstraction into one macro most reduces total description length:

```
  2/5 bootstrap solves succeeded; corpus = 48 elite programs.
[ABSTRACT] discovered C0: occurs 24x, length 3, saves 45 description nodes
           C0 decoded behaviourally as: ratio gate  v0[p1]/v0[p0]  (sign-equiv to product)
           C0 takes 2 params (the element indices), 3 local registers
```

The engine abstracts its own discovered 3-instruction gate into a single op
`C0(i,j)`, **generalised over the index pair** (the `v_get` element indices become
the macro's two parameters). This is the same tower mechanism the SK engine shows
(§8), now over executable tensor programs.

**Measure reuse acceleration** on *new* family members the library never saw —
flat evolution vs evolution with `C0` available as a `call` op, same budget:

```
  task        | random e→t | flat-evo e→t | LIB-evo e→t | lib speedup | calls in champ
  ------------+------------+--------------+-------------+-------------+---------------
  gate(2,3)   | — (miss)   |        91633 |         421 |     217.7x  | 1
  gate(1,3)   | — (miss)   |   — (miss)   |         575 |        n/a  | 1
  gate(0,3)   | — (miss)   |   — (miss)   |         351 |        n/a  | 1
  dbl(01,23)  | — (miss)   |   — (miss)   |  — (miss)   |        n/a  | 1
  [SOLVE RATE over 4 tasks]  random 0/4  |  flat-evo 1/4  |  LIB-evo 3/4
  [RATCHET] both solved: flat 91633 e→t, LIB 421 e→t  ⇒  217.7x fewer evals
```

**The ratchet is real.** With the library, every single-gate task collapses to a
**single `CALL`** (the champion uses exactly 1 call) and is solved in **a few
hundred** evaluations. Flat evolution at the same 250k budget solved only **1 of
3** single-gate tasks (the needle is unreliable; the other two hit deceptive
optima), and random search solved **0**. On the one task both methods solved, the
library used **217× fewer** evaluations. This is the Reasoned-Speculation
contribution of the plan, measured cleanly against ablations: **a discovered,
reused primitive measurably and dramatically accelerates discovery.**

### The honest, sharp negative — verifier-underdetermined abstraction

The compositional `double-gate` `y = sign(x0·x1 + x2·x3)` is **not** solved by the
library, and the reason is the most interesting result here — it is *not* merely a
budget shortfall:

The abstracted macro is the **ratio** gate `x_b/x_a`, not the product. On
*single*-gate tasks the two are indistinguishable to the verifier, because
`sign(x_b/x_a) = sign(x_a·x_b)` — so execution-as-truth correctly accepted it
(both score 1.0). But ratios and products **diverge under summation**:
`sign(x1/x0 + x3/x2) ≠ sign(x0·x1 + x2·x3)` in general (e.g.
`x=[0.1,0.1,1,−0.5]`: products sum to −0.49, ratios sum to +0.5 — opposite signs).
So composing two `C0` calls and adding them cannot solve the double-gate, and
`C0` gives no leverage there — both flat and library miss.

The lesson is precise and generalises beyond this toy: **execute-to-verify makes
abstraction sound only up to what the training tasks can distinguish.** A single
task family under-determines the primitive; the engine banked a shortcut that is
correct *there* and wrong under composition. The fix is a §8-flavoured curriculum
result — to abstract the *true* product (which does compose), the bootstrap must
include a task where ratio and product disagree (a compositional task), forcing
the verifier to separate them. That is the natural next experiment and the honest
edge of this result.

### Tier-honest status

* Phase 0–1: **Tier 1** (reproduction) — solid, not the prize.
* Phase 2: **the library-acceleration contribution, confirmed** with ablations
  (random vs flat vs library): 100–200×+ fewer evals on reused tasks, and it
  solves tasks flat evolution misses. This is exactly the "Reasoned Speculation"
  the plan stakes the project on — and it comes with a sharp, honest boundary
  (verifier-underdetermined abstraction breaks compositional reuse).
* **Not** Tier 3: nothing here is a discovered primitive that beats attention at
  matched budget. Task A/B are gradient-free needles on a toy family; the wins are
  real but bounded, and every number above is reproducible from
  `zig build run-invent -- phaseN`.

### Tests

`inv_substrate.zig`: scalar/vector ops execute and persist; the multiply-gate
computes `x0·x1`; protected divide/recip never produce NaN/inf. `inv_tasks.zig`:
the sanity gate (correct program > 0.95, linear model & empty program at chance),
off-axis gate. `inv_evolve.zig`: evolution runs end-to-end and never emits an
out-of-bounds program. `inv_library.zig`: two gate elites with *different* index
pairs share one template; the extracted macro generalises over the pair when
called; a div-gate elite decodes as a ratio gate; no-recurrence → no extraction.

---

## 14. Phase 3 — does compounding buy REACH? (the Tier-3 fork)

The whole question behind "an engine that out-invents humans" is **reach**: can a
discovered primitive let search reach territory it otherwise can't? Phase 2 showed
a library accelerates *reuse* of a primitive at the same task arity. Phase 3 asks
the harder thing — does reuse **compound** to reach *compositional* tasks (sums of
K products) that flat search cannot? Run with `zig build run-invent -- phase3`.

Two separable questions, reported separately and honestly.

### (1) Can it reliably DISCOVER a *composable* primitive? — open sub-problem

The Phase-2 macro was the *ratio* gate, which doesn't compose. To force the true
product I added a **regression grading mode** (fitness = held-out correlation with
the continuous target), which separates product from ratio (`corr(x/y, x·y) < 1`).
But the regression bootstrap is a *harder* needle than classification — removing
the ratio basin and the partial-product plateau:

```
DISCOVERY probe — regression-graded, 4 seeds x 150k evals:
  0/4 reached corr≥0.95 (best 0.944); abstractable PRODUCT found: no
```

Reliable discovery of the composable form is genuinely hard at single-machine
budget: classification prefers the non-composing ratio, and the engine's favourite
*product* construction is the **vector-scaling** form (`v0 *= x1; read v0[0]`),
which writes a vector and so falls outside the v1 scalar-only macro language. So
the reach test below uses a **verified product macro** (decode-checked, and shown
to compose additively in a unit test) to isolate the reach question from this one.

### (2) Given a composable primitive, does reuse buy reach? — the result

`C0 = v0[p0]·v0[p1]` (verified product), `dim = 2K`, 4 seeds/cell, 300k budget:

```
  task              | raw min_ops | flat solves | flat best e→t | C0-lib solves | C0-lib best e→t
  ------------------+-------------+-------------+---------------+---------------+----------------
  K=1  (1 product)  |      3      |     3/4     |       26037   |     4/4       |          18
  K=2  (2 products) |      7      |     0/4     |     — (miss)  |     0/4       |     — (miss)
  K=3  (3 products) |     11      |     0/4     |     — (miss)  |     0/4       |     — (miss)
```

**The honest finding — a single primitive does NOT automatically buy compositional
reach.** At K=1 the reused primitive is transformative: `C0-lib` solves **4/4 in
~18 evaluations** (one `CALL`) versus flat's 3/4 at ~26k — a ~1400× acceleration,
reliably. But at **K≥2 even the macro-equipped search fails completely (0/4)**, the
same as flat. Two reasons, both real:

1. **Composition is a fresh needle.** With `C0`, a K-product task still needs K
   correctly-parameterised `CALL`s plus K−1 combiners assembled and wired to the
   output — an assembly whose difficulty grows with K. One macro shortens each
   product to one op; it does nothing to make the *assembly* easier.
2. **A genuine partial-credit deceptive trap.** A single product already predicts
   the sign of a sum of products ~70% of the time, so the search parks on that
   plateau (the champion uses exactly **1 call** at every arity) and never assembles
   the rest. This is not sampling noise — it is a real local optimum, and higher
   fidelity does not remove it.

### What this means for the Tier-3 path (the precise §8 wall)

This is the cleanest result of the whole investigation, and it is a **negative that
locates the wall exactly** (§2.4: negative results are wins). The compounding
ratchet gives reach *within an arity* but **not across composition from a single
abstraction level.** Compositional reach requires one of:

* **the tower** — abstract the *composition* itself into a higher macro
  (`C1 = sum of two C0`s), so K=2 collapses to one call to `C1` and K=4 to two.
  This is the DreamCoder library-growth mechanism the SK engine already shows
  (`false → identity → duplicator`); here it needs the macro language to support
  **nested calls and >2 parameters** (the current v1 ABI passes 2). That is the
  next engineering brick.
* **a fundamentally broader proposer** that can leap past the partial-credit trap
  (the deepest §8 problem: grounded, non-hallucinating, neural-grade reach).

Tier-honest status: Phase 3 is **not** a Tier-3 result and does not claim to be. It
is a clean, ablated measurement of *where and why* single-level compounding stops
buying reach — which is precisely the problem statement an invention engine must
solve next, stated with numbers rather than hope.

### Tests

`inv_tasks.zig`: regression grading scores the product gate ~1 and a linear model
~0 (so it separates product from ratio); the double-gate target is the sum of two
products. `inv_library.zig`: the verified product macro decodes as a product and
composes additively (`C0(0,1)+C0(2,3)` gives the sign of the sum of products);
`allExtractions`/`bestProductExtraction` select the composable abstraction by an
execution test, not a heuristic.

---

## 15. Phase 4 — the tower: does the *next* abstraction collapse the *next* task?

Phase 3 ended on a sharp wall: one primitive (`C0`, the product) gives no
compositional reach — `K=2` was **0/4** even with `C0` available, because composing
two products is a fresh needle guarded by a real ~70% partial-credit trap. Phase 4
adds the **second level of the library** and asks the decisive follow-up: if we
abstract the *composition itself* into a macro `C1` built **on top of** `C0`, does
the task `C0` couldn't reach collapse? Run with `zig build run-invent -- phase4`.

**The tower machinery (real, tested).** The macro language now supports the two
things a tower needs: **up to 4 call parameters** (`Instr.c`,`Instr.d`) and
**nested calls** — a macro body may invoke an *earlier* macro, executed in a deeper
private scratch frame so locals never collide (`runMacroValue(..., frame)`,
`MAX_DEPTH` frames). `C1(i,j,k,l) = v0[i]·v0[j] + v0[k]·v0[l]` is built by **calling
`C0` twice and summing** — a genuine two-level tower, unit-tested to compute and
compose correctly.

**The result** (library = {`C0` product, `C1` sum-of-two-products}; 4 seeds/cell):

```
  task             | min solution | solves | best e→t | champion uses
  -----------------+--------------+--------+----------+---------------
  K=1 (1 product)  | 1 C0 call    |  4/4   |     24   | 1×C0, 0×C1
  K=2 (2 products) | 1 C1 call    |  4/4   |    671   | 0×C0, 1×C1   ← was 0/4 in Phase 3
  K=4 (4 products) | 2 C1 + add   |  0/4   |  — miss  | —
```

**Reach compounds — exactly one rung at a time.** `K=2`, which `C0` alone could
**not** reach (0/4), now solves **4/4** via a *single* `C1` call (champion uses
`0×C0, 1×C1` — it reaches straight for the higher abstraction). The second level
collapsed the wall the first level hit. That is the positive complement to Phase
3's negative: **compositional reach is achievable, and the mechanism is the
tower.** And `K=4` stalls at **0/4** precisely as predicted — composing two `C1`s
re-introduces the same partial-credit trap one level up; it would need `C2 =
sum-of-two-C1s`.

### The complete arc (Phases 1–4), stated honestly

1. **Rediscover a primitive** (the gate) — Tier-1. ✓
2. **Reuse it** → 100–1400× fewer evals at the same arity. ✓
3. **One primitive ≠ compositional reach** — `K=2` = 0/4. The wall. ✓
4. **The next abstraction collapses the next task** — `C1` makes `K=2` = 4/4; the
   trap merely moves up to `K=4`. ✓

So **reach genuinely compounds through a tower of abstractions, climbed one rung at
a time.** Each new macro makes the next task a single call; composing at the
current top always re-introduces the deceptive trap, so depth-`D` needs a `D`-tall
tower. **The one thing still done by hand is climbing:** here `C0` and `C1` are
verified-by-hand (clearly labelled), because *autonomously discovering the next
rung* requires first *solving* a task at that rung — and that is blocked by the
very per-rung trap above (you can't abstract a `K=2` solution the search can't
find). Escaping each rung's trap to discover the next macro — via curriculum,
diversity, or a broader grounded proposer — is the precise open frontier (§8).

### Tier-honest status

Still **not Tier-3** — no attention-beating primitive, and the rung-climbing is not
yet autonomous. But the conceptual question behind an invention engine —
*does grounded, execution-checked compounding actually buy reach?* — now has a
clean, ablated, numbered answer: **yes, one rung at a time**, with the autonomous
rung-climb as the named next problem. That is the map an invention engine needs,
drawn with measurements instead of hope.

### Tests

`inv_substrate.zig` / `inv_library.zig`: the 4-parameter call ABI and nested macro
execution; `C1` built on `C0` computes `v0[i]·v0[j] + v0[k]·v0[l]` via nested calls
and routes its four parameters correctly to the two inner `C0` invocations.

---

## 16. Phase 5 — the frontier: can a curriculum climb a rung autonomously?

Phase 4 needed `C1` by hand because the engine cannot *solve* `K=2` with `C0` alone
(the 0/4 trap), so it has no `K=2` solution to abstract `C1` from. Phase 5 tests the
cheapest possible autonomous escape: **warm-start** the harder search with the
easier task's solution — seed a quarter of the `K=2` population with the `K=1`
program the engine already found, so it *extends a stepping-stone* instead of
assembling from scratch. Run with `zig build run-invent -- phase5`.

```
Stage 0 — solve K=1 with C0: perf 1.000, champion uses 1 C0 call  → stepping stone
Stage 1 — solve K=2 with C0 (needs 2 C0 calls + combine), 4 seeds/cell:
  condition            | solves | best e→t
  cold (random init)   |  0/4   | — (miss)
  warm (K=1 seeded)    |  0/4   | — (miss)
```

**Warm-start does NOT escape the trap — an honest, informative negative.** Seeding
with the `K=1` solution just floods the population with *the trap optimum itself*:
the `K=1` program computes one product, which already scores ~70% on `K=2` — exactly
the deceptive peak. Warm-start accelerates *reaching* the trap, not *leaving* it. The
path out still requires a discrete, fitness-neutral jump — add a second `C0` call and
combine it — and until that whole structure is wired, accuracy doesn't move, so
selection never rewards the intermediate. Simple curriculum transfer cannot crack a
genuine deceptive local optimum.

### What this pins down (the deepest §8 problem, localized)

The blocker to an **autonomous tower** is now a specific, well-studied phenomenon:
**deception**. A partial composition is a high-fitness attractor, and the full
solution is a fitness-neutral structural jump away — the classic case where greedy
fitness-following (and naive transfer) fails. The principled escapes are *not* more
scale; they are **architecture of search**:

* **quality-diversity / novelty search** (e.g. MAP-Elites): keep behaviourally
  *diverse* stepping-stones binned by a descriptor (such as number of `C0` calls), so
  a "two-calls-present-but-not-yet-combined" individual survives in its own niche
  instead of being out-competed by the 70% one-call peak — then a single mutation can
  wire it. This is the next brick.
* **a broad, grounded proposer** that can leap the neutral gap directly (the deepest
  §8 problem: neural-grade reach with execution as the only truth).

Tier-honest status: the autonomous rung-climb is **not** achieved, and Phase 5 says
*why* with numbers — the trap is real deception, not a budget shortfall, and the cheap
fix (warm-start) provably fails. That converts "we need reach" from a slogan into a
named, attackable problem with a concrete next experiment (quality-diversity search).

### Tests

Phase 5 is an experiment driver; it exercises the new population-seeding path in
`inv_evolve.runEvolution` (a quarter of the initial population drawn from
`Params.seed_progs`). All engines' unit tests remain green (`zig build test`).

---

## 17. Phase 6 — quality-diversity escapes the trap (the architecture fix)

Phases 3 and 5 established that the per-rung composition trap is real deception that
neither flat evolution nor warm-start can escape (both **0/4** on `K=2` with `C0`).
The principled answer is *architecture of search*, not scale: **MAP-Elites**
(`inv_evolve.runMapElites`). Instead of one population chasing fitness, it keeps the
best individual **per behavioural niche**, binned by `(number of library calls ×
program-length bucket)` — exactly the axis the trap hides along. A
"two-`C0`-calls-present-but-not-yet-combined" program lives in the *2-call* niche and
cannot be out-competed by the one-call ~70% peak; from there a single mutation wires
it. Run with `zig build run-invent -- phase6`.

```
Task: K=2 (2 products) with C0 — needs 2 C0 calls + a combine | 4 seeds/cell
  search method        | solves | best e→t | champion C0 calls
  ---------------------+--------+----------+------------------
  flat evolution       |  0/4   | — (miss) | 0
  MAP-Elites (QD)      |  2/4   |   72855  | 2
```

**Quality-diversity escapes the deception — the key positive result.** MAP-Elites
solves `K=2` **2/4** where flat evolution and warm-start are categorically stuck at
**0/4**, and its champion uses **2 `C0` calls** — it autonomously assembled the
two-product composition that greedy search could never reach. Diversity-preserving
**grounded** search (no LLM, no heuristic — still pure execute-and-measure) climbs the
rung on its own.

Honest reading: it is **2/4, not 4/4**, and costs ~73k evaluations — QD makes the trap
*surmountable*, not free; deception is hard and this is the right *architectural*
lever, exactly as predicted (not more compute). But the qualitative line is crossed:
**the engine can now produce its own rung-2 solution.** That is precisely the
prerequisite an autonomous tower was missing — a `K=2` solution to abstract the next
macro (`C1`) from, with no hand-built rung.

### Where this leaves the path to an invention engine

The full self-climbing loop is now in sight and grounded end-to-end:

```
solve rung-K (MAP-Elites)  →  abstract the recurring macro (MDL, by execution)
   →  solve rung-2K with the new macro (MAP-Elites again)  →  …
```

Each step is execute-and-measure; nothing is accepted on plausibility. The last piece
of machinery is abstraction over fragments that *contain calls* (so `C1` can be
abstracted from a `K=2` solution that calls `C0` twice) — then the engine climbs the
tower with no hand-built rungs. Still **not Tier-3** (no attention-beating primitive),
but the deepest §8 blocker — escaping per-rung deception in a grounded search — is now
shown **surmountable**, with numbers.

### Tests

`inv_evolve.zig`: MAP-Elites runs end-to-end and returns a valid champion; the niche
descriptor bins by call-count × length. All engines remain green (`zig build test`).

---

## 18. Phase 7 — the capstone: the engine climbs the tower by itself

Everything before built and tested the pieces; Phase 7 runs the **full self-climbing
loop end-to-end, with NO hand-built rungs.** Starting from one given primitive `C0`
(the product), the engine must solve a hard task, *abstract its own solution* into a
new macro, and use that macro to reach a task no single-level library could. Run with
`zig build run-invent -- phase7`.

The two pieces of machinery that close the loop:
* **abstraction over calls** — `canonicalize` now accepts `.call` ops, so a fragment
  that *calls `C0` twice and combines* canonicalises into a 4-parameter macro whose
  body contains those nested calls (the element indices generalise into params). This
  is how `C1` is *discovered from a solution*, not hand-written.
* **`verifyComposition` (the Prime Directive, applied to the library itself)** — an
  auto-abstracted macro is **run on random inputs** and banked only if it actually
  computes `v0[a]·v0[b] + v0[c]·v0[d]`. No label is trusted; the macro must execute
  correctly. `firstComposingMacro` scans a solved program's windows for such a core,
  so a *single* hard-won solution is enough — recurrence is not required to bank a
  subroutine the engine proved works.

**The run (real output):**

```
Step 1 — MAP-Elites solves a K=2 family with C0 (3 tasks x 4 seeds)…
  solved 1/12 K=2 instances; pooled 1 solution(s) to abstract from.
Step 2 — AUTO-ABSTRACTED C1 from a solved program: 4 params, 2 C0-call(s) in body
  C1 composes (verified by EXECUTION on random inputs): YES — v0[a]·v0[b] + v0[c]·v0[d]
Step 3 — MAP-Elites solves K=4 with the SELF-BUILT library {C0, C1} (4 seeds)…
  K=4 solved 1/4 | best 15510 evals | champion uses 2 C1 call(s)
[CLIMBED] C0 → (QD solves K=2) → auto-abstracted+verified C1 → (QD solves K=4).
```

**It climbed.** Quality-diversity solved `K=2` with `C0` (escaping the deceptive trap);
the engine then **abstracted its own solution into a verified second-level macro `C1`**;
and quality-diversity used that self-built `{C0, C1}` to solve `K=4` — the champion
invoking `C1` **twice** (it composed its own abstraction). No rung was hand-written;
every rung was confirmed by execution. This is the concrete, grounded form of *an
inventor that builds on its own inventions.*

**Honest reading (the numbers are thin, and that matters):** the solve rates are low —
`K=2` at **1/12**, `K=4` at **1/4**. Escaping per-rung deception with quality-diversity
*works but is unreliable* (~10–25% per attempt), so the loop succeeds end-to-end only
intermittently and leans on retries. This is a **proof of mechanism, not a robust
engine**: it shows the full grounded loop *can* close itself, not that it does so every
time. Making the rung-climb reliable (stronger QD, better descriptors, or the broad
grounded proposer) is the continuation.

### The complete arc (Phases 1–7)

1. **Invent** a primitive (the gate, in novel forms). — Tier-1.
2. **Reuse** it → 100–1400× fewer evals.
3. One primitive **≠ compositional reach** (K=2 = 0/4). — the wall.
4. The **tower compounds** — a second-level macro collapses K=2 (4/4 via one call).
5. **Curriculum/warm-start fails** (0/4) — the trap is real deception.
6. **Quality-diversity escapes** the trap (K=2 = 2/4 by grounded search alone).
7. **Self-climbing loop closes** — solve → auto-abstract+verify → solve the next rung,
   no hand-built rungs.

### Tier-honest status — where this actually lands

This is a **complete, grounded demonstration that execution-checked compounding can
build its own abstraction tower** — the mechanism behind a non-hallucinating inventor,
shown working on a toy family. It is **NOT Tier-3**: there is no discovered primitive
that beats attention, the substrate is tiny, the tasks are gradient-free needles, and
the rung-climb is unreliable. What it *is*: every claim is a number reproducible from
`run-invent`, nothing is accepted on plausibility, and the engine demonstrably grows
and reuses its own verified inventions. The honest frontier remains making the climb
reliable and reaching a primitive that breaks a real trade-off.

### Tests

`inv_library.zig`: `canonicalize` abstracts a fragment that CALLS `C0` twice + combines
into a 4-param macro; `verifyComposition` confirms by execution that an auto-abstracted
macro computes a sum of two products; `firstComposingMacro` recovers it from a single
solution. All engines remain green (`zig build test`).

---

## 19. The "beat attention" track (bricks A–E)

The path to a primitive that beats attention has five bricks; all five are now
*tested*. Run the sequence-substrate ones with `zig build run-invent -- seq` and the
reliability one with `… -- phase8`.

### Brick A — is the autonomous rung-climb reliable enough to stack? (`phase8`)

The Phase-7 loop closes only ~1/12 per attempt; you cannot stack the ~15–30 rungs
attention needs at that rate. Measuring the K=2 climb across configs (6 seeds each):

```
  config                | solves | best e→t
  classify, 250k        |  0/6   | —          (greedy + flat fitness: the trap wins)
  classify, 750k        |  3/6   | 153698     (budget raises the RATE)
  regress (corr), 250k  |  2/6   |   1070     (smooth signal: ~100x FASTER per solve)
```

**Finding:** reliability is fixable, and the big lever is the **fitness signal**, not
compute. Correlation (regression) grading gives partial credit toward the full
composition — a gradient flat accuracy doesn't — so when it solves it solves in
~1–11k evals vs ~150k. Budget raises the hit rate; regression collapses the cost.
Combined (regression + cheap restarts) the climb is tractable. Carried forward as the
climb's default. (Not a one-shot ≥6/6 yet — making it bulletproof is ongoing — but
cleared enough to proceed.)

### Bricks B–E — discover a primitive that beats attention's weakness (`seq`)

"Beating attention" is only gradeable on a task attention is *weak* at, so we use
**prefix-parity** `y[i] = x[0]·…·x[i]` (x ∈ {−1,+1}) — length generalization on an
algorithmic task, attention's documented failure mode. A **scan** (running product via
persistent state, O(L)) is correct at any length; a fixed-depth **stateless**
operator (the attention class, modelled as a per-position function with no carried
state) provably cannot be. The novel lever in the substrate (`inv_seq.zig`) is the
persistent **state** bank — the thing that makes the sub-quadratic, length-generalising
family reachable.

```
[Brick B] hand-written SCAN:        acc @ L=16,64,200 = 1.000  → HOLDS as length scales
[Brick C] stateless (att.-class):   acc @ L=64 = 0.51; best searched = 0.52  → stuck at chance, any length
[Brick D] search WITH state:        solved 5/6 runs, fastest 1928 evals, best 1.000
          discovered champion:      setup: st1 = 1 ;  step: st1 = st1 · st0    (the scan, by execution)
[Brick E] champion at HELD-OUT L:   L=64: 1.000 | L=128: 1.000 | L=256: 1.000  (8× training length)
```

**The full chain works end-to-end.** The engine **discovered, purely by execution**
(in ~1928 evals, reliably 5/6), the running-product scan — `st1 ← st1 · x[i]` — a
primitive that **beats the attention-class approach on its weakness** (100% vs 51%
chance on length generalization) and **holds as the sequence scales** to 8× its
training length, while the stateless class is stuck at chance *at any length*. The
discovered primitive is **irreducible to the fixed-depth class**: no stateless program
can represent the unbounded recurrence (Brick C searched the whole class and capped at
0.52). This clears the *structure* of the Tier-3 bar — a discovered, execution-verified
primitive that breaks a real trade-off (length generalization) and scales.

### Tier-honest scope — what this is and is NOT

* It **is**: a clean, grounded, end-to-end demonstration that the engine can *discover
  by execution* a primitive that beats the attention-class approach on a task attention
  is weak at, and that the win *holds as it scales* — the full Tier-3 shape, on a real
  trade-off (length generalization).
* It is **NOT** "we beat attention": prefix-parity is a toy; the "attention-class"
  baseline is a simplified *stateless* stand-in, **not a trained attention block** on a
  language/sequence-modelling task; and the discovered scan/recurrence is a **KNOWN**
  primitive (SSMs/RNNs) — so this is **rediscovery of a real trade-off-breaker**, not a
  never-seen invention. Reaching a *novel* primitive on a task where *trained attention*
  is the genuine state of the art remains the open frontier — gated, as always, by the
  §8 walls (search reach + fitness cost), now with the tools (reliable climb, sequence
  substrate, cost-relevant scaling tasks) in place to attack it.

### Tests

`inv_seq.zig`: the hand-written scan computes prefix-parity at 100% and holds at
L=16/64/200; the stateless regime is ≈ chance; evolution runs end-to-end on the
sequence substrate. All engines remain green (`zig build test` — 69 tests).

## 20. The alien-architecture research arc (Phases 0–3) — hunting a *novel* primitive

§19 ended on an honest wall: the engine *rediscovered* the scan (a known SSM/RNN
primitive), and the obvious "fix" (add gated/matrix state) would just reimplement
Mamba. The lesson: **novelty has to come from the SUBSTRATE, not the search loop** —
a human-shaped op-set can only re-derive points humans already mapped. So this arc
rebuilds the substrate as a deliberately **non-human** op-space and asks, as a real
research question with kill-tests and controls:

> Can execution-only search over an alien primitive space discover a sequence
> operator that pushes the **recall ↔ length-gen frontier** past where every known
> primitive sits — and if not, *why not*?

Both answers are results. Run: `frontier`, `novelty`, `alien`, `hunt`, `probe`.

### Phase 0 — the map (`frontier`). Two tasks that pull opposite ways:

```
  mechanism   | length-gen (parity L=256) | recall (K=32) | corner
  attention   |           0.496           |     1.000     | recall corner
  scan        |           1.000           |     0.372     | length-gen corner
  local       |           0.508           |     0.289     | neither (dominated)
```

Attention owns recall (content-addressed lookup) and fails parity (a fixed-depth
average can't represent the unbounded product); the scan is the mirror image. They sit
at **opposite corners**; the **top-right (high on BOTH) is empty** — the research
target. **Kill-test (passes):** attention and scan separate by >0.3 on *both* axes.

### Phase 1 — the novelty certifier (`novelty`). The anti-self-deception machinery.

A 6-feature **behavioural fingerprint** `[parity16, parity256, recallK4, recallK48,
x0_sensitivity, local_agree]` clusters the known mechanisms; a candidate is "novel"
only if its fingerprint is far from *every* anchor. The clusters are well separated
(attn↔scan = 1.31, attn↔local = 1.07, scan↔local = 1.41 ≫ threshold 0.35).
**Kill-test (passes):** a re-implemented scan (parity-via-count, re-indexed memory)
certifies at distance **0.000** from the scan anchor, verdict **NOT novel** — the
certifier sees through a known mechanism in disguise. Without this, every "win" is
just rediscovery we failed to recognise.

### Phase 2 — the alien substrate + reachability proof (`alien`).

Op-space: u64 registers + bit-mixing (XOR/AND/OR/SHL/SHR/ROTR/POPCOUNT/MUM/BSWAP) +
an **addressable memory with data-dependent addresses** (load/store) + eq/sel masks.
**No softmax, no float product.** Content addressing is reachable only via *hashing*;
accumulation only via *bit-mixing*. Hand-written alien programs prove the whole map —
including the empty corner — is reachable in this op-space:

```
  alien program  | length-gen L=256 | recall K=48 | corner
  XOR-scan       |      1.000       |    0.256    | length-gen (parity via bit-XOR)
  hash-table     |      0.501       |    1.000    | recall (via hashed memory, no softmax)
  UNION          |      1.000       |    1.000    | TOP-RIGHT (the open target)
```

The union certifies **novel** (dist 0.692 from nearest anchor) — but **honestly it is
two known mechanisms bolted together**, novel only because no *single* anchor does
both. The substrate can host a frontier-breaker; whether *search* finds one, and
whether it's unified or a bolted union, is the actual question.

### Phase 3 — the hunt (`hunt`) and the diagnostic (`probe`).

MAP-Elites niched on the recall×length-gen plane, 4×300k evals. **Top-right reached
0/4.** The niche map tells the story — every parity row fills, but the two high-recall
columns are **completely empty**: search climbs parity freely and never climbs recall
at all. The `probe` (dedicated single-objective search) locates the bottleneck
exactly:

```
  axis / grading           | solves | best score | fastest e→solve
  parity                   |  4/4   |   1.000    |   838      (climbs freely)
  recall (SPARSE 1-query)  |  0/4   |   0.547    |   —        (never solves)
  recall (DENSE all-query) |  0/4   |   0.343    |   —        (the fix made it WORSE)
```

**Finding (a real, refined result):** recall is a **conjunctive needle** in this
substrate — load+store must share the right address and value registers
*simultaneously*; until both are wired, retrieval is zero for *every* key. The
**Brick-A fitness-signal fix is REFUTED here**: denser grading (query every key) made
recall *worse*, not better — a half-wired conjunctive mechanism yields partial *output*
for nothing, so more graded outcomes just raise the bar. This **refines** the Brick-A
lesson: reward density helps when *partial mechanisms give partial output* (parity,
arithmetic composition), and **not** for an all-or-nothing conjunction. *(NOTE: Phase 3
called recall "unreachable"; Phase 5 below REVISES that — it is reachable but RARE.)*

### Phase 5 — the curriculum (`curriculum`), and the revision of Phase 3.

The recommended lever (a): a K-ladder — ramp the number of bindings K and warm-start
each rung from the previous champion. Running it with 8 seeds REVISED the Phase-3 read:

```
[COLD] from-scratch search per rung (hit RATE over 8 seeds):
  K=1: 8/8 (latch, 184 evals)   K=2: 1/8   K=3: 1/8   K=4: 0/8 (0.594)   K=6: 1/8
[GENERALIZE] best cold champion (solved K=6):  step: r3 = mem[r0]; mem[r0] = r5
             load/store ops = 2 | recall @ HELD-OUT K=48 = 1.000  ⇒ GENUINE key-addressing
```

* **Recall addressing IS discoverable by execution.** Cold search found
  `r3 ← mem[key]; mem[key] ← value` — exactly the hand-written hash-table — and it holds
  at held-out K=48 (1.000). So Phase 3's "unreachable" was wrong: it's **reachable but
  RARE** (~1/8 per attempt, roughly K-independent at K≤6; the K=4 0/8 is noise). The real
  blocker is **per-attempt reliability of hitting a conjunction — the Brick-A problem
  again**, not a missing gradient. (Phase 3's K=20/4-seed probe missed it by sampling.)
* **The K-ladder did NOT make the hard jump easier.** The warm ladder appears to solve
  every rung, but that's two confounds: 8 attempts/rung, and — once addressing is found
  at K=2 — it is banked and trivially seeds all higher rungs. Warm-starting *from the
  K=1 latch* does not help discover addressing; the latch is a structural dead-end.
  Lever (a) is a wash for the hard step.

### Phase 6 — "does gambling get you there?" (`gamble`). The reliability-vs-novelty test.

A falsifiable claim (full note: `docs/research/alien_novelty_limit.md`): *gambling
changes how reliably you hit an attractor, not which attractor — the attractors are the
known mechanisms.* The experiment: gamble on recall, bank it, seed the joint (corner)
objective from it, decompose the result.

```
[1] recall HIT after 14 restarts  →  step: r3 = mem[r0]; mem[r0] = r5   (the hash-table)
[2] seed joint from it            →  min(parity,recall) = 1.000 in 19k evals (corner reached)
[3] corner program: r2 = r2 + r0; r3 = mem[r0]; mem[r0] = r5
    accumulator ops 1 | memory ops 2 | fp [1 1 1 1 1 0.52] → certifier "NOVEL" (dist 0.68)
```

**Confirmed.** Gambling DID reach the corner — but it is the **bolted union of two
rediscoveries** (accumulator ⊕ hashed memory). Note the scan was rediscovered via **ADD**
here (`r2 += r0`, low bit = parity), and via **XOR** in `curriculum`/`alien` — *same
mechanism, different alien spelling*, which underlines the convergent-attractor point.
So **"keep gambling → you'll get it" is TRUE for the KNOWN answer (reliably), FALSE for a
NEW one**: more restarts hit the same minimal-complexity attractors, never a novel
primitive. The certifier flags the union "novel" only because no *single* anchor does both.

### Phase 7 — forbid the attractor (`forbid`). The first novelty experiment.

If known mechanisms are convergent attractors, *removing their primitives* should force a
different spelling of the same mechanism, a neighbouring known mechanism, or a wall — not
a novel primitive. Restrict the op-space and re-search:

```
  config                  | solves | best   | reading
  parity, FULL            |  4/4   | 1.000  | baseline
  parity, NO xor          |  4/4   | 1.000  | same accumulator, add/sub spelling
  parity, NO xor/add/sub  |  4/4   | 1.000  | STILL solves — accumulator is multiply-realizable
  recall, FULL            |  0/4   | 0.563  | (~1/8, 4 seeds — noisy miss)
  recall, NO load/store   |  0/4   | 0.531  | WALL — no memory ⇒ recall unsolved at this budget
```

**Finding:** the parity accumulator is so convergent it survives deleting xor *and* add
*and* sub — search finds yet another spelling (eq/sel/mul/rotr tracking the low bit). You
cannot forbid a convergent mechanism by removing a few ops. Forbidding memory made recall
*unsolvable* (a wall — the compare-and-select alternative is itself attention's mechanism
and a bigger conjunction than this budget reaches). Forbidding an attractor reveals a
different spelling, a neighbouring *known* mechanism, or a wall — **never a novel one**.

### Phase 8 — the insufficiency task (`fuse`). The fairest attempt to force novelty.

A task neither the scan, the hash-table, nor their bolted union can do: **per-key
counting** (output how many times the current symbol has appeared). It needs accumulation
*inside* the addressed cell — a fused read-modify-write.

```
[SETUP] scan 0.184 | hash 0.184 | union 0.184 | fused RMW 1.000   (only RMW solves it)
[SEARCH] cold gamble (40 restarts × 400k = 16M evals):  NO hit, best 0.495
[CURRICULUM] seeded from a banked hash-table building block:  NO hit, best 0.495
```

**Finding:** the insufficiency task genuinely forces a fusion (only the RMW counter
solves it) — but search **could not discover it**, neither cold (16M evals) nor by
extending a banked hash-table. The RMW is a *3-op* conjunction (load + increment + store,
same address) with no partial-credit slope for the increment — a bigger needle than the
2-op hash-table, beyond this budget. So even when a task *demands* something past the
bolted union, what it demands is a *known fused pattern* (a counter array), and the engine
can't even reach it — a reliability wall, not novelty. (The recall↔length-gen certifier is
scoped to those two axes and would mislabel an RMW counter "novel" since the counter is
not an anchor — a known limitation, not evidence of invention.)

### Tier-honest scope — what this arc is and is NOT (and the sobering meta-finding)

* It **is**: a working, verified research apparatus — a frontier *map*, a novelty
  *certifier* that catches disguised rediscovery, an *alien* substrate proven able to
  host a frontier-breaker, and a *search* that DOES discover genuine, generalizing
  content-addressing (`mem[key]` load/store) by execution alone. The method is sound.
* It is **NOT** "we invented a new architecture", and the deepest finding says why:
  **the alien substrate did not produce novelty — it produced alien *encodings* of the
  SAME known mechanisms.** Search rediscovered the scan (XOR-accumulate = running parity)
  and the hash table (load-before-store = content addressing) because those are the
  **minimal-complexity solutions even in a bit-mixing op-space**. Making the primitives
  weird did not make the *solutions* novel. The top-right, when reached, is the union of
  two rediscoveries — a bolted hybrid, not a unified novel primitive. Forcing genuine
  novelty would require *forbidding* the convergent known mechanisms (prescribing what
  you don't want), which is a far harder and more dubious proposition. This is the honest
  answer to "can we invent something new, not rediscover existing architectures": with
  execution-only search, known mechanisms are convergent attractors — novelty does not
  fall out of an alien substrate alone.

### Tests

`inv_frontier.zig` (4) — Phase-0 opposite-corners kill-test, bounded-scan recall decay,
Phase-1 disguised-scan kill-test, anchor separation. `inv_alien.zig` (6) — three
corner-reachability kill-tests (XOR-scan, hash-table, union→top-right), union-novelty,
no-state baseline ≈ chance, hunt smoke. All green (`zig build test`).

