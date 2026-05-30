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
