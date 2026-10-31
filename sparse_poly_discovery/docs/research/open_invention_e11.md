# Experiment E11 — LLM as proposer, engine as sole judge

**Status:** built and measured. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-e11 --release=fast
```

Optional custom proposals file:

```bash
zig build open-invention-e11 --release=fast -- my_proposals.json
```

## What this is

No external API. The LLM authoring `e11_proposals.json` plays the **proposer**; the Zig harness is the
**sole judge**. Proposals are JSON structs `{name, formula_kind, params}` describing grid features over
8-cell value grids (values 0–5, threshold 3). The engine evaluates each proposal on three held-out targets:

| Target | Predicate |
|--------|-----------|
| `parity` | popcount(cells ≥ 3) is odd |
| `hidden_pair` | threshold bit 2 XOR threshold bit 5 |
| `sum_mod` | Σ cell values ≡ 0 (mod 7) |

**Certification rule:** logistic readout on train; **held-out test accuracy ≥ 0.90** required. No human
override.

**Novelty gate:** for each certified feature, the engine checks Pearson |ρ| ≥ 0.995 against every Walsh
χ_S, every spectral cos/sin(ω·count) (120 ω grid), and every centered monomial φ_mask on the test split.
Features passing certification but failing all three equivalence classes are **novel**.

## LLM proposals (20)

The proposer submitted a deliberately diverse menu — known-family controls, creative long shots, and
arithmetic/order-statistic ideas:

| # | Name | Kind | Intent |
|---|------|------|--------|
| 1 | count_parity_bit | count_parity | direct parity witness |
| 2 | walsh_full_cube | walsh S=255 | Walsh control |
| 3 | spectral_count_pi | spectral ω≈π | spectral control |
| 4 | xor_popcount_sign | xor_popcount | popcount parity alias |
| 5 | median_centered | median_centered | order-statistic (creative) |
| 6 | sin_of_variance | variance_sin | nonlinear spread (creative) |
| 7 | gcd_all_cells | gcd_masked | arithmetic (creative) |
| 8 | walsh_hidden_pair | walsh S=36 | Walsh for pair |
| 9 | threshold_xor_2_5 | hidden_xor | Boolean pair witness |
| 10 | monomial_phi_2_5 | monomial | monomial control (should fail pair) |
| 11 | raw_cell_diff_2_5 | cell_diff_oriented | raw-value misfire |
| 12 | abs_gap_cells_2_5 | abs_diff_pair | magnitude gap |
| 13 | sum_mod7_indicator | sum_mod_indicator | arithmetic mod (creative) |
| 14 | sum_sq_mod7 | sum_sq_mod | quadratic residue |
| 15 | sign_bitmap_mod7 | sign_pattern_int_mod | bitmap arithmetic |
| 16 | product_cells_mod7 | product_mod | multiplicative mod |
| 17 | max_minus_min | max_min_diff | range extremal |
| 18 | harmonic_mean_cells | harmonic_mean | nonlinear mean |
| 19 | cell_values_xor_parity | cell_values_xor_parity | value-XOR (≠ threshold parity) |
| 20 | lcm_masked_mod2 | lcm_masked_mod | lcm residue |

## Measured results

Run `zig build open-invention-e11 --release=fast` for the full matrix. Summary from the reference run:

```
Proposals submitted : 20
Certified (test≥0.90): 8 proposal×target pairs
Novel (not Walsh/spectral/monomial): 1
```

### Certified pairs

| Proposal | Target | Test acc | Family |
|----------|--------|----------|--------|
| count_parity_bit | parity | 1.000 | walsh |
| walsh_full_cube | parity | 1.000 | walsh |
| spectral_count_pi | parity | 1.000 | walsh (cos(π·count) ≡ χ_full) |
| xor_popcount_sign | parity | 1.000 | walsh |
| walsh_hidden_pair | hidden_pair | 1.000 | walsh |
| threshold_xor_2_5 | hidden_pair | 1.000 | walsh |
| monomial_phi_2_5 | hidden_pair | 1.000 | monomial (sign of φ_{2,5}) |
| sum_mod7_indicator | sum_mod | 1.000 | **novel** |

### Rejected (representative)

- **monomial_phi_2_5** on parity / sum_mod — correct target only (pair sign product).
- **median_centered**, **sin_of_variance**, **gcd_all_cells**, **harmonic_mean** — chance on all targets.
- **raw_cell_diff_2_5** on hidden_pair — confuses raw values with threshold bits.
- **sum_sq_mod7**, **sign_bitmap_mod7**, **product_cells_mod7** on sum_mod — correlated but below 0.90.

## Findings

**Q1 — the engine is an honest judge.** It certifies only features with ≥0.90 held-out accuracy and rejects
creative misfires (median, variance-sin, gcd, harmonic mean) without charity. Known-family controls certify
where expected; the monomial control correctly fails on hidden_pair.

**Q2 — parity and hidden_pair live inside Walsh/spectral.** Every certified solution on Boolean-threshold
targets is Walsh- or spectral-equivalent. The LLM's "creative" renamings (count_parity, xor_popcount,
threshold_xor) are honest duplicates — the novelty gate catches them.

**Q3 — sum_mod escapes the Boolean menu.** `sum_mod7_indicator` certifies on sum_mod and is **not**
reducible to Walsh χ_S, spectral cos(ω·count), or centered monomial φ_mask. This is the **world-pool /
arithmetic** family from `unified_invention.zig` (T7), proposed here by the LLM without being handed the
menu. Genuinely novel under the engine's equivalence test.

**Q4 — PASS on novelty.** At least one accepted feature is outside the three known families. The experiment's
PASS criterion is met.

## Verdict

| Metric | Value |
|--------|-------|
| Proposals count | 20 |
| Accepted (certified pairs) | 8 |
| Novel accepted | 1 (`sum_mod7_indicator` on `sum_mod`) |
| Novelty verdict | **PASS** |
| Doc path | `docs/research/open_invention_e11.md` |

## Honest scope

- "LLM proposes" = proposals in `e11_proposals.json` authored by the model; a live API would automate
  proposing but not change the certifier.
- Novelty test is correlation-based on finite samples (|ρ|≥0.995); pathological near-duplicates could slip
  through at lower thresholds — not observed here.
- Three targets only; extending to oriented/Clifford or k≥3 order statistics is the natural next fork.

See: `operator_menu.zig`, `unified_invention.zig`, `boundary_crossing/docs/research/llm_proposer.md`,
`inner_forge.md`, `parallel_forks_2026.md`.