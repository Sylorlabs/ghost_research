# FORK E4-G00 — genuinely-novel hard-mint generalization test

**Date:** 2026-07-06  
**Status:** measured  
**Parent:** SWARM EXP-5 (`swarm_exp05_rq9_taxonomy.md`)  
**Reproduce:**

```bash
cd sparse_poly_discovery && zig build swarm-fork-e4-g00 --release=fast
```

Harness: `swarm_fork_e4_g00.zig` (~9 s).

## Question

EXP-5 left seed-pinned **G00** `((c0*c0)*(max>thresh))` as the sole **genuinely-novel** escape
outside expanded RQ9 basis (v2 test 0.463, v1 test 0.830). This fork asks:

1. Does the mint **generalize across held-out grid seeds** (not just the canonical RQ9 pair)?
2. Does **promoting G00 into the E4 cell library** lift downstream hard-target solve rate?

## Pinned mint

| Field | Value |
|-------|-------|
| E4 target seed | `0xE4CE11ED0FF1CE42` |
| Program | `((c0*c0)*(max>thresh))` |
| Threshold | train median (canonical ≈ 0.0) |
| Certified label | binary: `eval(prog) > threshold` |

**Note:** E4 round-1 also promoted `(sum*parity)` as “G00” on the **same** E4 grid seed — a different
program. RQ9/EXP-5 G00 is the **hardest** candidate (`pick0` from `generateE4Targets`), not the
sum*parity mint. This fork tests the EXP-5 survivor.

## Phase 1 — held-out generalization across seeds

**Protocol:** mint program **fixed** across seeds; threshold **recalibrated** per train seed (train median).
v1/v2 greedy basis search on **canonical** pair only (EXP-5 anchors); alt seeds report mint-direct +
static-basis max \|ρ\| (mono+Walsh+world, 523 features).

| seed pair | train seed | held-out seed | mint-direct | v1 basis | v2 basis | max\|ρ\| |
|-----------|------------|---------------|-------------|----------|----------|----------|
| **canonical** | `0xF0235A11CE0FF1CE` | `0xE957E5700002` | **0.463** | **0.830** | **0.463** | 0.273 |
| alt-A | `0xA1B2C3D4E5F60718` | `0x1234567890ABCDEF` | 0.459 | — | — | 0.251 |
| alt-B | `0xDEADBEEFCAFE0001` | `0xBADDCAFE00000002` | 0.460 | — | — | 0.249 |
| alt-C | `0x1111222233334444` | `0xAAAABBBBCCCCDDDD` | 0.457 | — | — | 0.237 |

**Mean mint-direct (4 seeds): 0.460** — stable ~0.46 held-out; no seed lifts mint-only logit near 0.90.

**Interpretation:**

- Mint-direct ≈ v2 basis on canonical (0.463): the predicate’s **raw feature** does not generalize;
  val-perfect VM/synth fits are **routing artifacts** on train, not transferable signal.
- v1 basis 0.830 > mint-direct: greedy composition finds **correlated proxies** on held-out that
  still miss the 0.90 reproducibility bar.
- max\|ρ\| ≪ 0.995 on all seeds: label is **not** a high-correlation lift of static mono+Walsh+world
  features — consistent with genuinely-novel classification.

## Phase 2 — downstream library promotion (E4 grid)

**Protocol:** E4 seed `0xE4CE11ED0FF1CE42`; 20 hard targets (depth≥3, base menu <0.70); base library =
8 singleton cells; compare coverage **base** vs **base+G00 mint**.

| Metric | base (8 cells) | base + G00 mint |
|--------|----------------|-----------------|
| Solved (≥0.90) | **0/20** | **0/20** |
| Lift targets (unsolved→solved) | — | **0** |

Best near-miss: G19 `((c0*c0)+(sum*parity))` base 0.687 → +G00 0.684 (no lift). Small +0.02–0.03
bumps on several targets; **none** cross certification floor.

**Contrast with E4 forge:** E4 promotes **discovered** mints per-target (`sum*parity`, rank-compare)
and reaches **18/20** via **composition of multiple opaque primitives**, not by injecting the
hard G00 predicate alone into an 8-cell menu.

## Verdict

| Criterion | Result |
|-----------|--------|
| **Genuinely novel** | **YES** — v2 basis 0.463 < 0.90; stable ~0.46 mint-direct across seeds; max\|ρ\| < 0.995 |
| **Canonical held-out acc** | mint-direct **0.463**; v1 basis **0.830**; v2 basis **0.463** |
| **Multi-seed mint-direct** | mean **0.460** (4 seeds) |
| **Promotion helps downstream** | **NO** — 0/20 → 0/20; 0 lift targets |
| **Fork verdict** | **KEEP** — outside expanded basis; downstream gain requires **other** mint families (E4 G06 rank-compare), not G00 alone |

## Conclusion

`((c0*c0)*(max>thresh))` is a **stable, seed-robust genuinely-novel survivor**: held-out accuracy
stays ~0.46 whether measured mint-direct or via expanded RQ9 basis, and static-feature correlation
stays far below the novelty gate. Promoting this single mint into the minimal E4 library **does not**
unlock downstream hard targets — the honest value is as a **falsification anchor** (equivalence-tax
escape), not as a library primitive for composition.

**Recommended follow-ups:** threshold-sweep / calibration study; deeper VM (depth>6) oracle; relate G00
to cell-product × count-threshold family vs affine monomial closure.

## See also

`swarm_exp05_rq9_taxonomy.md`, `open_invention_rq9.md`, `open_invention_e4.md`, `open_invention_e26.md`,
`swarm_fork_e4_g00.zig`.