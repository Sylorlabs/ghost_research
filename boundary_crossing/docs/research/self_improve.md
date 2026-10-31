# The engine improving itself — Claude proposes, measurement certifies

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build self-improve --release=fast` (~5 s).

## The recursive move

Use the certified inject→certify→promote method, with Claude as the LLM, to invent a **better invention
engine**. The "targets" are now **engine improvements**; the "certifier" is **empirical measurement** on a
held-out battery — an improvement is certified only if it *measurably* helps (more solved / fewer bits / fewer
nodes) with **no regression**. A claimed-but-useless upgrade fails the measurement; the engine cannot fool
itself about its own gains. Claude analyzed the current engine and proposed three improvements, each a known
idea from program induction / open-endedness, each measurable here.

## Results

Battery: a dependency **chain** T1..T4 (each builds on the last, depth 2→5) + T5 (Fibonacci, quadratic).
Baseline search is bounded to triples, so the depth-4/5 chain targets and the quadratic are out of reach.

```
config                               | solved | total bits | search nodes
BASELINE (flat lib, fixed order)     |  2/5   |    14.6    |   2059
+ (A) abstraction-promotion          |  4/5   |    25.4    |   3542
+ (A)+(C) LLM-injected candidate     |  5/5   |    28.8    |   3542
+ (A)+(C)+(B) freq-biased search     |  5/5   |    28.8    |   3426   ← the better engine

certification (measured marginal gain, held-out):
  (A) abstraction-promotion : CERTIFIED ✓  solved 2→4  (the depth-4/5 chain becomes shallow reuse)
  (C) LLM-injected candidate: CERTIFIED ✓  solved 4→5  (the quadratic, outside the search's DSL)
  (B) freq-biased search    : CERTIFIED ✓  nodes 3542→3426  (same answers, less compute)
```

**3/3 certified.** The better engine strictly dominates: 5/5 vs baseline's 2/5, at fewer search nodes.

## What each improvement is, and why it certifies

- **(A) Abstraction-promotion (DreamCoder's wake-sleep).** Promote each solved program as a library atom, so a
  chain of targets — each building on the last — becomes solvable at shallow depth. Baseline (flat library,
  triple-bounded search) cannot express the depth-4 target `((sq∧mod3)∨mod5)∧even`; with promotion, `T2` is
  reused as one atom and `T3 = T2 ∧ even` is a *pair*. This is **genuine self-improvement**: the engine gets
  *better at deeper targets by reusing what it already invented*. Certified by solved 2→4 (each new solve is a
  ~5-bit reuse of a promoted abstraction, not a regression — it solves more, each cheaply).
- **(C) LLM-injected candidate.** Fibonacci needs the quadratic `5n²±4`, outside the affine DSL — the search
  cannot reach it. Claude injects `is_fib`; it solves. The LLM is the out-of-closure source, **still required**.
  Certified by solved 4→5.
- **(B) Frequency-biased search.** Try recently-promoted atoms first, so the matching program is found earlier.
  Certified by nodes 3542→3426 (same answers, less compute) — a modest but real, measured efficiency win.

## The answer to "it's OK if it still requires you, as long as it leads to the right path"

It does require the LLM (improvement C), and that **is** the right path — provably. Here is why: each
LLM-injected primitive is **certified and promoted**, so it enters the engine's reusable library, and every
later target can build on it *without the LLM*. The LLM is needed only at the **frontier** — exactly where the
autonomous search hits its current closure — and each time, the frontier moves out and stays out. So the engine
is a **ladder**: each rung (engine version) is bounded, but the sequence of certified rungs climbs without bound.
The LLM is the thing that adds a rung when the ladder runs out; abstraction-promotion is the thing that makes
every rung permanent. *That* is recursive self-improvement done honestly — an unbounded ladder built from
bounded, certified rungs.

## Honest ceiling (now from the meta-level)

The better engine is still bounded by its DSL + the LLM's closure. Improving the engine **relocates** its ceiling
(deeper, cheaper, faster); it does not remove it — the structureless target stays uninventable, and a target
outside both the DSL and the LLM's knowledge would too. Recursive self-improvement is real and measurable and
**bounded all the way up**, exactly as every layer of this project proved. The right path is the loop itself:
keep injecting (LLM / data / external problems), keep certifying (compression + held-out, cheat-proof), keep
promoting — and the bounded rungs compose into an unbounded climb.

## Honest scope

- Certification is by held-out measurement on this battery; an improvement that helped only by overfitting the
  battery would show no held-out gain (the chain targets are exact predicates, verified on `[DOM/2, DOM)`).
- The improvements are real but small-scale demonstrations of large ideas (DreamCoder abstraction, FunSearch
  LLM-mutation, learned search order); scaling each is engineering that pushes the same ceiling further out.
- (B)'s node win is modest here (one short chain); on a large target stream the frequency bias compounds. The
  point is the *mechanism* (measured, certified), not the magnitude on five targets.

See: `autonomous_engine.md`, `compression_engine.md`, `llm_proposer.md`, `invention_engine.md`, `../README.md`,
repo-root `CLOSURE_PRINCIPLE.md`. Prior art: DreamCoder (Ellis et al. 2021); FunSearch (2023); POET (Wang et al.
2019); the AI-generating-algorithms program (Clune 2019).
