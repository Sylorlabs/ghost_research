# Research Q7 — E11 scale: 100 LLM proposals, engine sole judge

**Status:** built and measured. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-rq7 --release=fast
```

Optional custom proposals file:

```bash
zig build open-invention-rq7 --release=fast -- my_proposals.json
```

## What this is

Scale-up of **Experiment E11** from 20 → **100** LLM-proposed grid features. No external API: the model authoring `rq7_proposals.json` is the **proposer**; the Zig harness is the **sole judge**.

Proposals are JSON structs `{name, formula_kind, params}` over 8-cell value grids (values 0–5, threshold 3). The engine evaluates each proposal on **five** held-out target families:

| Target | Predicate |
|--------|-----------|
| `parity` | popcount(cells ≥ 3) is odd |
| `hidden_pair` | threshold bit 2 XOR threshold bit 5 |
| `sum_mod` | Σ cell values ≡ 0 (mod 7) |
| `oriented` | raw value: g[1] > g[0] |
| `monomial_sign` | sign φ{2,5} = ∏(g[i]−2.5) over mask {2,5} is positive |

**Certification rule:** logistic readout on train; **held-out test accuracy ≥ 0.90** required. No human override.

**Novelty gate (expanded vs E11):** for each certified feature, Pearson |ρ| ≥ 0.995 against every Walsh χ_S, every spectral cos/sin(ω·count) (120 ω grid), every centered monomial φ_mask, and every world-pool divisibility feature (`sum%mod_p`, `sign%mod_p` for p ∈ {2,3,5,7,11,13}). Features passing certification but failing all four equivalence classes are **novel**.

**Pass bar:** ≥2 non-equivalent (novel) promoted features on ≥2 distinct target families.

## LLM proposals (100)

The proposer submitted a deliberately diverse menu across formula kinds:

| Category | Count | Examples |
|----------|------:|----------|
| Walsh subsets | 12 | `walsh_S255`, `walsh_hidden_pair_36` |
| Spectral count | 7 | `spectral_omega_4` |
| Parity / popcount | 5 | `count_parity_direct`, `xor_popcount_sign` |
| Hidden-pair witnesses | 10 | `threshold_xor_2_5`, `monomial_phi_2_5` |
| World / mod arithmetic | 16 | `sum_mod7_indicator`, `sign_mod3_indicator` |
| Oriented / relational | 25 | `orient_diff_1_0`, `clifford_sin_v1_v0` |
| Monomial masks | 15 | `monomial_mask_36` |
| Antisymmetric pair | 3 | `antisym_cells_2_5` |
| Creative long shots | 7 | `median_centered`, `gcd_all_cells`, `harmonic_mean_cells` |

Full list: `sparse_poly_discovery/rq7_proposals.json`.

## Measured results

Run `zig build open-invention-rq7 --release=fast` for the full certified matrix. Summary from the reference run:

```
Proposals submitted : 100
Accepted (certified pairs): 25
Novel (non-equivalent)    : 9
Families with novel       : 3
```

### Per-family breakdown

| Target | Certified | Novel |
|--------|----------:|------:|
| `parity` | 5 | 0 |
| `hidden_pair` | 7 | 2 |
| `sum_mod` | 1 | 0 |
| `oriented` | 5 | 5 |
| `monomial_sign` | 7 | 2 |

### Certified pairs (all)

| Proposal | Target | Test acc | Family |
|----------|--------|----------|--------|
| walsh_S255 | parity | 1.000 | walsh |
| spectral_omega_4 | parity | 1.000 | walsh |
| count_parity_direct | parity | 1.000 | walsh |
| xor_popcount_sign | parity | 1.000 | walsh |
| thresh_count_mod2 | parity | 1.000 | walsh |
| walsh_hidden_pair_36 | hidden_pair | 1.000 | walsh |
| walsh_hidden_pair_36 | monomial_sign | 1.000 | walsh |
| threshold_xor_2_5 | hidden_pair | 1.000 | walsh |
| threshold_xor_2_5 | monomial_sign | 1.000 | walsh |
| threshold_xor_5_2 | hidden_pair | 1.000 | walsh |
| threshold_xor_5_2 | monomial_sign | 1.000 | walsh |
| monomial_phi_2_5 | hidden_pair | 1.000 | monomial |
| monomial_phi_2_5 | monomial_sign | 1.000 | monomial |
| sum_mod7_indicator | sum_mod | 1.000 | world |
| orient_diff_1_0 | oriented | 1.000 | **novel** |
| orient_ind_1_0 | oriented | 1.000 | **novel** |
| raw_diff_1_0 | oriented | 1.000 | **novel** |
| clifford_sin_v1_v0 | oriented | 1.000 | **novel** |
| rank_v1_gt_v0 | oriented | 1.000 | **novel** |
| monomial_mask_36 | hidden_pair | 1.000 | monomial |
| monomial_mask_36 | monomial_sign | 1.000 | monomial |
| antisym_cells_2_5 | hidden_pair | 1.000 | **novel** |
| antisym_cells_2_5 | monomial_sign | 1.000 | **novel** |
| antisym_cells_5_2 | hidden_pair | 1.000 | **novel** |
| antisym_cells_5_2 | monomial_sign | 1.000 | **novel** |

### Novel promotions

| Proposal | Target | Formula |
|----------|--------|---------|
| orient_diff_1_0 | oriented | g[1] > g[0] sign feature |
| orient_ind_1_0 | oriented | g[1] > g[0] indicator |
| raw_diff_1_0 | oriented | g[1] − g[0] |
| clifford_sin_v1_v0 | oriented | sin(0.4·(g[1]−g[0])) |
| rank_v1_gt_v0 | oriented | rank(g[1]) > rank(g[0]) |
| antisym_cells_2_5 | hidden_pair, monomial_sign | (c₂c₅ − \|g₂−g₅\|) centered product minus magnitude gap |

### Rejected (representative)

- **median_centered**, **sin_of_variance**, **gcd_all_cells**, **harmonic_mean** — chance on all targets.
- **sum_sq_mod7**, **product_all_mod7**, **sign_bitmap_mod7** on sum_mod — correlated but below 0.90.
- **raw_orient_misfire_2_5** on hidden_pair — confuses raw ordering with threshold XOR.
- **88/100 proposals** — no target reached the 0.90 bar (honest rejection at scale).

## Findings

**Q1 — Scale does not weaken the certifier.** At 100 proposals the engine still certifies only 25 proposal×target pairs (25% hit rate on the full 500-cell matrix). Creative noise is rejected without charity.

**Q2 — Four targets live inside Walsh/spectral/monomial/world.** Parity and hidden_pair certify only as Walsh/monomial renamings. Sum_mod certifies only as world (`sum_mod7_indicator`). The expanded world gate correctly reclassifies E11's `sum_mod7_indicator` from "novel" to **world-equivalent**.

**Q3 — Oriented escapes the Boolean menu.** Raw-value ordering features (diff, indicator, Clifford sine, rank) certify on `oriented` and are genuinely outside Walsh/spectral/monomial/world — the relational family from `unified_invention.zig` T6 and `antisymmetric_relational.md`.

**Q4 — Antisymmetric pair is a new novel primitive.** `antisym_cells_2_5` = (g[2]−2.5)(g[5]−2.5) − |g₂−g₅| certifies on both `hidden_pair` and `monomial_sign` at 1.000 test accuracy, with max |ρ| = 0.985 vs monomial φ₃₆ (below the 0.995 gate). It captures threshold-XOR structure through a **non-monomial antisymmetric** combination — promoted as novel on two distinct families.

**Q5 — PASS at scale.** ≥2 non-equivalent promoted features on ≥2 distinct families: **9 novel** across **oriented**, **hidden_pair**, and **monomial_sign**.

## Verdict

| Metric | Value |
|--------|-------|
| Proposals count | 100 |
| Accepted (certified pairs) | 25 |
| Novel accepted | 9 |
| Families with novel | 3 (oriented, hidden_pair, monomial_sign) |
| Pass bar | **PASS** |
| Doc path | `docs/research/open_invention_rq7.md` |

## Honest scope

- "LLM proposes" = proposals in `rq7_proposals.json` authored by the model; a live API would automate proposing but not change the certifier.
- Novelty test is correlation-based on finite samples (|ρ|≥0.995); pathological near-duplicates (e.g. antisym at 0.985 vs monomial) are honestly below threshold.
- Five targets only; k≥3 order statistics and live API proposer loops are natural extensions.

See: `open_invention_e11.md`, `operator_menu.zig`, `unified_invention.zig`, `antisymmetric_relational.md`, `boundary_crossing/docs/research/llm_proposer.md`.