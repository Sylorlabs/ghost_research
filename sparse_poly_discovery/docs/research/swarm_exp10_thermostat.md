# Swarm EXP-10 (I56) — hard thermostat tune: is mb_mass win fragile?

**Date:** 2026-07-05  
**Status:** measured — **mb_mass win is fragile (strawman confirmed)**  
**RQ:** I56 falsification hunt — did we beat a badly tuned hand baseline?

## Commands

```bash
cd sparse_poly_discovery && zig build swarm-exp10 --release=fast
# or direct:
zig build-exe -OReleaseFast swarm_exp10_thermostat.zig -femit-bin=/tmp/ghost_swarm_exp10 && /tmp/ghost_swarm_exp10

# Cross-check full harness (BAND block):
zig build-exe -OReleaseFast eval.zig -femit-bin=/tmp/ghost_eval && /tmp/ghost_eval
```

**Protocol:** BAND task `[16,48]`, disturbances off (`shock_period=0`, `volatility_after=1e6`), **15,000 steps × 6 seeds** (same as `eval.zig` `[BAND]` block).

## Summary

| Policy class | Best fail/1k | Beats mb_mass? |
|--------------|-------------|----------------|
| Stock thermostat (`thermostatMeanSeeds`) | ~20.80 (eval ref) | — |
| **E1 grid-tuned (3-branch)** | **0.00** | **yes (11.02 >> 0)** |
| **Hysteresis grid (8,064 configs)** | **0.00** | **yes** |
| Lookahead H=1 (full protocol) | 22.67 | no (mb_mass wins) |
| Lookahead H=2 (full protocol) | 333.33 | no |
| Lookahead H=3/4 (supplementary screen) | 19.00 / 333.50 | no |
| **mb_mass(sum)** | **11.02** | — |

**Hand-tuned best: 0.00 fail/1k. mb_mass still loses badly.**

The original “mb_mass beats hand-coded control” claim was a **strawman**: the stock thermostat (20.80) was under-tuned. A modest threshold grid — already in `eval.zig` E1 — solves the band perfectly. EXP-10 pushes harder (hysteresis + mid-zone + lookahead) and **does not rescue mb_mass**.

What **does** survive is the **closure escape**: mb_mass (11.02) still beats every XOR-substrate agent (33–163 fail/1k). It does **not** beat a tuned rule that reads total mass directly.

---

## Method

### 1. E1 baseline (reproduce `eval.zig`)

3-branch thermostat: `charge` below `charge_below`, `rest`/`discharge` above `high_above`, else `discharge`.

Grid: `charge_below ∈ {14,16,18,20,22,24}`, `high_above ∈ {28,32,36,40,44,47}`, `high_action ∈ {rest, discharge}`.

### 2. Hysteresis expansion

4-threshold state machine with enter/exit bands:

- `charge` while in charging mode until `mass >= charge_above`; enter charging when `mass <= charge_below`
- `rest`/`discharge` while dumping until `mass <= high_below`; enter dumping when `mass >= high_above`
- middle zone: `discharge` or `rest` (`mid_rest` flag)

Screen: 8,064 configs (step-2 coarse thresholds, hysteresis gaps 1–6), 2,000 × 2 seeds; full 15k × 6 verify on screen ≤ 0.5 fail/1k.

### 3. Lookahead (optional)

Deterministic one-step and H-step exhaustive rollout (noise off). Score: avoid failure, minimize band violation, tie-break distance to band midpoint (32).

---

## Results (2026-07-05 run)

