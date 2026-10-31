# Swarm EXP-9 — C21: Dual-band where sum fails; does feature-search find a 2-feature controller?

**Date:** 2026-07-06  
**Status:** **COMPLETE** — measured on fresh runs after `unified_invention.zig` build fix.

## Commands

```bash
cd sparse_poly_discovery && zig build-exe -OReleaseFast dual_band_test.zig -lc && ./dual_band_test
cd sparse_poly_discovery && zig build-exe -OReleaseFast correlation_discover.zig -lc && ./correlation_discover
cd sparse_poly_discovery && zig build hardness-router-test --release=fast
```

(`zig build dual-band-test` / `correlation-discover` also work once the full install graph compiles.)

## Question (RQ #21 / C21)

On a band variant where **sum-only control fails**, can autonomous **2-feature search** discover a controller that beats the best single feature — without being told the pair?

Focal variant: **(sum, max_cell)** — additive total mass plus nonlinear order statistic (`max_cell`, the “max” in the menu; no `variance` feature exists in `FeatureKind`). The naive hypothesis is that pairing sum with a nonlinear extremal feature should suffice. It does not.

## Task (dual-band)

```
total_mass ∈ [16, 48]
left_mass  ∈ [6, 22]   (cells 0..7)
```

Failure modes: cell overflow (≥5), sum OOR, left_mass OOR. Sum readout cannot see left-half distribution; single-band sum controller goes from ~0 fail/1k to ~83 fail/1k here.

---

## Harness 1 — `dual-band-test` (exhaustive O(N²) pair search)

Budget: **5000 steps × 4 seeds** per policy. Menu: `{sum, left_mass, right_mass, max_cell}`.

### Single-feature baselines

| policy | fail/1k |
|--------|---------|
| mb_mass(**sum**) | **83.31** ← sum alone fails |
| mb_mass(left_mass) | **39.02** ← best single |
| mb_mass(max_cell) | 115.92 |

### Focal (sum, max) variant

| policy | fail/1k | vs sum alone |
|--------|---------|--------------|
| mb_mass2(**sum, max_cell**) | **83.30** | **no gain** (≈ sum) |
| mb_mass2(sum, left_mass) | 83.30 | no gain |
| mb_mass2(left_mass, right_mass) | 270.35 | worse |

The obvious additive+extremal pair **(sum, max)** does not solve dual-band. Max_cell’s value is **prospective** (prevents overflow before failure), not visible as sum+max retrospective correlation.

### Exhaustive pair search (12 directed pairs)

| pair | fail/1k |
|------|---------|
| **(left_mass, max_cell)** | **35.40** ← BEST |
| (max_cell, left_mass) | 35.40 |
| (sum, *) / (*, sum) except above | ~83.25–83.30 |
| (left_mass, right_mass) | 270.35 |

**Verdict:** exhaustive search **finds** the emergent pair `(left_mass, max_cell)` and it **beats** best single-feature (35.40 vs 39.02 left_mass; 35.40 vs 83.31 sum).

> Note: older docs report 0.25 fail/1k for this pair before the delta-corruption fix (`delta_corruption_fix.md`). Post-fix, skip-reset-step learning trades spurious delta removal for slower max_cell convergence at 5k steps → ~35 fail/1k is the current honest number.

---

## Harness 2 — `correlation-discover` (O(N) retrospective 2-feature proposals)

Budget: 5000×8 warmup; 10000×6 verify; 8000×6 single-feature probes.

### Approach 1 — deviation correlation (top-2 by \|fail_mean − safe_mean\|/std)

Proposed: **(nonzero_count, left_mass)**  
Verify: **35.73 fail/1k** (known best 35.52) — **wrong pair name, near-optimal control**

### Approach 2 — controllability-ranked (pair top-2 singles)

Singles: sum=32.96, left_mass=48.42, max_cell=115.92  
Proposed: **(sum, left_mass)**  
Verify: **83.33 fail/1k** — **FAIL**

### Approach 3 — residual OOR (primary left_mass, residual partner)

Proposed: **(left_mass, sum)**  
Verify: **83.33 fail/1k** — **FAIL**

**Verdict:** retrospective failure analysis **does not reliably identify** `(left_mass, max_cell)`. `max_cell` has **0.000 OOR fraction** at failure time — proactive-control features are invisible to correlation. Controllability ranking picks the “obvious” (sum, left) pair that **catastrophically fails** in 2D.

---

