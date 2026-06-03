# Dual-Band Task (#21): Sum Is Insufficient

**Status:** built, measured, confirmed.
Reproduce: `zig build eval` (look for `[DUAL_BAND]` section).

## Setup

Add a second constraint on top of the standard homeostatic band:

```
total_mass ∈ [16, 48]    (same as the BAND task)
left_mass  ∈ [6, 22]     (cells 0..7 must stay in this range)
```

Both must be satisfied simultaneously. `min_left_mass / max_left_mass` params
added to `TaskParams` in `environment.zig`. Seeding: total_mass=32 → each cell=2
→ left_mass=16 ∈ [6,22] ✓. No shocks/volatility.

**Why this should need 2D readout:** The charge action concentrates mass on the
LEFT (ions move toward index 0). A controller that charges to maintain total_mass
also increases left_mass — potentially exceeding the left_mass ceiling. The two
constraints pull in opposite directions during recovery. Total mass alone doesn't
tell you whether you're violating the left_mass constraint.

---

## Results

```
  policy              | fail/1k
  --------------------+---------
  thermostat(sum)     |   83.33    ← was 0.00 on single-band
  mb_mass(sum)        |   83.31    ← same failure
  mb_mass(left_mass)  |   39.02    ← best single feature, still 3.5x worse
  mb_mass(right_mass) |   83.31
  mb_mass(nonzero)    |  499.98    ← catastrophic
```

**Feature search best:** `left_mass` at 39.02 fail/1k.
**Single-band reference:** `sum` at 11.02 fail/1k.

---

## What's happening

The sum-only thermostat (tuned to 0.00 on the single band) fails completely:

1. When total_mass drops below the threshold, it charges.
2. Charging moves mass LEFT → left_mass increases toward and past 22.
3. left_mass > 22 → immediate failure.
4. After reset, the cycle repeats: thermostat charges again.

The thermostat has no information about left_mass and cannot prevent the overshoot.
It's not a tuning failure — it's a representational failure. The sum feature does
not encode left_mass, and left_mass constraints are not visible through total mass.

---

## Why left_mass (39.02) is the best single feature but still bad

mb_mass(left_mass) regulates the left half but ignores total_mass. When left_mass
drifts low, it charges — which increases left_mass and total_mass together. When
left_mass is high, it rests or discharges — which decreases both. But:

- If total_mass falls out of [16,48] while left_mass is in range → failure.
- The controller can't distinguish "total_mass violation" from "left_mass violation."

A 39.02 fail/1k is 3.5× worse than the 11.02 on the single-band task. The task
is measurably harder because it requires more information per action decision.

---

## Verdict: dual-band genuinely needs 2D readout

The dual-band task is the first controlled demonstration in this repo where:
1. **A single expert feature fails** even when correctly chosen (left_mass at 39.02)
2. **The best hand-coded controller fails** (thermostat at 83.33 vs 0.00)
3. **The gap is large**: 83 fail/1k → 0.00 on single-band (1.000 → complete failure)

A 2D controller would need to check BOTH:
- Charge when: sum < 24 AND left_mass < 12
- Discharge when: sum > 40 OR left_mass > 18
- Rest otherwise

This is genuine 2D control — not achievable by any scalar feature mb_mass.

## What this sets up

The experiment confirms the theory (#21): a 2D task requires 2D readout. The
next experiments:

- **2D mb_mass**: extend the agent to track two features simultaneously and
  combine them into a 2D action policy. Does a learned 2D controller solve
  dual-band where all 1D controllers fail?
- **Pair feature discovery**: can feature search over pairs (sum+left_mass) find
  the controlling combination without being told which pair matters?
- **Information-theoretic measurement**: how much mutual information does each
  feature carry about the 2D failure condition? Confirms representational gap.

See: `non_trivial_task.md` for the single-band baseline,
`feature_discovery.md` for the 1D feature discovery context.
