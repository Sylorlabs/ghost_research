# Build Plan: A Specialized Invention Engine (for a fresh agent)

> **You are being handed a focused mission. Read this whole document before writing
> any code. It encodes not just *what* to build but *how to think* — because the
> default gravity of this problem pulls every engineer back to known methods that
> cannot possibly produce the result. Resisting that pull is the job.**

---

## 0. The mission, in one sentence

Build a machine whose only purpose is to **invent new computational primitives** —
candidates so low-level that genuinely novel ones (e.g. a primitive that beats
attention) are reachable — where **every candidate is judged by being executed
and measured against ground truth, never by plausibility.** Output format is
irrelevant; it can emit alien programs/graphs as long as the invention is
extractable and re-runnable.

The end goal is **Tier-3 invention** (a new primitive that breaks a real
trade-off), *not* Tier-1 (tuning) or Tier-2 (recombining known parts).

---

## 1. THE PRIME DIRECTIVE (the one thing you never relax)

**Truth comes from execution, not from a learned distribution.**

A system hallucinates when its source of truth is "this looks plausible" (that is
what an LLM is). A system *cannot* hallucinate when its source of truth is a
**verifier that runs the candidate and measures it against reality.** That single
property is the entire reason this engine is worth building and the only axis on
which it beats an LLM. So:

- Every candidate primitive is **run on real data and scored by real performance.**
- Nothing is ever accepted because it "seems like a good architecture."
- You may burn every architectural dogma (transformers, attention, even backprop).
  You may **not** burn execution-as-truth. That is not a chain — it is the anchor.

If you ever find yourself scoring a candidate without running it, stop. You have
reintroduced hallucination.

---

## 2. HOW TO THINK

1. **Reproduce, then transcend.** First make the engine rediscover a *known* good
   primitive from raw parts (proves the engine works). Only then hunt for novel
   ones. Do not skip the reproduction — without it you can't tell invention from
   bugs.
2. **Simplicity is the steering wheel.** Prefer the shortest program that hits the
   performance bar (Minimum Description Length). This is what makes discovered
   primitives *general* instead of overfit spaghetti. Performance says "it works";
   MDL says "it works because of real structure, not memorization."
3. **The ratchet is the bet.** Human invention compounds: dot-product → softmax →
   attention → transformer. The novel lever here is a **library of discovered
   primitives that become reusable building blocks**, so search builds upward
   instead of restarting. Everything hinges on whether reuse *accelerates*
   discovery. Test that ruthlessly and early.
4. **Negative results are wins.** "The boring method already does this" or "the
   ratchet gives no speedup" are valuable, publishable facts that save months. Say
   them plainly. Do not dress a Tier-1 result as Tier-3.
5. **Expect to hit the compute wall.** Evaluating fitness means training each
   candidate; that is expensive. When you hit it, that is not failure — it is the
   Tier-3 problem statement (see §8). Name it precisely when you reach it.
6. **Brick before cathedral.** Each phase has a kill-test. Do not build the next
   phase until the current brick holds weight.

---

## 3. FORBIDDEN MOVES (anti-regression — re-read every session)

These are the regressions the problem will tempt you into. Each is banned, with
the reason. If you feel one is necessary, you have misunderstood the mission.

1. **No LLM (or any pretrained model) in the proposal loop.** The proposer is
   search + the discovered library. *Why: an LLM proposer reintroduces the exact
   hallucination this engine exists to beat. The whole point is a generator whose
   outputs are grounded, not plausible.*
2. **No searching over a menu of known high-level layers** (`{attention, conv,
   MLP, LSTM, ...}`). The search space is **primitive math operations only**.
   *Why: choosing among known layers is Neural Architecture Search — it can only
   recombine, never invent a new primitive. It pre-bans the answer.*
3. **No scoring by heuristic/proxy-plausibility in place of execution.** Fitness is
   always run-and-measure on data. *Why: see the Prime Directive.* (A cheap fitness
   *proxy* is allowed only later, as an explicit Tier-3 research target in §8, and
   only validated against true execution.)
4. **Do not import an AutoML/NAS framework and call its `evolve()`/`search()`.**
   You may use a tensor/array library for the *executor* (matmul etc.). The
   **search, the MDL selection, and the compounding library must be yours** —
   that is the contribution. *Why: outsourcing the engine to a known framework is
   Tier-1 by definition.*
5. **No declaring victory on rediscovery alone.** Rediscovering a known primitive
   proves the engine works (good), but it is not the result. The results are:
   (a) the library measurably *accelerating* discovery, and (b) a discovered
   primitive *beating a baseline at matched budget*. *Why: rediscovery is
   AutoML-Zero (2020); the prize is beyond it.*
6. **No scaling before the kill-tests pass.** *Why: scaling a broken engine just
   burns compute confirming it's broken.*
