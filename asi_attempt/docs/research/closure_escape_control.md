# Research note: the closure-wall escape, demonstrated in the control domain

**Status:** built, measured, **a major positive result.** A *learned* controller
beats hand-coded control on the non-trivial band — but **only** once given one
feature the XOR substrate provably cannot compute. Reproduce: `zig build eval`
(`[BAND]` block; means over 6 seeds × 15,000 steps).

## The setup

`non_trivial_task.md` established a homeostatic band `[16,48]` no constant policy
can hold (constants 55–333 fail/1k) but a hand-coded **thermostat solves at
20.80**. Every VSA agent — the prototype-distance `mb_safety`, with or without the
repulsion-floor fix, with random *or* metric encoding — is **stuck above the
thermostat**. This note shows *why*, and what breaks the ceiling.

## Results

```
  policy                 |   fail/1k |  err_l   | note
  -----------------------+-----------+----------+----------------------------
  thermostat (hand-coded)|     20.80 |    —     | the bar to beat
  -----------------------+-----------+----------+----------------------------
  mb_safety stock (XOR)  |    162.94 |  0.329   | prototype-distance readout
  mb_safety pure (XOR)   |     33.62 |  0.045   | + repulsion-floor fix (CP3)
  ordinal stock (XOR)    |     55.63 |  0.267   | + metric value encoding
  ordinal + pure (XOR)   |     55.63 |  0.118   | both XOR fixes — still stuck
  -----------------------+-----------+----------+----------------------------
  mb_mass learned        |     11.02 |  0.294   | + SUM readout => BEATS thermostat
```

## The three XOR fixes are not enough — the readout is closure-bound

The agent's state is a pure XOR of random role/filler vectors; its action choice
scores the *Hamming distance* of the predicted state to a majority-bundled "safe"
prototype. Two independent attempts to fix this **inside the XOR substrate** both
fail to crack the band:

1. **Repulsion-floor fix (pure attraction, CP3):** 162.94 → 33.62. Cuts
   prediction error ~7× and helps, but plateaus at 33.62 (> thermostat).
2. **Metric value encoding (ordinal/thermometer fillers):** 162.94 → 55.63, but
   collapses to the `discharge` attractor (mean_mass 23.5 = const_discharge) —
   it cannot represent "stay in `[16,48]`". A single bundled prototype snaps to
   the dominant mode; it cannot encode a *range* of safe states.

Both are real improvements and both hit a wall, because total mass — `Σ grid[i]`,
a **sum/threshold** — is not a function the XOR/bundle algebra can expose. The
band predicate lives *outside the closure* of the substrate.

## The escape: one out-of-closure feature

`mb_mass` is the **same agent** with one feature added: it reads total mass (the
sum), learns each action's mean mass-delta and the `[min,max]` of safe masses
online, and picks the action whose predicted mass is nearest the safe midpoint.
It still *learns* the dynamics and the band from experience — it is not told
`[16,48]`. Result: **11.02 — it beats the hand-coded thermostat (20.80) by ~2×**
and every XOR agent by 3–15×.

Tellingly, `mb_mass`'s hypervector prediction error stays high (err_l 0.294 — as
bad as the stuck stock agent), yet its control is the best on record. **Control
here is not about world-model prediction accuracy at all; it is about having the
right feature.** This closes the loop on CP3: prediction quality was never the
binding constraint — substrate *expressiveness* was.

## The ceiling is a representational impossibility (theorem-grade)

`zig build probe` (the band-readout ceiling) settles that this is not a tuning
failure but a representational one. Generate random grids, label "mass in [16,48]",
and ask whether *any* linear/XOR readout of the encoding can classify them:

```
  readout                          | random enc | ordinal enc
  ---------------------------------+------------+------------
  nearest-prototype (agent readout)|   0.502    |   0.504      <- chance
  best linear (perceptron, 8192b)  |   0.513    |   0.510      <- chance
  sum-threshold (out-of-closure)   |   1.000    |   1.000
```

Even the *best* linear readout over all 8192 encoding bits is at chance — and
**ordinal (metric) encoding does not help.** The reason is structural: the encoder
XOR-binds all 16 cells into one vector, so the grid collapses to a **parity**, and
total mass (a sum) is information-theoretically unrecoverable by any linear/XOR
readout, whatever the value fillers are. This is the exact control-domain analogue
of `affine_closure` (where GF(2)-affine mixers provably cannot achieve avalanche):
the band predicate lies outside the closure of the substrate, period. `mb_mass`
wins not because it learns better but because it is given a feature the substrate
cannot synthesise.

## Why this matters — the closure principle, demonstrated

This is a controlled before/after of the cross-thread **closure principle**
(`ghost-research-strategic-synthesis`): *search/learning confined to a closed
primitive set cannot produce anything outside that set's closure; the escape is
to inject a generator outside the closure.* The repo now has it in three domains:

| domain | closed substrate | the ceiling | out-of-closure generator |
|--------|------------------|-------------|--------------------------|
| mixers (Thread 07) | GF(2)-affine | statistical failure (proven) | MUL |
| invention (wcore Claim C) | fixed opcode VM | only known mechanisms | a new atom |
| **control (here)** | XOR/bundle VSA | stuck above thermostat | the **SUM** readout |

In every case, grinding *within* the closure (more iters, more tiers, better
prediction, metric encoding) cannot escape; adding the right out-of-closure
generator does — here it is the difference between losing to a one-line policy
(162.94) and beating hand-coded control (11.02). The control domain is the first
where the escape also produces a genuinely *super-human-baseline* learned agent.

## Open

- `mb_mass` regulates to the safe-range midpoint; planning (rollout) over the
  scalar model is the natural next lever (`mb_plan`).
- The general lesson for the whole project: when a learner plateaus, ask whether
  the target predicate is even *in the closure* of its substrate before tuning
  the learner. Expressiveness first, optimisation second.
