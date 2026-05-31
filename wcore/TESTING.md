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

