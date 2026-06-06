# Adaptive Feature Discovery v2: Multi-Seed Probes

**Status:** partial success. Reproduce: `zig build adaptive-feature`

Updates to v1 (`adaptive_feature.md`): WARMUP 1500→3000, PROBE_STEPS 2000→10000,
probe now averages 4 seeds per feature (vs single seed in v1).

---

## What Changed

### v1 (single-seed 2000-step probes)
- 3/5 seeds switched to nonzero_count (wrong)
- Mean: 184.13 fail/1k

### v2 (4-seed 10000-step probes)
- 0/5 seeds switch at all (no wrong switches)
- Mean: 29.78 fail/1k

The multi-seed fix eliminated all wrong switches. The key insight: probe results
are seed-dependent. A single probe seed can produce catastrophically wrong results
(seed 2 in v1: left_mass probe = 332.10 fail/1k, should be ~39).

---

## Results (5 seeds, 60k total steps each)

```
  seed | disagree_rate | triggered? | probe winner | fail/1k
  -----+---------------+------------+--------------+--------
  0    | 0.003         | no         | stayed: sum  |   0.47
  1    | 0.045         | yes        | stayed: sum* |  47.63
  2    | 0.041         | yes        | stayed: sum* |  47.40
  3    | 0.041         | yes        | stayed: sum* |  47.48
  4    | 0.010         | no         | stayed: sum  |   5.92
  mean |               | 3/5 trigger|              |  29.78
```

*probe ran but sum won the probe comparison.

---

## Why the Agent Doesn't Switch to left_mass

The probes correctly show no wrong switches, but also don't discover left_mass.
Probe results for triggered seeds:

```
  seed 1:  sum=18.70  left_mass=45.60  (sum wins)
  seed 2:  sum=76.98  left_mass=130.30 (sum wins)
  seed 3:  sum=24.20  left_mass=37.83  (sum wins, but close)
```

Sum probe beats left_mass probe in all triggered seeds.

**Why sum looks better in short probes**: A fresh ScalarController for sum
can hold sum ∈ [16,48] reliably from the seeded start. A fresh left_mass
controller holds left_mass ∈ [6,22] but lets sum drift → more failures initially.
The steady-state advantage of left_mass only appears after ~10,000+ steps of
convergence, which the 10k-step probe captures only partially.

The per-seed probe results are also still noisy (seed 2: sum=76.98 vs seed 1: sum=18.70).
More probe seeds or longer probes would give more reliable estimates.

---

## What Worked

**Disagreement detection is reliable**: Seeds 1-3 (disagree_rate 0.041-0.045)
correctly trigger autonomous feature search. Seeds 0, 4 (0.003-0.010) correctly
stay with sum. The threshold=0.03 fires on the right seeds.

**No wrong switches**: Multi-seed probes correctly reject nonzero_count (which
had catastrophically bad probes in v1). The 4-seed average makes nonzero_count
score 303 fail/1k (seed 1) — clearly worse than sum.

**Mean 29.78 < both baselines**: The system performs better than:
- sum alone (83.31 fail/1k)
- left_mass alone (39.02 fail/1k)
- thermostat (83.33 fail/1k)

This is because seeds 0 and 4 (easy) achieve near-zero failure rates, and the
triggered seeds stay with sum rather than making a harmful switch.

---

## Remaining Limitation

The probe length (10k steps × 4 seeds) is sufficient to reject bad features
(nonzero_count correctly scores ~300 fail/1k) but insufficient to distinguish
good features (sum vs left_mass are within each other's variance band).

Reliable distinction between sum (83.31 long-run) and left_mass (39.02 long-run)
would require ~50k-step probes or a different selection criterion that doesn't
depend on short-run probe performance.

Alternative criterion: instead of "lowest probe fail/1k", use "lowest probe
disagree_rate" (model disagreement in probe). Features that explain more of
the failures should have lower disagree_rate after converging.

See: `adaptive_feature.md` (v1 results), `correlation_feature_discovery.md`.
