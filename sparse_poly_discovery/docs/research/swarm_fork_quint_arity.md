# Swarm fork — quint-arity menu growth (hidden quint 0,1,2,3,6)

**Date:** 2026-07-05  
**Status:** **PASS** — quint ceiling broken; wall relocates to sextuple-arity.

## Fork from quad-arity

The quad fork (`swarm_fork_quad_arity.md`) confirmed quad-growth breaks the triple-family bottom and showed the **quad-family bottom** on hidden quint (0,1,2,3,6): best quad (0,4,5,6) at **0.504 ≈ chance**, while a hand-built quint-relation inner reached **1.000**.

This fork extends `menu_growth.zig` with the same **discover → certify → promote** loop at **quint arity** (Target 7), completing the ladder through degree-5.

## Commands

```bash
cd sparse_poly_discovery
zig build menu-growth --release=fast        # ~5 s (56-quint search)
# or: zig build-exe menu_growth.zig -OReleaseFast -femit-bin=/tmp/ghost_menu_growth && /tmp/ghost_menu_growth
```

Seed fixed: `0x9E3B1D0FA5172C44`. Split: train/val/test = 4500/2250/2250.

## Growable families

| Arity | Family | Search space |
|-------|--------|--------------|
| Pair | `φ(i,j) = [c_i, c_j, c_i·c_j]` | 28 pairs |
| Triple | `φ(i,j,k) = [c_i−μ, c_j−μ, c_k−μ, (c_i−μ)(c_j−μ)(c_k−μ)]` | 56 triples |
| Quad | `φ(i,j,k,l) = [c_i−μ, …, (c_i−μ)(c_j−μ)(c_k−μ)(c_l−μ)]` | 70 quads |
| Quint | `φ(i,j,k,l,m) = [c_i−μ, …, (c_i−μ)(c_j−μ)(c_k−μ)(c_l−μ)(c_m−μ)]` | 56 quints |

Certification (same discipline as Phase B):

1. **Discover** — argmax validation accuracy over the family.
2. **Certify escape** — held-out test ≥ 0.90 where the prior menu sat < 0.70.
3. **Certify irreducibility** — new cross-term held-out R² < 0.40 from prior menu; kill-test (append cross-term → R² > 0.90).
4. **Promote** — add certified inner to menu.

## Results (fresh run)

```
TARGET 1 — hidden pair (2,5)   [F24 ceiling: 0.591]
  DISCOVER best pair = (2,5)                  test 1.000
  PROMOTE                       ceiling 0.591 → 1.000   CEILING BROKEN ✓

TARGET 2 — hidden triple (1,3,6)   [pair-family ceiling]
  best PAIR (grown family) = (3,5)            test 0.501   → CEILING

TARGET 3 — hidden triple (1,3,6)   [certified triple growth]
  DISCOVER best triple = (1,3,6)              val 1.000   test 1.000
  PROMOTE                       pair-ceiling → 1.000   CEILING BROKEN ✓

TARGET 4 — hidden quad (0,4,5,7)   [triple-family ceiling]
  triple-grown menu:                           test 0.499   (chance 0.504)
  best TRIPLE (grown family) = (0,1,2)       test 0.503   → CEILING
  QUAD-relation inner                           test 1.000   → next family escapes

TARGET 5 — hidden quad (0,4,5,7)   [certified quad growth]
  DISCOVER best quad = (0,4,5,7)              val 1.000   test 1.000
  PROMOTE                       triple-ceiling → 1.000   CEILING BROKEN ✓

TARGET 6 — hidden quint (0,1,2,3,6)   [quad-family ceiling]
  quad-grown menu:                             test 0.506   (chance 0.504)
  best QUAD (grown family) = (0,4,5,6)        test 0.504   → CEILING
  QUINT-relation inner                          test 1.000   → next family escapes

TARGET 7 — hidden quint (0,1,2,3,6)   [certified quint growth]
  quad-grown menu (fixed+pair+triple+quad):   test 0.506   (chance 0.504)
  DISCOVER best quint = (0,1,2,3,6)          val 1.000   test 1.000
  CERTIFY escape         PASS   (1.000 ≥ 0.90, quad-menu 0.506 < 0.70)
  CERTIFY irreducible    PASS   (held-out R² = −0.269 < 0.40;
                                 kill-test R² = 1.000 → non-vacuous)
  PROMOTE                       quad-ceiling → 1.000   CEILING BROKEN ✓
```

## Return fields

| Field | Value |
|-------|-------|
| **Quint ceiling broken** | **Y** — certified quint-selection breaks quad-family bottom (0.504 → **1.000**) |
| **Promoted** | **Y** — hidden quint (0,1,2,3,6) discovered blind, certified, promoted |
| **Test acc (hidden quint, post-discovery)** | **1.000** |
| **Quad-menu baseline (Target 7)** | **0.506** (chance 0.504) |
| **Irreducibility R²** | **−0.269** (kill-test **1.000**) |
| **Next ceiling** | **Sextuple-arity** — on NCELL=8, degree-6 is the full grid character; the ladder saturates at arity 8 |

## Verdict

- **Quint ceiling broken: Y.** The forge discovered (0,1,2,3,6) blind (val-selected), certified escape + irreducibility against the quad-grown menu, and promoted it to **1.000** test accuracy.
- **Wall relocation confirmed through five arity steps.** Each fixed-arity family has its own bottom; growing arity escapes the *named* ceiling without repealing the closure law.
- **Pair, triple, and quad results unchanged** from prior forks — no regression on Targets 1–5 numbers.

## Relation to Phase C (`inner_forge.zig`)

`inner_forge` reaches monomial targets via **mask promotion** in the open forge — a different substrate (centered-subset monomials, not pair/triple/quad/quint relation menus). This fork proves the **menu-growth ladder** explicitly: pair → triple → quad → quint, each rung certified the same way Phase B certified pairs.

On NCELL=8, quint is the last nontrivial arity step before the full-grid character (degree 8). Phase C's open forge still asks whether **unfixed arity** (monomials + operator menu) saturates in one pass or requires hand-structured arity steps. This run shows arity steps work when the growable family matches the target's degree.

## Honest caveats

- Quint growth is still **selection-with-certification** over a fixed combinatorial family (56 entries), not open-ended primitive invention.
- Irreducibility R² = −0.269 means the quad-grown menu is *worse than chance* at reconstructing the quint cross-term — a strong but *relative* certificate.
- Single seed; separations are clean (0.5/1.0) so seed noise is not load-bearing here.
- Runtime ~5 s on this machine (56-quint brute search atop prior targets).

## References

- `swarm_fork_quad_arity.md` — quad ceiling break (parent fork)
- `swarm_fork_triple_arity.md` — triple ceiling break (grandparent)
- `swarm_exp01_menu_growth.md` — EXP-1 pair ceiling break
- `menu_growth.md` — Phase B pair growth doc
- `menu_growth.zig` — extended with Target 7 (quint certify/promote) and Target 6 (quint ceiling demo)
- `inner_forge.md` — Phase C monomial forge + operator escape
- `boolean_fourier.md` — χ_S characters at each arity