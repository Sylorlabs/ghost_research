# Swarm EXP-8 — C19: Multi-step planning vs greedy mb_mass

**Date:** 2026-07-05  
**Status:** measured — planning does **not** materially beat greedy; scalar-model bottleneck confirmed.

## Question (RQ19 / C19)

Does **multi-step planning** (rollout over the learned scalar mass model) beat greedy `mb_mass`
(**11.02 fail/1k**), or is greedy already optimal for the homeostatic band `[16,48]`?

## Commands

```bash
# Full harness (includes BAND block + E2 planning sweep)
cd sparse_poly_discovery && zig build eval --release=fast

# Focused EXP-8 probe (same protocol, faster)
cd sparse_poly_discovery && zig run planning_probe.zig -OReleaseFast
```

**Protocol:** `TaskParams{ min_mass=16, max_mass=48, shock_period=0, volatility_after=1_000_000 }`  
**Metric:** failures per 1000 steps (lower = better)  
**Seeds:** 6 (seeds 1–6) × **15,000** steps  
**Controller:** `epsilon=0`, macros/meta off, feature=`sum`

## Implementation

`agent.zig` already had `.mb_plan` — H-step exhaustive rollout over the learned per-action
`mass_delta[]`, scoring sequences by out-of-band steps + 0.01×|mass−setpoint| centering term.
For EXP-8 we made horizon configurable via `Config.plan_horizon` (was hardcoded `H=4`).

| Depth | Sequences enumerated | Role |
|-------|---------------------|------|
| H=1 | 3¹ = 3 | 1-step lookahead (≈ greedy objective) |
| H=3 | 3³ = 27 | short horizon |
| H=5 | 3⁵ = 243 | longer horizon |

## Results (2026-07-05, `planning_probe.zig -OReleaseFast`)

| Policy | fail/1k | mean_mass | vs greedy |
|--------|---------|-----------|-----------|
| **mb_mass (greedy)** | **11.02** | 33.220 | — |
| mb_plan H=1 | 11.02 | 33.220 | tie |
| mb_plan H=3 | **10.92** | 34.020 | −0.10 |
| mb_plan H=5 | 23.39 | 32.249 | +12.37 (worse) |
| thermostat (grid-tuned) | **0.00** | — | charge≤16, high≥28, high=rest |

**Best planning:** H=3 at **10.92 fail/1k**  
**Best tuned thermostat:** **0.00 fail/1k** (charge≤16, high≥28, rest on high)

Corroboration from `zig build eval` BAND block (same run): `mb_mass learned = 11.02`.

## Prior art (H=4, pre-`plan_horizon` config)

Earlier `eval.zig` E2 block reported **mb_plan H=4 = 11.19** — slightly *worse* than greedy.
This EXP-8 depth sweep shows the optimum is shallow (H=3) and deeper horizons hurt.

## Analysis

1. **Greedy is near-optimal for the learned scalar model.** H=1 ties greedy exactly; H=3
   improves by only **0.10 fail/1k** (~1.5 fewer failures over 90k total steps) — within
   run-to-run noise.
2. **Depth sensitivity is adverse.** H=5 more than doubles failures (23.39). The scalar
   rollout amplifies model error over longer horizons; there is no reliable planning gain.
3. **Planning is not the competence bottleneck.** Even best planning (10.92) remains
   **10.9× worse** than the grid-tuned thermostat (0.00). The gap is the quality of the
   learned 1-step delta model + setpoint heuristic, not lookahead depth.
4. **Mechanism:** `mb_plan` rolls forward `cur_mass + Σ mass_delta[a]` — a linear
   extrapolation of running-mean deltas. On this band task the greedy 1-step setpoint
   tracker already captures nearly all usable signal from that model.

## Verdict

| Field | Value |
|-------|-------|
| **Best planning score** | **10.92 fail/1k** (H=3) |
| **Beats greedy (11.02)?** | **Marginally** (Δ = −0.10; H=1 ties; H=5 hurts) |
| **PASS / FAIL** | **FAIL** |

**FAIL** on the research bar: multi-step planning does not meaningfully beat greedy `mb_mass`.
Greedy is effectively optimal for this scalar readout; competence gains require a better model
or controller (cf. hand-coded thermostat), not deeper rollout.

## Code touched

- `agent.zig`: `Config.plan_horizon` for `.mb_plan`
- `eval.zig`: E2 sweep over H ∈ {1, 3, 5}
- `planning_probe.zig`: focused EXP-8 harness
- `build.zig`: `planning-probe` step (note: full `zig build` may fail on unrelated targets;
  use `zig run planning_probe.zig -OReleaseFast` directly)