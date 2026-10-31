# Swarm EXP-3 — Clifford bivector on genuinely relational predicates

**Date:** 2026-07-05  
**Status:** **COMPLETE** — three frontiers re-run + focal-pair battery added.

## Commands

```bash
cd sparse_poly_discovery && zig build clifford-relational          # ~36 s (ReleaseFast default)
cd sparse_poly_discovery && zig build antisymmetric-relational     # ~3 s
cd sparse_poly_discovery && zig build oriented-control             # ~7 s
cd sparse_poly_discovery && zig build relational-binding-battery   # ~6 s
```

Build defaults to `ReleaseFast` via `build.zig` (`preferred_optimize_mode = .ReleaseFast`).

## Question

Does Clifford's grade-2 (bivector) beat plain `product(i,j)` on **genuinely relational** predicates — not symmetric mass/sum?

Prior deflations (`clifford_binding.md`, Frontier 1) tied Clifford to real pairwise on symmetric tasks. The untested prediction (`antisymmetric_relational.md`): Clifford wins **only** when the predicate is antisymmetric and encoding uses a **shared basis**.

## Harness 1 — `clifford-relational` (symmetric XOR, random per-cell roles)

Predicate: `(cell0≥3) XOR (cell1≥3)` — needs pairwise interaction, not sum.  
Encoding: random Cl(7,0) rotor roles per cell; second-order = Σ geo(Cᵢ,Cⱼ) vs Σ (Cᵢ⊙Cⱼ).

| encoding | test acc | second-order via |
|----------|----------|------------------|
| bundle only Σ Cᵢ | **0.455** | none (near chance) |
| Clifford pairwise +Σ geo(Cᵢ,Cⱼ) | **0.998** | geometric product |
| MAP real pairwise +Σ (Cᵢ⊙Cⱼ) | **1.000** | elementwise product |
| ground truth [b0,b1,b0·b1] | **1.000** | explicit interaction |

**Verdict:** DEFLATION. Clifford does **not** beat plain real pairwise on symmetric relational XOR. The lever is **second-order binding**, not the geometric product. XOR needs only the symmetric (grade-0 / dot) part — both substrates expose it when all pairs are summed.

## Harness 2 — `antisymmetric-relational` (oriented, shared Cl(2,0) basis)

Encoding: Cᵢ = cos(θvᵢ)·e₁ + sin(θvᵢ)·e₂ (shared basis).  
Oriented predicate: y = sign(v1−v0). Symmetric sanity: XOR(b0,b1).

### Oriented predicate (chance ≈ 0.577)

| feature | dim | test acc |
|---------|-----|----------|
| bundle Σ Cᵢ | 4 | 0.561 |
| real pairwise sym C0⊙C1 | 4 | **0.583** ← `product(i,j)`-class fails |
| **Clifford grade-2 geo[e12]** | 1 | **1.000** ← WINS |
| first-order ordered [C0;C1] | 8 | 1.000 |
| ground truth sin(θ(v1−v0)) | 1 | 1.000 |

### Symmetric XOR sanity

| feature | test acc |
|---------|----------|
| real pairwise sym | 0.836 |
| Clifford grade-2 | **0.510** (correctly useless) |

**Verdict:** Clifford **wins** on oriented predicate. Grade-2 = sin(θ(v1−v0)) — the antisymmetric feature. Plain symmetric `product(i,j)` / C0⊙C1 is orientation-blind (0.583 ≈ chance).

## Harness 3 — `oriented-control` (real grid TD agent)

Shared Cl(2,0) encoding; compare sum (mb_mass) vs bivector readouts on single-band and dual-band tasks.  
Train 80k / eval 10k / 8 seeds.

### Single-band (symmetric total-mass constraint)

| readout | mean fail/1k |
|---------|--------------|
| **sum(mb_mass)** | **19.80** |
| biv_chain(15) | 50.70 |
| biv_lr_mass / biv_geo_lr | 55.51 |

### Dual-band (left-mass distribution)

| readout | mean fail/1k |
|---------|--------------|
| **sum(mb_mass)** | **35.10** |
| biv_chain(15) | 77.73 |
| biv_lr_mass / biv_geo_lr | 83.30 |

**Verdict:** Clifford bivector readouts **do not beat** sum on the real control task. Oriented dynamics exist in the environment, but failure modes are symmetric mass-band constraints. Explicit `left_mass` scalar (~39 fail/1k in prior harness) beats Clifford bivector here.