7. **No "it basically works" without the number.** Report exact fitness, exact
   evals-to-target, exact program. *Why: this engine's entire value is grounded
   measurement; ungrounded claims betray it.*

---

## 4. THE ARCHITECTURE

### 4.1 Substrate (the search space)
Primitive operations over a small typed memory of variables (scalars, vectors,
matrices). A minimal viable set:
- arithmetic: `add, sub, mul, div`
- linear algebra: `matmul, transpose, outer, dot, broadcast`
- elementwise nonlinearities: `relu, tanh, exp, abs, recip, max, min`
- reductions: `sum, mean, argmax`
- memory: `read(var_i)`, `write(var_i, val)` over a fixed bank of typed slots
- (later) a bounded `loop`/`scan`

A *transformer* is one program over this set. A *transformer-killer* is a program
over this set that you don't have a name for yet. If your substrate is layers, the
killer is unreachable; if it's primitives, it's in the space.

### 4.2 Candidate = a 3-part program (no autodiff dependency)
Following the AutoML-Zero shape (so you invent the *learning rule too*, and avoid
needing to build autodiff):
- `Setup()` — initialize the memory/params.
- `Predict(x) -> y_hat` — compute a prediction from input using current memory.
- `Learn(x, y)` — mutate the memory (params) given one labeled example.

This lets the engine invent architectures **and** optimizers — strictly more
inventive than fixing backprop. (You may *also* offer a version where `Learn` is a
fixed gradient step and only `Predict` is searched — keep both as switchable
regimes; the harder, more interesting one is searching `Learn` too.)

### 4.3 Fitness (the verifier — the heart)
For a candidate program and a task:
1. `Setup()`.
2. For N training examples: `Predict`, accumulate loss, `Learn`.
3. Measure accuracy/loss on **held-out** examples.
4. Average over several random seeds **and** several tasks from a family (so it
   rewards *general* primitives, not ones overfit to one instance).
   This averaged held-out score is fitness. **It is produced only by running the
   program.** Guard against NaN/inf/timeout (assign worst fitness).

### 4.4 Selection (MDL)
`adjusted = performance − λ · program_length`. λ small but nonzero. Ties broken
toward shorter programs. This is the simplicity prior; it is non-negotiable
because it is what turns "passes the test" into "captures real structure."

### 4.5 The compounding library (THE NOVEL LEVER)
Periodically, scan the current elite programs for a recurring sub-fragment whose
abstraction into a single named macro-op **most reduces the total description
length** of the elite set (exactly the MDL common-subexpression extraction that
`wcore/src/sk_compress.zig` and `sk_learn.zig` already implement for combinators —
use them as the reference algorithm). Add that macro-op to the primitive set so
future candidates can call it as one op. This is the ratchet: discovered structure
becomes a building block for the next discovery. **This is the part nobody has
pushed on, and the reason this might exceed AutoML-Zero.**

### 4.6 Search
Regularized evolution (proven for this regime): maintain a population; tournament-
select; mutate (insert/delete/modify an op, swap an argument, or **call a library
op**); replace oldest. No gradients on the program structure; the only gradients
that exist are whatever the candidate's own `Learn` invents. The steering comes
from fitness + MDL + the growing library — **not** from a learned proposer.

---

## 5. PHASES AND KILL-TESTS

Run strictly in order. Each phase ends with a go/no-go.

**Phase 0 — substrate + executor + one task + fitness harness.**
- Implement the ops, the 3-part program representation, the executor, and the
  fitness function on Task A (§6).
- *Sanity gate:* hand-write a known-good program (a 1-feature-cross perceptron with
  a gradient-style `Learn`) and confirm fitness scores it high and garbage low.
  **If a correct hand-written program doesn't score high, the verifier is broken —
  fix it before anything else.** (Tier: scaffolding.)

**Phase 1 — flat regularized evolution.**
- Evolve programs on Task A. Baselines: random search, and flat evolution.
- *Kill-test:* evolution must reach the target fitness **markedly faster than
  random search** and rediscover the needed primitive (e.g. a multiply-gate +
  a working learn rule). **If evolution ≈ random, the substrate/fitness/mutation
  is broken — fix before Phase 2.** (Tier: reproduction; expect ~AutoML-Zero.)

**Phase 2 — add the compounding library (the core hypothesis).**
- Run on a *family* of related tasks (§6, Task B) so there is shared structure to
  abstract.
- *Kill-test (the whole bet):* evolution **+ library** reaches target across the
  family in **significantly fewer candidate evaluations** than flat evolution.
  Measure evals-to-target for: random vs flat vs library. **If the library gives
  no acceleration, that is the wall — report it precisely; the project pivots to
  §8.** (Tier: if it works, this is the Reasoned-Speculation contribution.)

