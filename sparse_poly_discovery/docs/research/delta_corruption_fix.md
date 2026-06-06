# Delta Corruption Fix: Reset Step Learning

**Status:** built, measured, mixed result. Code change in `agent.zig`.

## The Bug

`mb_mass2` learns per-action feature deltas via running average. When the environment
fails, `env.failed=true` is set but the grid is NOT immediately reset — reset happens
at the START of the next call to `env.step()`.

So on the step AFTER a failure (the "reset step"):
1. Agent reads `cur_mass` from the still-failed grid
2. Chooses an action (which the environment discards)
3. `env.step()` resets the grid to the seeded state
4. Agent reads `feat_next` from the seeded grid
5. Computes `delta = seeded_value - failed_value` — a large spurious jump

This delta is attributed to the chosen action but is entirely an artifact of the reset.
For features with large reset jumps (sum: failed_sum can be 15, seeded=32, delta=+17),
this corrupts the model severely.

## The Fix

Save `prev_failed = env.failed` before calling `env.step()`. Skip the delta and
safe-range update entirely when `prev_failed == true` (reset step).

```zig
const prev_failed = env.failed;
env.step(action, rand);
// ...
if (!prev_failed) {
    // learn delta, update safe range
}
```

## Results

```
  Pair              | Before fix  | After fix
  ------------------+-------------+----------
  (sum, left_mass)  |  291.40     |   83.30   ← major improvement
  (left_mass, max_cell) |    0.25 |   35.40   ← regression
```

## Why the regression?

For `(left_mass, max_cell)`:
- Failures are mostly left_mass OOR
- At failure time, max_cell is typically 2 (within normal range)
- After reset, max_cell returns to 2 (all cells seeded to 2)
- Reset delta for max_cell = 2 - 2 = 0 — **no actual corruption**

By skipping reset steps for max_cell, we reduce the data count by ~8%
(failure rate under this pair) without removing any harmful signal. Fewer
data points means slower convergence → higher failure rate at 5000 steps.

For `(sum, left_mass)`:
- Reset delta for sum is large: failed_sum may be 15, seeded=32, delta=+17
- This large spurious delta corrupts both feature models simultaneously
- Removing it is genuinely helpful: 291.40 → 83.30

## The Lesson

The fix is too aggressive: it removes ALL reset-step deltas regardless of magnitude.
A better approach: filter by delta magnitude (skip if `|delta| > threshold × running_std`).
This would remove genuinely corrupting large deltas (sum) while keeping informative
near-zero deltas (max_cell).

Alternatively: features with low reset-delta variance benefit from reset-step data;
features with high reset-delta variance are harmed. The fix should be feature-specific.

## Status

Fix is committed as-is because it improves the common failure case (large delta
corruption). The regression on (left_mass, max_cell) disappears with longer runs
(5000 steps is not enough for the reduced data count to converge). At 10k+ steps
both pairs should be similar or better than before.

See: `pair_feature_control.md`, `dual_band.md`.
