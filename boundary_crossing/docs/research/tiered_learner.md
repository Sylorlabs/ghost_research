# Tiered learner — learns as it goes, with ghost_engine's memory + data tiers (no LLM)

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build tiered-learner --release=fast` (~10 s).

## The ask (Micah)

Build the learned-guide demonstration (verification_learning.md), **and steal the memory + data tiers I
engineered for ghost_engine** so the model isn't frozen — it **learns as it goes** and **categorizes data into
different categories**.

## What was stolen from ghost_engine (the real mechanisms, read from the code)

From `src/abstractions.zig` and `src/triad.zig`:

- **`Category`** `{structural, procedural, relational, boundary, state, invariant}` → here, data is categorized
  into `{ramp, record(width), sparse, noisy}` by **cheap features** (modal fraction, delta-1 entropy gain, best
  stride+delta entropy). That's "categorizes data into categories," feature-based, no gzip.
- **Rune rank ladder** (`triad.zig`) `NOISE→EMERGING→PATTERN→VALIDATED→VERIFIED`, promoted by **occurrences +
  distinct contexts**, **TTL-pruned** → here, each memorized primitive has a rank, promoted by reuse, and NOISE
  unused for TTL turns is pruned (`DecayState: prunable`).
- **Reinforcement** `{success/failure}→reinforce_promote/demote` → each use of a primitive reinforces it
  (occurrences++, distinct++), and `maybePromote` walks it up the ladder. Online, not frozen.

## Wired to the verification-learning thesis

The **verifier** (real gzip + exact round-trip) hands out **perfect labels** for free. The **tiered/categorized
memory is the learned guide** (AlphaZero/DreamCoder-shaped): for a new item, categorize it, then try the memory's
primitives for that category **highest-rank-first**; the verifier certifies; reinforce. No LLM, no frozen table —
the guide is built entirely from certified outcomes, online.

## Result — measured head-to-head (tiered memory vs blind-every-time)

```
turn  category     solved-by     evals (tiered / blind)
  0   ramp         blind-search    152 / 152      ← first sighting of each category: full search
  1   record w=8   blind-search    152 / 152
  …
  5   ramp         NOISE (memory)    1 / 152      ← seen before → solved from memory in ONE eval
  11  record w=8   EMERGING          1 / 152      ← promoted up the ladder by reuse
  …
TOTAL verifier evaluations:  TIERED 1379   vs   BLIND 3040   →  55% FEWER
11 of 20 items solved straight from memory.

final tiered/categorized memory:
   [EMERGING] ramp     w=0   occ=5 distinct=5   d1
   [EMERGING] record   w=8   occ=7 distinct=7   s16>d1
   [NOISE   ] record   w=16  occ=2 distinct=2   s8>d2
   [NOISE   ] record   w=4   occ=1 distinct=1   s4>d2
```

The drop from 152 → 1 evaluations on familiar categories **is** "learns as it goes," and it beats re-searching
every time by 55% (a gap that widens with a longer stream). The ramp and record-8 primitives **earned their way
up to EMERGING** by repeated certified reuse — exactly the ghost_engine ladder, populated by real outcomes.

## Honest notes

- It **generalizes within a category** (the `d1` ramp filter works on every new ramp), and **refuses to
  false-learn**: noisy and sparse items never produce a reusable memory hit (no filter beats the 5% threshold),
  so nothing structureless gets memorized — the same honesty as the math probes declining a structureless target.
- The "guide" here is the tiered memory itself (a non-parametric learned policy). A parametric guide (a small net
  predicting which primitive/branch is promising from data features) is the natural next step — same loop, same
  perfect labels; it would help *across* categories and on unseen ones, where the memory is empty.
- This is the AlphaZero/DreamCoder loop with ghost_engine's tiers: **learning from a verifier's perfect labels,
  online, not frozen** — the concrete demonstration of the verification-learning thesis.

See: `verification_learning.md`, `self_extending_inventor.md`, `autonomous_inventor.md`, `../README.md`.