## Harness 4 — `relational-binding-battery` (blind focal-pair selector)

Closes gaps: **hidden pair (2,5)**, **oriented pair (0,1)**, **covariance sign (0,1)**.  
Blind argmax on validation over focal-pair substrates:

| substrate | role |
|-----------|------|
| `product_ij` | cᵢ·cⱼ (structure_discovery menu inner) |
| `cliff_biv` | sin(θ(vⱼ−vᵢ)) |
| `cliff_geo_sym` | cos(θ(vᵢ−vⱼ)) |
| `cov_ij` | (cᵢ−μ)(cⱼ−μ) |
| `bundle_ij` | [cᵢ ; cⱼ] |

### Results (test acc)

| predicate | blind pick | product_ij | cliff_biv | best test |
|-----------|------------|------------|-----------|-----------|
| hidden_pair(2,5) | cov_ij | 0.535 | 0.541 | 0.759 (cov_ij) |
| oriented_pair(0,1) | cov_ij | 0.763 | 0.763 | 0.755 (cov_ij) |
| covariance(0,1) | **cov_ij** | 0.505 | 0.505 | **1.000** (cov_ij) |

**Cross-substrate:** `cliff_biv` beats `product_ij` by >0.03 on **any** predicate? **NO**.  
`product_ij` beats `cliff_biv` by >0.03 on **any** predicate? **NO**.

**Interpretation:**
- **Hidden pair (2,5):** focal `product(2,5)` and focal `cliff_biv` both ≈ chance. XOR needs the correct **pair** (menu-growth / pair-selection), not a different binding algebra. `poly2-raw` still cracks it at 1.000 (`structure_discovery.md` P7).
- **Covariance:** centered product `cov_ij` is the exact feature — neither Clifford nor raw product alone suffices.
- **Oriented (focal, 2-dim bundle allowed):** `[c0;c1]` and `cliff_biv` tie (~0.76) because identity is preserved; the 1-dim antisymmetric_relational test is the sharper discrimination.

## Blind selector comparison (substrates across predicates)

| predicate class | best substrate | Clifford bivector vs product(i,j) |
|-----------------|----------------|-----------------------------------|
| Symmetric XOR (full pairwise sum) | real pairwise / MAP | **TIE** (1.000 vs 0.998) |
| Oriented sign(v1−v0) (1-dim) | Clifford grade-2 | **Clifford WINS** (1.000 vs 0.583) |
| Hidden pair XOR (2,5) focal | none at chance | **both FAIL** — need pair discovery |
| Covariance sign | cov_ij centered product | **both FAIL** — need centered product |
| Grid control | sum (mb_mass) | **product/sum WINS** — bivector hurts |

## Does Clifford beat plain product(i,j) on any case?

**YES — one clean case:** antisymmetric / oriented predicates with **shared-basis** encoding and a **1-dimensional** bivector readout (`antisymmetric-relational`: 1.000 vs 0.583).

**NO — on the cases that matter for the menu and control stack:**
- Symmetric relational (XOR): ties or loses to plain pairwise product.
- Hidden pair at focal `(0,1)`: both fail; neither beats the other.
- Real grid control: sum/mass readout dominates.

## Verdict: **KEEP niche / DROP default**

| Scope | Verdict |
|-------|---------|
| **Default relational binding** (vs `product(i,j)`) | **DROP** — second-order binding is the lever; Clifford does not beat plain product on symmetric relational tasks. |
| **Oriented inner in menu** (`oriented(i,j)` = grade-2 sin) | **KEEP** — sole case where Clifford earns its keep; correctly useless on symmetric XOR. |
| **Full Cl(7,0) random-role binding for discovery** | **DROP** — expensive, no gain over real pairwise on relational predicates tested. |

**One-line:** Clifford is not the relational substrate; it is an **oriented inner** for antisymmetric predicates when encoding uses a shared unit circle. Keep `oriented(0,1)` in the menu; do not promote Clifford geometric product as the general replacement for `product(i,j)`.

## Artifacts added

- `relational_binding_battery.zig` — focal-pair blind selector for hidden / oriented / covariance predicates.
- `build.zig` step: `relational-binding-battery`.

## References

- `clifford_binding.md` — mass/sum deflation (Hadamard-R wins)
- `antisymmetric_relational.md` — oriented win prediction (confirmed)
- `structure_discovery.md` — blind selector; hidden pair ceiling at 0.591
- `menu_growth.md` — pair-selection escapes hidden-pair ceiling to 1.000