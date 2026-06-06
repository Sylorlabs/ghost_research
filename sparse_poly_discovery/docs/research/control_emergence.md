# Research note: does the "active inference engine" actually control anything?

**Status:** questions stated, instruments built, **answered with reproducible numbers.**
Reproduce with `zig build eval` (table + Q5 + E1 + E2) and `zig build unit-test`
(the VSA / readout-channel assertions). All figures below are means over 6 seeds
× 15,000 steps; the run is deterministic.

## Background

`sparse_poly_discovery` was presented as an *active inference* agent. Active inference says
an agent acts to keep itself in *preferred* states. Reading the code (now
refactored into `agent.zig`) shows it only ever did *half* of that: it learns a
forward model by minimising **perceptual** surprise, but its **actions** were
random or driven by scripted "macros" — the model was never used to choose what
to do. So the headline claim was untested. There was also no evaluation at all:
the project ran a real-time daemon, streamed telemetry to a dashboard, and never
produced a number answering "does it work?".

The environment (`environment.zig`) is a 16-cell ion grid standing in for a
battery cell. `charge` piles mass toward the anode, `discharge` moves it toward
the cathode and drains the top, `rest` decays every cell by 1. Any cell ≥ 5 is a
dendrite short-circuit = **failure**. Scheduled shocks every 500 steps; volatility
after step 750. **The control objective is to avoid failure.** Primary metric:
failures per 1000 steps.

## The questions (each falsifiable)

- **Q1.** Does the forward model learn? (prediction error should fall below the
  frozen ~0.50.)
- **Q2.** Does perceptual surprise-minimisation *alone* (the as-built agent:
  learning + random actions + macros + meta) produce control? *Hypothesis: no —
  failure rate ≈ random, because the model is never used to act.*
- **Q3.** If actions are chosen with the model (pick the action whose predicted
  state is closest to a learned "safe" prototype, farthest from a learned
  "failure" prototype), does control emerge?
- **Q4.** Do the hierarchical add-ons (macros, "executive control" meta-layer)
  help, hurt, or do nothing?
- **Q5.** Is the lowest-surprise action also the safest? (Tests the active-
  inference premise directly.)

## Results

```
  policy                 |   fail/1k | mean_mass |  err_e |  err_l
  -----------------------+-----------+-----------+--------+-------
  baseline_random        |     56.27 |    20.515 |  0.501 |  0.501
  baseline_rest          |      0.00 |     0.993 |  0.502 |  0.502   <- trivial optimum
  baseline_discharge     |     26.60 |    17.112 |  0.501 |  0.501
  baseline_charge        |    245.87 |    27.645 |  0.500 |  0.500   <- catastrophe
  -----------------------+-----------+-----------+--------+-------
  as_built               |     48.20 |    18.998 |  0.394 |  0.409
  mb_surprise            |     30.04 |    16.162 |  0.298 |  0.326
  mb_safety (clean)      |     27.30 |    15.374 |  0.290 |  0.327
  mb_safety +macros      |     45.09 |    17.210 |  0.332 |  0.382
  mb_safety +macros+meta |     45.09 |    17.210 |  0.332 |  0.382
```

- **Q1 — confirmed.** Every learning variant pulls prediction error from the
  frozen ~0.50 down to ~0.29–0.41. The forward model learns.
- **Q2 — confirmed (the indictment).** The as-built architecture scores 48.2 vs
  random's 56.3 — a 14% nudge, and **worse than the one-line `always-discharge`
  policy (26.6)**. Surprise-minimisation with random actions learns to *predict*
  but not to *act*. It is not control.
- **Q3 — confirmed.** Adding model-based safety action selection roughly halves
  failures (56→27). Using the model to choose actions *does* produce control. See
  E1 below — greedy, it does far better than this.
- **Q4 — confirmed (damning for the original design).** The project's headline
  hierarchical machinery is harmful or inert: macros raise failures 27→45 (they
  override the safety choice with crystallised *random* 2-action scripts); the
  "executive control" meta-layer changes nothing (`+macros` and `+macros+meta`
  are identical to two decimals — it never alters the trajectory).
- **Q5 — 93.3%.** The safest action coincides with the most-predictable action
  93% of the time (chance = 33%). Active inference's premise *happens* to hold
  here, because the failure states (cells ≥ 5) are also the least-predictable
  ones. That is why `mb_surprise` (30.0) ≈ `mb_safety` (27.3).

