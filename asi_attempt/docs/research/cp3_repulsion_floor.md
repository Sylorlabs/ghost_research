# Research note: CP3 — does removing the repulsion floor improve CONTROL?

**Status:** built, measured, **hypothesis falsified — the opposite is true.**
Reproduce with `zig build eval` (means over 6 seeds × 15,000 steps; the new
`[CP3]` block at the end). The baseline table above it is byte-identical to the
pre-CP3 harness, so nothing else moved.

## The question

`expressiveness_ceiling.md` proved that the `0.25 repulsion forcefield` in
`connectome.attractVectorsPtr` floors forward-model prediction error at ~0.24,
and that pure attraction (no floor) collapses it to ~0.04 in isolation — a 5.4×
win. That probe measured *prediction*. The open question (CP3) was whether the
prediction win **converts to control**: does a sharper world-model lower the
failure rate of the full `mb_safety` controller?

A new `pure_attraction` flag on `agent.Config` swaps the rule-learning update
(`agent.zig`) to `connectome.attractVectorsPtrPure` — the attraction branch with
the `dist < 0.25` repulsion removed. Everything else is held fixed. We compare
stock vs pure at the greedy (eps=0, the headline competence) and exploratory
(eps=0.02, 0.10) operating points.

## Results

```
  policy            |   fail/1k | mean_mass |  err_e |  err_l
  ------------------+-----------+-----------+--------+-------
  stock  eps=0.00   |      2.97 |     3.339 |  0.271 |  0.255
  pure   eps=0.00   |     10.99 |     2.617 |  0.099 |  0.052   <- 5x better prediction
  stock  eps=0.02   |     21.17 |    13.904 |  0.278 |  0.303
  pure   eps=0.02   |     37.84 |     8.080 |  0.163 |  0.118
  stock  eps=0.10   |     27.30 |    15.374 |  0.290 |  0.327
  pure   eps=0.10   |     34.40 |    12.343 |  0.160 |  0.245
```
(fail/1k lower is better; err_l = late-window prediction error, lower is better)

## What actually happened — prediction and control are decoupled

**The prediction win reproduces inside the full agent: err_l falls 0.255 → 0.052
at eps=0 (~5×), matching the isolated probe.** So pure attraction does exactly
what the probe said to the world-model.

**But control gets *worse* at every operating point:** failures rise
2.97 → 10.99 (eps=0, 3.7×), 21.17 → 37.84 (eps=0.02), 27.30 → 34.40 (eps=0.10).
A *better-predicting* agent *fails more*. And it does so while keeping
**mean_mass lower** (2.62 vs 3.34): pure attraction holds the cell lower on
average yet still takes more lethal spikes — it mis-ranks actions at the
threshold-crossing moments, not in the bulk.

## Why — the forcefield is load-bearing for control

`control_emergence.md` established (against my own first guess, via a unit test)
that the controller's competence is **not** point-prediction accuracy. It works
by **recognising a recurring safe attractor**: under good control the grid sits
at all-zeros, the majority-bundled safe prototype locks onto that mode, and
`mb_safety` picks the action whose predicted state is nearest it. That readout
needs the rule vectors to stay *distinguishable*, not maximally accurate.

The 0.25 repulsion floor — a defect *for prediction* — keeps the per-action rule
vectors from collapsing together. Remove it and the rules converge tightly onto
their targets (error → 0.05) but lose the spread the safe/failure prototype
discrimination relies on; the action ranking degrades exactly where it matters
(near a shock), and failures rise. The same mechanism that makes the model
accurate makes the **controller** blind at the boundary.

## Implication for the research program

1. **CP3 answer: no — and the inverse holds.** Fixing the prediction floor is
   not free competence; it costs ~3.7× more failures at the greedy optimum. The
   cheapest-looking lever in `expressiveness_ceiling.md` is a control regression.
2. **Prediction fidelity is not the binding constraint on control here — it is
   anti-correlated with it.** Any path to higher competence that routes through
   "better world-model" (CP3, and by extension the nonlinear-binding fix the
   expressiveness note queues next) must be re-justified against *control*, not
   prediction, because this controller's competence lives in prototype
   *discriminability*, not model accuracy.
3. This sharpens the indictment from `control_emergence.md`: the agent is an
   **attractor-recogniser wearing a world-model**, and improving the world-model
   degrades the recogniser. A genuinely model-*based* controller (planning /
   value learning that actually uses prediction accuracy) would need a task where
   prediction accuracy and control are *coupled* — which the trivial-optimum
   battery cell is not (see `control_emergence.md` §terminal: `always rest` = 0.00).

The method point repeats `expressiveness_ceiling.md`'s lesson one level up: an
instrument built to confirm a prediction-side fix surfaced that the fix is a
control-side regression — you only learn that by measuring the thing you actually
care about (fail/1k), not its proxy (err_l).

## Update (CP3 reversed on a non-trivial task) — see `non_trivial_task.md`

The conclusions above are **correct for the trivial battery cell but do not
generalise** — they are an artefact of a benchmark whose optimum is the constant
`always rest`. Re-running the identical stock-vs-pure ablation on the homeostatic
**band** task (`environment.zig` `min_mass`/`max_mass`; no constant policy can
hold it) flips the sign:

```
  task            | stock fail/1k | pure fail/1k | pure err_l
  ----------------+---------------+--------------+-----------
  trivial cell    |   2.97        |  10.99       |  0.052    (pure WORSE)
  homeostatic band|  162.94       |  33.62       |  0.045    (pure ~5x BETTER)
```

On a task that actually **requires the model to act**, the prediction win
converts into a ~5× control win. So the right statement is not "better
world-model hurts control" — it is "**on the trivial task, control did not use
the model at all.**" Point 2 above ("any path through better world-model must be
re-justified against control") stands only for the degenerate cell; on the band,
the repulsion floor is a pure-loss defect for control too, exactly as
`expressiveness_ceiling.md` first argued. Read `non_trivial_task.md` for the full
arc.
