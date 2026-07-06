# Swarm fork — triple-arity menu growth (hidden triple 1,3,6)

**Date:** 2026-07-05  
**Status:** **PASS** — triple ceiling broken; wall relocates to quad-arity.

## Fork from EXP-1

EXP-1 (`swarm_exp01_menu_growth.md`) confirmed pair-growth breaks the F24 hidden-pair ceiling and showed the **pair-family bottom** on hidden triple (1,3,6): best pair (3,5) at **0.501 ≈ chance**, while a hand-built triple-relation inner reached **1.000**.

This fork extends `menu_growth.zig` with the same **discover → certify → promote** loop at **triple arity**, then measures the **next ceiling** on hidden quad (0,4,5,7).

## Commands

```bash
cd sparse_poly_discovery
zig build-exe menu_growth.zig -OReleaseFast -femit-bin=/tmp/ghost_menu_growth && /tmp/ghost_menu_growth
# or: zig build menu-growth --release=fast   # if full build graph is clean
```

Seed fixed: `0x9E3B1D0FA5172C44`. Split: train/val/test = 4500/2250/2250.

## Growable families

| Arity | Family | Search space |
|-------|--------|--------------|
| Pair | `φ(i,j) = [c_i, c_j, c_i·c_j]` | 28 pairs |
| Triple | `φ(i,j,k) = [c_i−μ, c_j−μ, c_k−μ, (c_i−μ)(c_j−μ)(c_k−μ)]` | 56 triples |

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
  pair-grown menu (fixed+pair):               test 0.513   (chance 0.513)
  DISCOVER best triple = (1,3,6)              val 1.000   test 1.000
  CERTIFY escape         PASS   (1.000 ≥ 0.90, pair-menu 0.513 < 0.70)
  CERTIFY irreducible    PASS   (held-out R² = −0.038 < 0.40;
                                 kill-test R² = 1.000 → non-vacuous)
  PROMOTE                       pair-ceiling → 1.000   CEILING BROKEN ✓

TARGET 4 — hidden quad (0,4,5,7)   [triple-family ceiling]
  triple-grown menu:                           test 0.499   (chance 0.504)
  best TRIPLE (grown family) = (0,1,2)         test 0.503   → CEILING
  QUAD-relation inner                           test 1.000   → next family escapes
```

## Return fields

| Field | Value |
|-------|-------|
| **Triple ceiling broken** | **Y** — certified triple-selection breaks pair-family bottom (0.501 → **1.000**) |
| **Test acc (hidden triple, post-discovery)** | **1.000** |
| **Next ceiling** | **Quad-arity** — hidden quad (0,4,5,7); triple-family best **0.503 ≈ chance**; quad-relation inner **1.000** |

## Verdict

- **Triple ceiling broken: Y.** The forge discovered (1,3,6) blind (val-selected), certified escape + irreducibility against the pair-grown menu, and promoted it to **1.000** test accuracy.
- **Wall relocation confirmed.** Each fixed-arity family has its own bottom; growing arity escapes the *named* ceiling without repealing the closure law.
- **Pair results unchanged** from EXP-1 — no regression on Target 1 numbers.

## Relation to Phase C (`inner_forge.zig`)

`inner_forge` reaches T2 `φ{1,3,6}` via **monomial promotion** (mask `0x4A`) in round 1 of the open forge — a different substrate (centered-subset monomials, not pair/triple relation menus). This fork proves the **menu-growth ladder** explicitly: pair → triple → (next) quad, each rung certified the same way Phase B certified pairs.

Phase C's open forge still asks whether **unfixed arity** (monomials + operator menu) saturates in one pass or requires hand-structured arity steps. This run shows arity steps work when the growable family matches the target's degree.

## Honest caveats

- Triple growth is still **selection-with-certification** over a fixed combinatorial family (56 entries), not open-ended primitive invention.
- Irreducibility R² = −0.038 means the pair-grown menu is *worse than chance* at reconstructing the triple cross-term — a strong but *relative* certificate.
- Single seed; separations are clean (0.5/1.0) so seed noise is not load-bearing here.

## References

- `swarm_exp01_menu_growth.md` — EXP-1 pair ceiling break (parent fork)
- `menu_growth.md` — Phase B pair growth doc
- `menu_growth.zig` — extended with Target 3 (triple certify/promote) and Target 4 (quad ceiling)
- `inner_forge.md` — Phase C monomial forge + operator escape
- `boolean_fourier.md` — χ_{1,3,6} as the triple character; χ_{0,4,5,7} as quad