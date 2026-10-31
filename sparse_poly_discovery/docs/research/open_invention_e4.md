# EXPERIMENT E4 — certified menu minting (program synthesizer)

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-e4 --release=fast
# or: zig build-exe open_invention_e4.zig -OReleaseFast && ./open_invention_e4
```

(~20 s, seed-pinned `0xE4CE11ED0FF1CE42`)

## What it does

Phase C (`inner_forge.zig`) promoted **fixed-shape** inner transforms (monomial subsets).
E4 asks: can a **program synthesizer** mint **opaque** grid→scalar primitives from a small VM,
with the same certifier (escape ≥0.90 held-out + irreducible R²<0.40)?

**VM (no cos):** `cell[i]`, `thresh`, `compare(>)`, `mul`, `add`, `sum`, `parity`, `min`, `max`, `rank_k`.

**Search:** all expression trees depth ≤5 over those ops (4096 candidates after dedup).

**Base menu:** 8 singleton cells only (minimal — no aggregates/composites handed in).

**Targets:** 20 generated hard predicates (depth≥3 VM programs whose base-menu test accuracy <0.70).

**Loop:** for each unsolved target, synthesize best program (correlation prefilter → logit val),
certify escape + irreducible, promote as opaque primitive, recount joint coverage.

## Results (2026-06-29 run)

```
VM depth≤5: 4096 candidates, 4077 compositional roots
Base menu (8 cells): 0/20 solved (all test ≈0.51–0.65)

round 1:
  G00 → mint (sum*parity)           escape 1.00  R²=0.02  [composed_known]
  G06 → mint ((c0+c0)*(rank_6>rank_5))  escape 1.00  R²=0.21  [genuinely_new*]

round 2: saturated (no further certified promotions)

Final: 18/20 solved at library size 10 (+2 minted)
Unsolved: G17 (0.90), G19 (0.90) — at certification floor, forge stopped

library size vs solve rate:
  lib=08   0/20   0.0%
  lib=10  18/20  90.0%
```

\* `genuinely_new` = behavioral matcher did not match a simple 1–2 leaf template; **not** “outside VM closure.”

## Verdict

**POSITIVE (bounded).** Certified menu minting works: 2 opaque synthesized primitives lift
solve rate **0% → 90%** from a minimal cell-only menu. The synthesizer finds real escapes
(`sum*parity`, rank-compare compositions) the fixed menu lacked.

**Saturation in 1 forge round** after 2 promotions — replicates the unified ceiling:
the VM is a **fixed closure**; minting **composes** inside it, does not import new generators.

### Are minted programs genuinely new?

| Program | Behavioral family tag | Structural reality |
|---|---|---|
| `(sum*parity)` | `composed_known` | Product of two VM leaves — parity-of-count family |
| `((c0+c0)*(rank_6>rank_5))` | `genuinely_new`* | Still a depth-3 VM tree: add + compare + mul |

**Conclusion:** Both promoted programs are **equivalent to known VM families** (count/parity,
rank-compare, affine cell, product). None use generators outside the substrate (no cos/Walsh/monomial
forge). Minting produces **opaque menu entries** — useful, certified, irreducible to the *current*
library — but **not** algebraic novelty outside the VM. This is selection-with-certification over
a compositional substrate, consistent with `menu_growth.md` and `inventable_substrate_design.md`.

The 2 remaining targets sit at the 0.90 certification floor; the forge correctly refuses
under-certified promotions rather than overfitting.

## Honest caveats

- **Relative irreducibility** (R²<0.40 vs current library), not absolute irreducibility to all VM programs.
- **Hard-target filter** requires 1200 random draws to fill 20 targets; seed-pinned but not exhaustive.
- **Joint coverage** after 2 mints solves 18/20 — most targets need no target-specific primitive
  once the library gains parity/rank-compare expressiveness (library composition effect).

## See

`inner_forge.zig`, `menu_growth.zig`, `open_invention_e3.zig` (no-spectral ablation),
`inventable_substrate_design.md`, repo-root `CLOSURE_PRINCIPLE.md`.