## The mechanism — and a claim my own instrument falsified

Model-based safety reads a learned "safe" vs "failure" prototype. My first
explanation, written into the code comments, was that the prototypes make the
**failure flag** readable. A unit test built to *prove* it (`tests.zig`)
**refuted it**: a state is `S = G ⊕ fail_val` (XOR), and bitwise majority commutes
with a constant XOR, so the `fail_val` term **cancels** in any prototype distance
— it contributes nothing. With independent grid noise the readout is a coin flip,
and the test failed.

The mechanism that *actually* works: under good control the cell sits at a
**single recurring grid (all-zeros)**, so `G` repeats and the majority prototype
**locks onto that attractor**. A second subtlety (also caught by the test): hard
bitwise majority over a near-50/50 mix of two states snaps entirely to the more
frequent one, so the safe attractor only becomes readable when it is the
*dominant* mode. The readout is "recognise the recurring safe state," not "read a
failure bit." The comments and this note were corrected to match what the
instrument said.

## Follow-up E1 — the failure floor is exploration cost

Sweeping the exploration rate of the clean `mb_safety` controller:

```
  epsilon=0.30 -> 38.34 fail/1k   (mean_mass 15.67)
  epsilon=0.10 -> 27.30 fail/1k   (mean_mass 15.37)
  epsilon=0.02 -> 21.17 fail/1k   (mean_mass 13.90)
  epsilon=0.00 ->  2.97 fail/1k   (mean_mass  3.34)   <- near the 0.00 optimum
```

Greedy, the controller scores **2.97 fail/1k** — a **~19× reduction over random
(56.3)** and within striking distance of the trivial optimum (0.00). This is
genuine competence on the task.

## Follow-up E2 — and why exploration hurts *so* much

Action mix of the clean controller (optimal policy ≈ 100% `rest`):

```
  epsilon=0.02: charge=22.8%  discharge=33.4%  rest=43.8%   (21.17 fail/1k)
  epsilon=0.00: charge= 2.1%  discharge=24.2%  rest=73.6%   ( 2.97 fail/1k)
```

Greedy, the controller **does discover the optimal action**: 73.6% `rest`, only
2.1% of the catastrophic `charge`. But a mere 2% exploration **collapses** that:
`charge` jumps from 2.1% to **22.8%** and failures *septuple* (2.97 → 21.17). The
22.8% is far more than the 2% random injection — it is a cascade. The reason
unifies the whole note: the controller is competent **only while it stays parked
on the all-zeros attractor that makes its own safe-prototype readable** (the
dominant-mode result from the unit test). Exploration knocks it off that
attractor; off-attractor the recurring grid is gone, the prototype readout
degrades, the agent starts mis-picking `charge`, which drives mass *up* — further
from the attractor — and the readout degrades further. The competence is real but
*self-stabilising and fragile*: it depends on the agent maintaining the very
regularity its own readout needs.

## Terminal conclusion

1. The as-built "active inference engine" **does not control the cell** — it only
   learns to predict (Q2). Control is not a property the original architecture
   had; it had to be added (Q3).
2. The headline hierarchical / "metacognitive" machinery **hurts or does nothing**
   (Q4). The competent agent is the *simplest* one: forward model + greedy
   model-based action selection, no macros, no meta.
3. A correctly-built model-based controller reaches **2.97 fail/1k** (vs 56.3
   random, 0.00 optimum) — real, reproducible competence — but it is **fragile**:
   it works by recognising a recurring safe attractor, and anything that disrupts
   that attractor (exploration, shocks) degrades it.
4. The task itself is trivially solved by the one-line policy `always rest`
   (0.00). The honest framing of this whole result is therefore modest: a VSA
   predictive-coding agent *can* learn near-optimal control on a toy cell **once
   you make it use its model to act** — not "an active inference engine," and
   nowhere near AGI/ASI.

What this note contributes is the method: refactor the daemon into a synchronous,
seeded agent; pose control as falsifiable questions against fixed-policy
baselines; and let unit tests interrogate the *mechanism*, not just the score —
which is what turned a wrong "reads the failure bit" story into the correct
"recognises a recurring attractor" one.
