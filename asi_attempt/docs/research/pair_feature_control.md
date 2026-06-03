# Pair Feature Control on Dual-Band

**Status:** built, measured, **surprising**. Reproduce: `zig build dual-band-test`

## Setup

The dual-band task has three failure modes:
1. Any cell ≥ 5 (dendrite failure, `fail_threshold=5`)
2. total_mass < 16 or > 48 (sum band)
3. left_mass < 6 or > 22 (left-half band)

The `mb_mass2` controller tracks TWO features simultaneously, picks the action
minimizing total out-of-band violation across both.

References: thermostat=83.33, mb_mass(sum)=83.31, mb_mass(left)=39.02 fail/1k.

---

## Results: pair feature discovery

```
  pair(sum, left_mass)   | 270.30 fail/1k  ← WORSE than single features
  pair(sum, right_mass)  |  83.25
  pair(left_mass, max_cell) |   0.25 fail/1k  ← NEARLY PERFECT
  pair(max_cell, left_mass) |   0.25
```

**The "obvious" pair `(sum, left_mass)` is catastrophically bad (270.30).**
**The non-obvious pair `(left_mass, max_cell)` is nearly optimal (0.25).**

The pair search discovered this without knowing in advance which pair works.
This is the first genuine positive result for automatic feature pair discovery
in this project.

---

## Why (left_mass, max_cell) = 0.25 works

The two features together COVER all three failure modes as side effects:

- **max_cell** directly prevents cell overflow (fail_threshold=5). When max_cell
  is regulated to stay ≤ 4, the agent prefers rest/discharge over charge. This
  limits total sum from growing too high (sum can't grow if max cells are capped).

- **left_mass** directly prevents left-half band violations. When left_mass is
  low, the agent charges — which also increases total sum, preventing sum from
  going too low.

Together: (left_mass, max_cell) accidentally covers all three failure modes even
though neither feature directly measures total_sum. The pair finds a control
equilibrium where the three constraints are jointly satisfied.

---

## Why (sum, left_mass) = 270.30 fails

The `mb_mass2` controller learns per-action deltas for BOTH features from live
interaction, including post-failure resets. After a failure, the environment
auto-resets to the seeded state (all cells=2). The delta computed is:
`(seeded_left_mass - pre_failure_left_mass)`, which is a large reset artifact.

For (sum, left_mass):
- Both features suffer delta corruption from resets
- The two corrupted feature models interfere with each other
- The combined 2D action choice is worse than either feature alone

The ScalarController (simpler, no VSA overhead) with sum-only achieves 31.23
on dual-band. But the full Agent's mb_mass2(sum, left_mass) = 270.30 because
the second-feature delta learning amplifies the corruption.

**Key insight: adding a second feature can HURT control if the second feature's
delta model is noisy and interferes with the first feature's signal.** More
information ≠ better control when the information is poorly estimated.

---

## The discovery is genuine

The pair search tried all C(4,2) = 6 directed pairs and found (left_mass, max_cell)
without any prior knowledge that this pair would work. The "obvious" pair (sum, left_mass)
was checked and found to be terrible.

This answers research question #21 positively: **automatic pair search CAN discover
a non-obvious feature combination that solves a task where no single feature works.**
The discovery uses the same exhaustive pair search as `pairGrow()` in `synergy.zig` —
the principle transfers from the bit-op domain to the control domain.

---

## Honest grade

The finding is real and surprising. However:

1. **The search is exhaustive** (4 features × 3 = 12 pairs). Scaling to N features
   would require N² probes. For large feature sets, smarter search is needed.

2. **The result depends on the specific implementation** (full Agent vs ScalarController).
   The full Agent's delta corruption explains why (sum, left_mass) fails. A cleaner
   implementation might have (sum, left_mass) work as expected.

3. **The pair (left_mass, max_cell) works because of an emergent coverage property** —
   the features jointly cover constraints neither directly measures. This is a genuine
   example of synergy in the feature space (emergent escape #38 transferred to control).

4. **Next**: can the agent discover this pair AUTONOMOUSLY from interaction, without
   running all pairs? This requires smarter feature pair proposals (e.g., based on
   correlation with failures) rather than exhaustive search.

See: `dual_band.md`, `pair_search.md`, `feature_discovery.md`.
