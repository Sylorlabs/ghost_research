# Swarm fork — quad-arity menu growth (hidden quad 0,4,5,7)

**Date:** 2026-07-05  
**Status:** **PASS** — quad ceiling broken; wall relocates to quint-arity.

## Fork from triple-arity

The triple fork (`swarm_fork_triple_arity.md`) confirmed triple-growth breaks the pair-family bottom and showed the **triple-family bottom** on hidden quad (0,4,5,7): best triple (0,1,2) at **0.503 ≈ chance**, while a hand-built quad-relation inner reached **1.000**.

This fork extends `menu_growth.zig` with the same **discover → certify → promote** loop at **quad arity**, then measures the **next ceiling** on hidden quint (0,1,2,3,6).

## Commands

```bash
cd sparse_poly_discovery
zig build menu-growth --release=fast        # ~2 min (70-quad search)
# or: zig build-exe menu_growth.zig -OReleaseFast -femit-bin=/tmp/ghost_menu_growth && /tmp/ghost_menu_growth
```

Seed fixed: `0x9E3B1D0FA5172C44`. Split: train/val/test = 4500/2250/2250.

## Growable families

| Arity | Family | Search space |
|-------|--------|--------------|
| Pair | `φ(i,j) = [c_i, c_j, c_i·c_j]` | 28 pairs |
| Triple | `φ(i,j,k) = [c_i−μ, c_j−μ, c_k−μ, (c_i−μ)(c_j−μ)(c_k−μ)]` | 56 triples |
| Quad | `φ(i,j,k,l) = [c_i−μ, …, (c_i−μ)(c_j−μ)(c_k−μ)(c_l−μ)]` | 70 quads |

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
  triple-grown menu (fixed+pair+triple):      test 0.499   (chance 0.504)
  DISCOVER best quad = (0,4,5,7)              val 1.000   test 1.000
  CERTIFY escape         PASS   (1.000 ≥ 0.90, triple-menu 0.499 < 0.70)
  CERTIFY irreducible    PASS   (held-out R² = −0.114 < 0.40;
                                 kill-test R² = 1.000 → non-vacuous)
  PROMOTE                       triple-ceiling → 1.000   CEILING BROKEN ✓

TARGET 6 — hidden quint (0,1,2,3,6)   [quad-family ceiling]
  quad-grown menu:                             test 0.506   (chance 0.504)
  best QUAD (grown family) = (0,4,5,6)        test 0.504   → CEILING
  QUINT-relation inner                          test 1.000   → next family escapes
```

## Return fields

| Field | Value |
|-------|-------|
| **Quad ceiling broken** | **Y** — certified quad-selection breaks triple-family bottom (0.503 → **1.000**) |
| **Test acc (hidden quad, post-discovery)** | **1.000** |
| **Next ceiling** | **Quint-arity** — hidden quint (0,1,2,3,6); quad-family best **0.504 ≈ chance**; quint-relation inner **1.000** |

## Verdict

- **Quad ceiling broken: Y.** The forge discovered (0,4,5,7) blind (val-selected), certified escape + irreducibility against the triple-grown menu, and promoted it to **1.000** test accuracy.
- **Wall relocation confirmed.** Each fixed-arity family has its own bottom; growing arity escapes the *named* ceiling without repealing the closure law.
- **Pair and triple results unchanged** from prior forks — no regression on Targets 1–3 numbers.

## Relation to Phase C (`inner_forge.zig`)

`inner_forge` reaches T3 `φ{0,4,5,7}` via **monomial promotion** (mask `0xB1`) in round 3 of the open forge — a different substrate (centered-subset monomials, not pair/triple/quad relation menus). This fork proves the **menu-growth ladder** explicitly: pair → triple → quad → (next) quint, each rung certified the same way Phase B certified pairs.

Phase C's open forge still asks whether **unfixed arity** (monomials + operator menu) saturates in one pass or requires hand-structured arity steps. This run shows arity steps work when the growable family matches the target's degree.

## Honest caveats

- Quad growth is still **selection-with-certification** over a fixed combinatorial family (70 entries), not open-ended primitive invention.
- Irreducibility R² = −0.114 means the triple-grown menu is *worse than chance* at reconstructing the quad cross-term — a strong but *relative* certificate.
- Single seed; separations are clean (0.5/1.0) so seed noise is not load-bearing here.
- Runtime ~2 min on this machine due to 70-quad brute search; pair/triple runs are faster.

## References

- `swarm_fork_triple_arity.md` — triple ceiling break (parent fork)
- `swarm_exp01_menu_growth.md` — EXP-1 pair ceiling break (grandparent)
- `menu_growth.md` — Phase B pair growth doc
- `menu_growth.zig` — extended with Target 5 (quad certify/promote) and Target 6 (quint ceiling)
- `inner_forge.md` — Phase C monomial forge + operator escape
- `boolean_fourier.md` — χ_{0,4,5,7} as the quad character