**Phase 3 — hunt a transformer-killer at toy scale (only if Phase 2 passes).**
- Harder task family where attention is the known-good primitive (§6, Task C).
- Include a small fixed **baseline** (a tiny attention block / MLP) at a matched
  parameter+compute budget.
- *Target:* a *discovered* primitive that **matches or beats the baseline at
  matched budget**, found purely by execute-and-measure, then shown to **hold as
  you scale** task size. That, decoded and shown irreducible to known layers, is
  the Tier-3 result. (Tier: this is the prize; expect to hit §8 first.)

---

## 6. CONCRETE TASKS (escalating)

- **Task A (Phases 0–1):** learn `y = sign(x1 · x2)` from 2-D inputs (an XOR-like
  product). A linear model provably fails; success *requires* discovering a
  multiplicative/gating op + a learning rule. Cheap to evaluate.
- **Task B (Phase 2):** a *family* of functions that all share a gating motif
  (e.g. `sign(x_i · x_j)` for several index pairs, plus a few `relu`-of-product
  variants). The library should abstract the shared gate and reuse it — that reuse
  is what you measure.
- **Task C (Phase 3):** a tiny sequence task attention is supposed to be good at —
  **associative recall** or **copy** on length-8–16 sequences over a small
  alphabet. Baseline = a minimal attention block. Hunt for a primitive that wins at
  matched budget.

Keep everything tiny on purpose: fitness must be cheap enough to evaluate
millions of candidates. Speed of the executor is a first-class concern.

---

## 7. STACK & ENGINEERING

- **Use a compiled language for the executor** (Zig recommended — it matches the
  `wcore` codebase and is fast; C/Rust fine). **Avoid Python as the hot loop** —
  you will run millions of candidate evaluations; interpreter overhead kills you.
- Tiny tensors (≤ a few hundred elements). You do **not** need a GPU or a DL
  framework. A few hundred lines of array math is enough.
- **Determinism + logging (wcore discipline):** seed everything; log per
  generation the best fitness, program length, library size, evals-to-target, the
  exact best program, and — for any discovered primitive — its *decoded behavior*
  (what function it computes, found by probing it). Every run reconstructable from
  its log.
- Parallelize fitness evaluation (it's embarrassingly parallel).

---

## 8. WHEN YOU HIT THE WALL (the real Tier-3 targets)

Two walls are expected; reaching either *clearly* is itself a result:

1. **Fitness is too expensive** (training every candidate dominates). The Tier-3
   prize here is a **cheap fitness proxy**: predict whether a primitive will
   learn/generalize/scale *without* full training, validated against true
   execution. (Current zero-cost NAS proxies are weak — beating them is real.)
2. **Search can't reach novel territory** even with the library. The Tier-3 prize
   here is a **grounded proposer** that is broad like a neural proposer but cannot
   hallucinate (its proposals are constrained to be executable and are still
   filtered by execution). This is the deepest open problem; treat any idea here
   as High-Risk Conjecture — stress-test for hidden dependence on a verifier or a
   human-shaped curriculum before believing it.

Do not pre-build for these. Reach them empirically first, then attack the one you
actually hit.

---

## 9. WHAT COUNTS AS SUCCESS (tier-honest)

- Phase 0–1 working: **Tier 1.** Necessary, not the prize. Don't oversell.
- Phase 2 library acceleration, measured cleanly vs ablations: **the real
  contribution** (Reasoned Speculation confirmed).
- Phase 3: a discovered primitive that **beats a matched-budget baseline on a task
  attention is good at, and holds as it scales, and is shown irreducible to a
  relabeled stack of known layers**: **Tier 3.** This is the finish line. It is
  very hard and most likely gated by §8 — say so honestly if so.

The deliverable at any stopping point is the same shape: the **best discovered
program, extractable and re-runnable, with its measured score and its decoded
behavior** — true because it was *checked*, not because it sounded right.

---

## 10. REFERENCE: the `wcore` codebase you're extending

`wcore` already implements the *skeleton* of this engine for a toy symbolic
substrate — study it, then swap the substrate for tensor primitives and the
verifier for empirical fitness:
- `src/sk_compress.zig`, `src/sk_learn.zig` — **MDL compounding-library
  extraction** (§4.5). This is your reference for the ratchet.
- `src/law.zig` — induce the minimal rule that fits data (MDL + verification).
- `src/nodecount.zig` — the description-length metric.
- `TESTING.md` §8–12 — the honest, ablation-driven, negative-result-friendly
  reporting style. Match it.

The honest through-line: **wcore's method (search + MDL + execute-to-verify +
compounding library) is the right skeleton for a non-hallucinating inventor. Its
domain was a toy. Your job is to give it a real body: tensor-program primitives
and empirical fitness — and find out, with momentum and kill-tests, where it
breaks.**