## Harness 3 — `hardness-router-test` (guided cross-class pair search)

Budget: 5000×6 single probes; 15000×6 pair verify; brute = 12 directed pairs.

### Single-feature hardness

| feature | class | fail/1k |
|---------|-------|---------|
| sum | deg1 | 83.40 |
| left_mass | deg1 | 35.80 |
| right_mass | deg1 | 83.30 |
| max_cell | extremal | 83.30 |

Task class: **q38_compound** (deg1 ∧ extremal both fail alone → pair needed).

### Guided vs brute

| method | proposed pair | fail/1k |
|--------|---------------|---------|
| **Hardness router** | **(left_mass, max_cell)** | **35.13** |
| Brute O(N²) | (left_mass, max_cell) | 35.13 |
| Naive (sum, left_mass) | — | 83.33 |
| (sum, max_cell) | — | ~83.30 (dual-band-test) |

Router **matches brute** on pair identity and fail rate.

---

## Does 2-feature beat single-feature?

**YES** — for the pairs search actually finds:

| controller | fail/1k | beats best single (39.02)? |
|------------|---------|----------------------------|
| mb_mass(left_mass) | 39.02 | — |
| mb_mass2(left_mass, max_cell) | **35.40** | **yes (−3.6)** |
| mb_mass(sum) | 83.31 | no |

The winning pair is **not** (sum, max) or (sum, left); it is **(left_mass, max_cell)** — emergent indirect coverage of all three failure modes.

---

## Sample cost (environment steps, approximate)

| method | expensive evaluations | env steps (order) |
|--------|----------------------|-------------------|
| **Exhaustive pair search** | 12 pair runs | **~240k** (12 × 5k × 4) + 60k presets |
| **Hardness router (guided)** | 4 singles + 1 pair | **~210k** (4×5k×6 + 15k×6) |
| **Hardness router (brute baseline)** | 12 pair runs | **~1.08M** (12 × 15k × 6) |
| **Correlation-discover** | warmup + 3 approaches + verifies | **~580k** |

Guided router reduces pair-evaluation cost **~5×** vs brute (1 cross-class verify vs 12 full pair runs) while matching the optimal pair.

Pair search cost scales **O(N²)** in menu size (N=4 here → 12 directed pairs). Correlation methods are **O(N)** analysis but miss proactive features.

---

## PASS / FAIL summary

| criterion | result |
|-----------|--------|
| Sum alone fails on dual-band | **PASS** (83.31 fail/1k) |
| Obvious (sum, max_cell) 2-feature fixes it | **FAIL** (83.30 — no improvement) |
| Exhaustive 2-feature search finds beating pair | **PASS** — (left_mass, max_cell) 35.40 vs 39.02 single |
| Hardness-guided 2-feature search | **PASS** — matches brute, 35.13 fail/1k |
| Correlation / controllability 2-feature search | **FAIL** — wrong pair or 83 fail/1k |
| **EXP-9 overall (C21)** | **PASS** for pair-combination search; **FAIL** for retrospective 1→2 escalation |

---

## Interpretation

1. **C21 is real:** dual-band is the controlled band where sum fails and 2D readout helps; the fix is not “add sum to something” but an **emergent cross-class pair** (deg1 + extremal).
2. **(sum, max) is a deliberate negative control:** nonlinear `max_cell` alone looks useless (115.92) and shows zero failure correlation, yet in combination with `left_mass` it enables near-optimal control. Value is **combinatorial**, not single-feature salience.
3. **Search mechanism matters:** only methods that **evaluate pairs in combination** (exhaustive or hardness cross-class routing) succeed. Escalating from best singles or failure correlates does not.
4. **Variance:** not in the control `FeatureKind` menu; `max_cell` is the tested nonlinear order statistic. For distributional spread, `nonzero_count` appears in correlation top-2 but does not substitute for `max_cell` in the optimal pair.

---

## Artifacts / fixes

- `unified_invention.zig`: added missing `oriented()` helper (build blocker for `zig build` install graph).
- `dual_band_test.zig`: explicit `mb_mass2(sum,max)` line for C21 focal variant.

## References

- `dual_band.md` — task definition (#21)
- `pair_feature_control.md` — emergent (left_mass, max_cell) discovery
- `correlation_feature_discovery.md` — why retrospective analysis fails
- `delta_corruption_fix.md` — 0.25 → 35.40 regression explanation
- `hardness_router.zig` — Q38 compound routing on control features