```
=== Swarm EXP-10 (I56): thermostat hard tune on BAND [16,48] ===
    15000 steps x 6 seeds, disturbances off

[1] E1 baseline grid (no hysteresis) — repro eval.zig
  best E1: 0.00 fail/1k  charge<=16 high>=28 high=rest

[2] Hysteresis grid (expanded thresholds + mid zone)
  configs screened: 8064 (2k x 2 seeds, full verify if screen <= 0.5)
  best hysteresis: 0.00 fail/1k
    charge<=16 -> charge>=17 | high>=31 -> high<=30
    high-action=rest  mid-action=rest

[3] Lookahead thermostats (deterministic one-step / H-step)
  lookahead H=1: 22.67 fail/1k
  lookahead H=2: 333.33 fail/1k
  lookahead H=3: 19.00 fail/1k (3k x 2 seeds, supplementary)
  lookahead H=4: 333.50 fail/1k (2k x 2 seeds, supplementary)

[4] Learned reference
  mb_mass(sum): 11.02 fail/1k

=== VERDICT ===
  best hand-tuned (any class): 0.00 fail/1k
  mb_mass:                     11.02 fail/1k
  => mb_mass LOSES to best hand-coded thermostat — prior win was STRAWMAN.
```

### Best hand-tuned parameters

| Class | Parameters | fail/1k |
|-------|------------|---------|
| E1 tuned | `charge<=16`, `high>=28`, high=`rest` | **0.00** |
| Hysteresis | `charge<=16→>=17`, `high>=31→<=30`, high=`rest`, mid=`rest` | **0.00** |

Both achieve **perfect band holding** on the deterministic BAND task.

### mb_mass

**11.02 fail/1k** — reproduced exactly from prior `eval` runs. Greedy scalar readout regulates toward the learned safe midpoint but cannot match a rule that directly thresholds total mass with tuned switches.

---

## Interpretation

### Is the mb_mass win fragile?

**Yes — to hand-baseline tuning.** Any claim that “learned control beats hand-coded” on BAND is **false** once the thermostat is grid-searched (0.00 vs 11.02).

**No — to XOR-substrate readout.** mb_mass still wins 3–15× over `mb_safety` / ordinal agents (closure escape intact; see `closure_escape_control.md`).

### Why doesn’t lookahead help?

One-step greedy rollout **does not** encode the same invariant structure as a hysteresis thermostat. It optimizes immediate next-mass without the sustained branch logic that prevents floor/ceiling oscillation. H=2 exhaustive rollout is worse (333 fail/1k) — likely overfitting to local mass without the global band policy. **Planning over mass alone ≠ a tuned thermostat** on this task.

### Hysteresis vs E1

Hysteresis finds a **different** parameterization (narrow 1-unit dump band 30–31) but the same score (0.00). Extra tuning buys **robustness margins**, not a better headline number on deterministic BAND.

---

## Honest verdict (I56)

| Question | Answer |
|----------|--------|
| Best hand-tuned score? | **0.00 fail/1k** (E1 and hysteresis tie) |
| Does mb_mass still lose? | **Yes — 11.02 vs 0.00** |
| Was the prior “beats thermostat” claim valid? | **No — strawman** (stock 20.80 thermostat) |
| Does anything positive survive? | **Closure escape only** — SUM readout beats XOR agents; mb_mass is a **weak controller** that beats weaker ones |
| Does harder tuning change the story? | **No** — hysteresis and 8k-config sweep confirm E1; lookahead does not close the gap |

**Conclusion:** Falsification hunt **supports** the corrected framing in `closure_escape_control.md`. Tune the hand baseline harder → mb_mass **still loses**. The interesting result is representational (out-of-closure SUM), not superhuman learned control.

---

## Artifacts

- Harness: `sparse_poly_discovery/swarm_exp10_thermostat.zig`
- Build step: `zig build swarm-exp10`
- Prior correction: `closure_escape_control.md` (E1 block)
- Stock baseline reference: `eval.zig` `thermostatMeanSeeds` → 20.80 fail/1k

## References

- `closure_escape_control.md` — closure escape vs strawman thermostat correction
- `non_trivial_task.md` — BAND task definition
- `eval.zig` — E1/E2/E3 BAND block (grid thermostat, mb_plan, noise stress)
- RESEARCH_QUESTIONS.md **#56** (I56), **#19** (planning vs greedy)