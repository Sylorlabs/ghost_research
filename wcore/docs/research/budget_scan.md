# Budget scan: can the engine invent, or only recombine deeper?

**Status:** built, measured — an uncharted-knob experiment with an answer not known
in advance. Reproduce: `cd wcore && zig build -Doptimize=ReleaseFast &&
./zig-out/bin/wcore-invent budgetscan <seed> [dmax]`. Optional third arg sets
exhaustive reduction depth (default 8). New phase `budgetScan` in
`src/inv_main.zig`.

## The genuinely open question

The breadth test (`claim_c_breadth.md`) reduced each discovered solver to a
known-atom composition only up to **depth 4**, and one seed (0xD00D) left a single
solver flagged "irreducible". I called it *probably* a budget artifact — but I did
not know. The honest "can it invent?" test is to crank the **exhaustive** reduction
budget up and watch: does any solver *survive* deeper reduction (a candidate
genuine atom), or does everything collapse to a composition (Claim C robust, the
depth-4 flag a mere artifact)? `reducible()` enumerates *every* composition of the
atoms up to the budget, so "irreducible at DMAX" is a hard claim.

## Results (DMAX = 8)

Seed 0xD00D — the one with a depth-4 "survivor":

```
  min reduction depth | #solvers
  --------------------+---------
         2            |   3
         3            |   3
         4            |   2
         5            |   1     <- the depth-4 "irreducible" — it reduces at depth 5
  [RESULT] 9 deep solvers; 9 reduced within depth 8; 0 survive.
```

Across seeds 0xD00D, 0xBEEF, 0x1111, 0xFACE: **0 survivors at DMAX=8 in every
case.** The instrument stays non-vacuous throughout — the hand-built true outsider
`distinct-count` remains irreducible at depth 8 in the sanity check.

## What this answers

- **The 0xD00D anomaly was a budget artifact.** It is a depth-5 composition; the
  depth-4 search simply hadn't looked deep enough. Not a new atom.
- **Can it invent? No — it recombines deeper.** Every solver the open-ended search
  produced, including the most suspicious one, is an exact composition of the
  existing atoms once the reduction budget is allowed to grow. Pushing the engine
  into this uncharted regime surfaced no genuine atom.
- **"Irreducible" is exactly as deep as your reduction search.** Novelty flags move
  with the budget: depth 4 said "1 irreducible," depth 5 said "0." You can never
  certify a new atom, only fail to reduce within a budget — closure all the way up,
  now demonstrated by *scaling the budget*, not just asserting it.

## Honest status

This is a **negative result to a genuinely open question** — the good kind of
research even though the answer is "no." The knob (reduction depth) was unexplored,
the outcome was fixed by exhaustive computation rather than by my construction, and
it dissolved an anomaly from my own earlier run. It strengthens Claim C from
"holds at depth 4" to "holds under budget-scaling, and the lone exception was an
artifact." The standing frontier is unchanged and now sharper: a *new atom* would
have to survive an unbounded reduction budget — which on a fixed opcode VM it
provably cannot, because every behaviour is some composition of the opcodes. Real
invention needs the atom set itself to be open, where the question recurs one level
up.
