# Research note: a non-trivial task — and the CP3 reversal it exposes

> **CORRECTION (E1).** This note calls the band "non-trivial" and reports a hand-coded
> thermostat at 20.80. That thermostat was **badly tuned**: a grid-tuned one scores
> **0.00** — the band is trivially solved by a simple state-dependent rule, just as the
> original cell was by `always rest`. The band is non-trivial **only for constant
> policies** (they fail 205–333); it is *not* hard for hand-coded control. So the learned
> agent's 11.02 is not "competence approaching the bar" — the bar is 0.00 and it's far
> from it. What stands is narrower: no *constant* policy works, and the SUM-feature agent
> beats the XOR-readout agent. The "first genuine competence signal" framing is withdrawn.

**Status:** built, measured. Reproduce with `zig build eval` (the `[BAND]` block) and
`zig build eval-gen` (the `homeostatic` regime). Means over 6 seeds × 15,000 steps
(eval) / 5 seeds × 10k-train/4k-eval (gen).

## Why this exists

Every prior asi_attempt result is haunted by one fact: the battery cell is
**trivially solved by `always rest` (0.00 fail/1k)**. You cannot measure
"intelligence" on a task whose optimum is a constant policy — and CP3
(`cp3_repulsion_floor.md`) showed the consequence: on that task, improving the
world-model *hurt* control, because control there is just "recognise the
recurring all-zeros attractor," for which prediction accuracy is irrelevant.

The fix is a task where **no constant policy is optimal.** `environment.zig` now
takes a homeostatic band `[min_mass, max_mass]` on total grid mass: drop below
`min_mass` (under-charge) or rise above `max_mass` (over-charge) and you fail.
`rest` drains to under-charge, `charge` piles to over-charge — no constant action
can hold a mid-band. Defaults (`min_mass = max_mass = 0`) are byte-identical to
the old environment (verified: the main eval table is unchanged).

## Results — the task is non-trivial AND solvable

`[BAND]` `[16,48]`, disturbances off (shocks/volatility were an accidental mass
source that let constant `discharge` cheat the band):

```
  policy                 |   fail/1k | mean_mass |  err_l
  -----------------------+-----------+-----------+-------
  const_random           |    205.23 |    33.510 |  0.501
  const_rest             |    333.33 |    16.000 |  0.503   <- drains to floor
  const_charge           |    333.33 |    48.000 |  0.499   <- piles to ceiling
  const_discharge        |     55.53 |    23.502 |  0.501   <- best constant, but...
  -----------------------+-----------+-----------+-------
  thermostat (hand-coded)|     20.80 |       —   |    —     <- SOLVABLE
  learned mb_safety stock|    162.94 |    35.048 |  0.329
  CP3 pure (no floor)    |     33.62 |    38.396 |  0.045   <- the result
```

- **Non-trivial:** every constant policy fails — 205–333 fail/1k. The best
  constant (`discharge`, 55.53) only survives ~18 steps per life by bleeding
  through the band; it does not *hold* it.
- **Solvable:** a hand-coded state-dependent thermostat (charge near the floor,
  dump near the ceiling, else bleed) scores **20.80** — proof this is a real
  controllable task, not an unsolvable regime (cf. `bigger_shocks`, where every
  policy ties at a lethal floor).
- **The as-built / stock learned controller fails it:** `mb_safety` stock scores
  **162.94** — beaten by the constant `discharge` one-liner (55.53) and ~8× worse
  than the thermostat. The attractor-recogniser has no single attractor to park
  on, so it collapses. **Generalisation confirms the diagnosis:** `eval-gen`
  shows `homeostatic` is the *only* regime where transfer (299.90) collapses to
  ≈ rest_floor (333.25) — the zero-attractor competence is task-specific and does
  not transfer to a task with a moving setpoint.

## The reversal — prediction COUPLES to control once the task needs the model

CP3 (`cp3_repulsion_floor.md`) found that removing the 0.25 repulsion floor
("pure attraction") cut prediction error ~5× but made control **worse**
(2.97 → 10.99) on the trivial task, and concluded "better world-model must be
re-justified against control." **That conclusion was an artefact of the trivial
task.** Re-run the identical ablation on the band:

```
  CP3 stock (repulsion) :  162.94 fail/1k   (err_l 0.329)
  CP3 pure  (no floor)  :   33.62 fail/1k   (err_l 0.045)   ~5x BETTER, ~7x lower error
```

On a task that **requires using the world-model** to choose the action that keeps
mass in band, the ~7× prediction win converts into a ~5× **control** win — the
exact opposite sign of the trivial-task result. Prediction and control were
decoupled *only because the benchmark was degenerate.*

## Implications

1. **The project's first genuine competence signal.** The fixed agent (pure
   attraction) scores **33.62**, beating *every* constant policy including the
   `discharge` cheat (55.53) and approaching the hand-coded thermostat (20.80).
   This is a learner discovering homeostatic control — not "recognising a
   recurring zero state," which is all the trivial task ever required.
2. **The expressiveness-probe was right after all.** `expressiveness_ceiling.md`
   said "fix the learning rule (the repulsion floor) first." CP3 on the trivial
   task appeared to refute it; the band task vindicates it. The fix was real but
   *unmeasurable* until the task could exercise the model.
3. **Meta-lesson: a degenerate benchmark can make a real capability look like a
   defect and hide its fix.** The single highest-leverage move in this whole line
   was not a better agent — it was a task whose optimum is not a constant. Every
   downstream question (planning, value learning, the GF(2) representational
   ceiling) should be asked on the band, not the cell.

Next: the GF(2) representational ceiling (`expressiveness_ceiling.md` §2) is now
the binding constraint to test — does a nonlinear binding/readout push the fixed
agent below the thermostat's 20.80? And does multi-step planning over the
(now-accurate) model beat greedy here, where greedy was already optimal on the
trivial cell?
