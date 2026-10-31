# EXPERIMENT E26 — Equivalence tax v2 (RQ9++)

**Status:** built, measured, re-verified 2026-07-05. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-e26 --release=fast
```

(~85 s, ReleaseFast)

## What this tests

RQ9 v1 asked whether 6 certified escapes (E3/E4/E5/E11) live inside
**monomial + Walsh + world + VM**. E26 expands the tax collector and the escape battery:

> With **mod synthesis**, **xor_popcount**, and **composed pipelines** added to the basis,
> what fraction of **all E1–E12 grid-certified escapes** are still reproducible on held-out grids?

Pass bar (relaxed from RQ9's 30%): **<40% reproducible** → genuine invention outside expanded closure.

## Basis v2 (expanded tax collector)

| Family | Contents |
|--------|----------|
| Monomial | centered φ_S, deg 1–4 (255 masks) |
| Walsh | χ_S for all 256 sign-pattern subsets |
| World | `sum(g)%p` and `sign(g)%p` for p ∈ {2,3,5,7,11,13} |
| VM | expression trees depth ≤6 |
| **xor_popcount** | `popcount(XOR_masked_cells) & 1` for all 255 masks (E2/RQ2) |
| **mod synthesis** | depth≤3 programs over {count₂,count₃,count₄,inv,sum} + sin/mod (E3/RQ3/E14) |
| **pipelines** | E5 inner₁→inner₂ scalar features (7×7 = 49 combos) |

**Still excluded:** spectral cos(ω·count) as a named menu family (scan_p uses fixed ω in pipeline scalars).

## Escapes under test (20)

| Group | Count | Notes |
|-------|-------|-------|
| RQ9 core | 6 | E3 parity, E4 G00/G06, E5 F-A/F-B, E11 sum_mod7 |
| E1 battery B | 11 | seed-pinned masks (0xE1B10D20A11CE01); B1=0x0C, B2=0x2A |
| E2 XOR | 2 | oracle-only survivors XOR(0x0F), parity(XOR 0x33) |
| E12 order-stat | 1 | rank2(0,1,2)==1 |

**Excluded (no grid escape):** E6 (0/16 aliens), E7 (+0 lift), E8 (terminal), E9 (0 transfer), E10 (novelty zoo).

## Search protocol

Same as RQ9 except prefilter expanded to top **128**/round:

- Train: 7000 grids (seed `0xF0235A11CE0FF1CE`)
- Held-out test: 3500 grids (seed `0xE957E5700002`)
- Budget: ≤8 greedy features; reproducible = test ≥0.90

## Measured results (2026-07-05 re-run; matches 2026-06-30)

```
Candidates: 778 static + 8342 extra = 9120 total

┌────────────────────────────────┬────────┬──────────┬─────────────┬──────────────┐
│ Escape                         │ Source │ Test acc │ Reproducible│ Basis winner │
├────────────────────────────────┼────────┼──────────┼─────────────┼──────────────┤
│ E3-parity                      │ E3     │ 1.000    │ YES         │ χ(0xFF)      │
│ E4-G00 (sum*parity mint)       │ E4     │ 0.463    │ NO          │ VM tree      │
│ E4-G06 (rank-compare mint)     │ E4     │ 1.000    │ YES         │ φ(0x01)      │
│ E5-F-A (inversion-parity)      │ E5     │ 0.952    │ YES         │ synth#105    │
│ E5-F-B (sum-then-bind)         │ E5     │ 1.000    │ YES         │ χ(0x03)      │
│ E11 (sum_mod7_indicator)       │ E11    │ 0.930    │ YES         │ sum%mod_3    │
│ E1-B1..B11 (battery)           │ E1     │ ≥0.93    │ 11/11 YES   │ Walsh/world/VM │
│ E2 XOR(mask=0x0F)&1            │ E2     │ 1.000    │ YES         │ xor_pop(0x0F)│
│ E2 parity(XOR 0x33)            │ E2     │ 0.746    │ NO          │ VM cmp tree  │
│ E12 rank2(0,1,2)==1            │ E12    │ 0.793    │ NO          │ VM tree      │
└────────────────────────────────┴────────┴──────────┴─────────────┴──────────────┘
```

| Metric | Value |
|--------|-------|
| Escapes tested | **20** |
| Reproducible | **17/20 (85.0%)** |
| RQ9 v1 baseline | 4/6 (67%) |
| Pass bar | <40% reproducible |
| **Verdict** | **FAIL** — expanded basis covers most escapes |

## Novel survivors (3)

1. **E4-G00 (0.463)** — seed-pinned hard VM mint; val-perfect fits do not generalize to held-out grids.
2. **E2 parity(XOR 0x33) (0.746)** — parity-on-XOR-transform; xor_popcount alone insufficient (mask 0x33 direct read fails test).
3. **E12 rank2==1 (0.793)** — order-statistic on triple; pipelines/mod-synth do not reach 0.90 within budget.

## Interpretation

### What the expanded basis closes (vs RQ9 v1)

| Escape | RQ9 v1 | E26 v2 | Mechanism |
|--------|--------|--------|-----------|
| E5-F-A inversion-parity | NO (0.508) | **YES (0.952)** | mod synthesis + inversion→half_p pipeline |
| E2 XOR(0x0F) | N/A | **YES (1.000)** | xor_popcount(0x0F) |
| E11 sum_mod7 | YES (0.936) | YES (0.930) | world pool + mod synth |

### What stays novel even under v2

Hard mints (E4-G00), parity-on-transform XOR (E2), and k≥3 order stats (E12) survive the expanded tax — the honest **outside-closure** candidates after adding synthesis, GF(2) readout, and pipelines.

## Verdict

| Criterion | Result |
|-----------|--------|
| Reproducibility rate | **85.0%** |
| Pass bar (<40%) | **FAIL** |
| Novel survivors | E4-G00, E2 parity_xor, E12 rank2 |
| Doc path | `sparse_poly_discovery/docs/research/open_invention_e26.md` |

**Conclusion:** Equivalence tax v2 **fails** the <40% bar. Expanding the basis from RQ9 to include mod synthesis, xor_popcount, and pipelines **increases** coverage (67%→85% on overlapping escapes; E5-F-A and E2 XOR now reproducible). The three survivors are the refined list of "real invention outside the designed menu."

## See also

`open_invention_e26.zig`, `open_invention_rq9.zig` (v1), `open_invention_e14.zig`,
`open_invention_e5.zig`, `open_invention_rq2.zig`, `docs/research/open_invention_rq9.md`.