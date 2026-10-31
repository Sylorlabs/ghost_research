# Swarm EXP-1 — menu-growth re-run & verification (pair-selection / ceiling break)

**Date:** 2026-07-05  
**Status:** **PASS** — reproducible; ceiling break confirmed; no P0–P6 regressions.

## Commands

```bash
cd sparse_poly_discovery && zig build menu-growth --release=fast        # ~15 s
cd sparse_poly_discovery && zig build structure-discovery --release=fast  # ~31 s
```

Seed fixed in both probes: `0x9E3B1D0FA5172C44`. Split: train/val/test = 4500/2250/2250.

## Summary

| Metric | Prior (`menu_growth.md`) | This run | Match |
|--------|--------------------------|----------|-------|
| Hidden-pair **fixed-menu** test acc | 0.556 | **0.556** | ✓ |
| Hidden-pair **discovered** pair | (2,5) | **(2,5)** | ✓ |
| Hidden-pair **discovered** test acc | 1.000 | **1.000** | ✓ |
| Escape certify | PASS | **PASS** | ✓ |
| Irreducible R² (menu°2 → c₂·c₅) | 0.261 | **0.261** | ✓ |
| Kill-test R² (menu+cross) | 1.000 | **1.000** | ✓ |
| **Ceiling broken** | Y (0.591 → 1.000) | **Y** | ✓ |
| F24 P7 menu ceiling | 0.591 | **0.591** | ✓ |

## Menu-growth (Phase B) — fresh output

```
TARGET 1 — hidden pair (2,5)   [Frontier-24 menu ceiling: 0.591]
  fixed menu (joint degree-2 over 6 inners)   test 0.556   (chance 0.501)
  DISCOVER best pair = (2,5)                  val 1.000   test 1.000
  CERTIFY escape         PASS   (1.000 ≥ 0.90, menu 0.556 < 0.70)
  CERTIFY irreducible    PASS   (held-out R² = 0.261 < 0.40;
                                 kill-test R² = 1.000 → non-vacuous)
  PROMOTE                       ceiling 0.591 → 1.000   CEILING BROKEN ✓

TARGET 2 — hidden triple (1,3,6)   [pair-family ceiling]
  fixed menu                                  test 0.520   (chance 0.513)
  best PAIR (grown family) = (3,5)            test 0.501   → CEILING
  TRIPLE-relation inner                       test 1.000   → next family escapes
```

## Structure-discovery baseline (Frontier 24) — P0–P7 regression check

| Predicate | Discovered (inner, outer) | Test acc | Prior doc | Regression? |
|-----------|---------------------------|----------|-----------|-------------|
| P0 parity-of-count | (count, spectral) | **1.000** | 1.000 | none |
| P1 sum-threshold | (sum, threshold) | **1.000** | 1.000 | none |
| P2 max-threshold | (max, threshold) | **1.000** | 1.000 | none |
| P3 inversion-parity | (inversion, spectral) | **1.000** | 1.000 | none |
| P4 oriented v1>v0 | (oriented, threshold) | **1.000** | 1.000 | none |
| P5 product-threshold | (product, threshold) | **1.000** | 1.000 | none |
| P6 AND-composition | (count, spectral) | **1.000** | 1.000 | none |
| P7 HIDDEN pair (2,5) | (count, spectral) ceiling | **0.591** | 0.591 | none (expected ceiling) |

**P0–P6:** 7/7 routed correctly, all test = 1.000. **No regressions.**

## Verdict

- **Hidden-pair test acc (post-discovery):** **1.000**
- **Ceiling broken:** **Y** — certified pair-selection breaks F24's 0.591 menu ceiling.
- **P0–P6 regressions:** **none**

EXP-1 is a clean **reproducibility confirm** of `menu_growth.md`. Every reported number matches the prior doc exactly on the fixed seed.

## Fork question — triple-arity ceiling

Target 2 in this run reproduces the predicted **wall relocation**:

- The pair-family that just escaped Target 1 **cannot** reach the hidden triple (best pair (3,5) at **0.501 ≈ chance**).
- A hand-built triple-relation inner `[c₁−μ, c₃−μ, c₆−μ, triple-product]` reaches **1.000**.

This is **not** a failure of EXP-1; it is the designed consequence of fixing arity at pairs. The open fork for Phase C (`inner_forge`) is whether an **open inner-transform forge** (no fixed arity) can iterate past triple-arity bottoms or **saturates** at the VM's expressive closure — the decisive question named in `menu_growth.md` and `inventable_substrate_design.md`.

Practical fork for the swarm:

1. **Accept pair-growth as sufficient for EXP-1** — ceiling break on (2,5) is certified and reproducible.
2. **Queue EXP-next on triple-arity** — either extend menu-growth to a triple-family search (28 → C(8,3)=56 entries) or run Phase C inner-forge and measure saturation vs growth on Target 2.

## References

- `menu_growth.md` — primary Phase B doc (numbers confirmed)
- `structure_discovery.md` — F24 baseline & P7 ceiling
- `menu_growth.zig`, `structure_discovery.zig`
- `inventable_substrate_design.md` — Phase C plan