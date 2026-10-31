# SWARM EXP-5 — RQ9 escape taxonomy (non-reproducible characterization)

**Status:** measured 2026-07-05. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-rq9 --release=fast
```

Harness: `open_invention_rq9.zig` (v1 basis + inline EXP-5 expanded pass).

## Question

RQ9 v1 measured **4/6 escapes reproducible (66.7%)**, failing the **<30% reproducible**
invention bar — only **33.3% non-reproducible**. EXP-5 asks:

1. Which escapes are **false invention** (certified via one route, but already in the basis)?
2. Which v1 failures does an **expanded basis** (mod synthesis + E5 pipelines) recover?
3. What survives as **genuinely novel** after expansion?

## Bases compared

| Pass | Basis families | Candidates |
|------|----------------|------------|
| **v1** | monomial φ_S (deg≤4) + Walsh χ_S + world pool + VM depth≤6 | 523 + 8174 = **8697** |
| **v2 (EXP-5)** | v1 + mod synthesis depth≤3 + E5 pipelines (7×7) | 523 + 8342 = **8865** |

**Excluded from both:** spectral cos(ω·count), xor_popcount (see `open_invention_e26.zig`).

**Search:** greedy forward selection, budget≤8, corr-prefilter top 96/round; reproducible = test ≥0.90.

**Grids:** train seed `0xF0235A11CE0FF1CE` (7000); held-out test seed `0xE957E5700002` (3500).

## Classification taxonomy

| Class | Definition |
|-------|------------|
| **basis-repro** | v1 test ≥0.90 — escape lives in monomial+Walsh+world+VM closure |
| **synthesis-only** | v1 <0.90, v2 ≥0.90, winning model uses `mod_synth` feature |
| **pipeline-only** | v1 <0.90, v2 ≥0.90, winning model uses E5 `pipeline` feature (no synth) |
| **genuinely-novel** | v2 test <0.90 — outside expanded closure within budget |

## Classification table (measured)

| Escape | Source | Certified primitive | v1 test | v1 repro | v2 test | v2 repro | **Taxonomy** | Basis / v2 winner |
|--------|--------|---------------------|---------|----------|---------|----------|--------------|-------------------|
| E3-parity | E3 | `mod(count,2)` | 1.000 | YES | 1.000 | YES | **basis-repro** | χ(0xFF) |
| E4-G00 | E4 | `sum*parity` mint | 0.830 | NO | 0.463 | NO | **genuinely-novel** | (thresh×rank_3) VM |
| E4-G06 | E4 | rank-compare mint | 1.000 | YES | 1.000 | YES | **basis-repro** | φ(0x01) |
| E5-F-A | E5 | inversion→half_p | 0.508 | NO | 0.952 | YES | **synthesis-only** | synth#105 |
| E5-F-B | E5 | sum(c0,c1)→bind_xy | 1.000 | YES | 1.000 | YES | **basis-repro** | χ(0x03) |
| E11 sum_mod7 | E11 | `sum%mod_7` | 0.936 | YES | 0.930 | YES | **basis-repro** | sum%mod_3 |

### Summary counts

| Metric | v1 | v2 (expanded) |
|--------|-----|---------------|
| Reproducible | 4/6 (66.7%) | 5/6 (83.3%) |
| Non-reproducible | 2/6 (**33.3%**) | 1/6 (16.7%) |
| basis-repro | 4 | 4 |
| synthesis-only | 0 | 1 |
| pipeline-only | 0 | 0 |
| genuinely-novel | 2 | 1 |

## Does expanded basis recover v1 failures?

**Partially: 1/2 recovered.**

| v1 failure | v1 test | v2 test | Recovered? | Mechanism |
|------------|---------|---------|------------|-----------|
| E5-F-A inversion-parity | 0.508 | **0.952** | **YES** | mod synthesis `synth#105` (inversion mod 2 program) |
| E4-G00 sum*parity mint | 0.830 | **0.463** | **NO** | val-perfect VM/synth fits; held-out generalization collapses |

E5-F-A was certified via the composed pipeline `inversion→half_p(S mod 2)`. Without synthesis
in the basis, greedy search stalls at ~0.51 test (random for parity). Adding the E3/E14 mod-synth
bank closes the gap: `synth#105` reaches 0.952 — the escape is **honest synthesis routing**, not
a new family outside the designed menu.

E4-G00 is the opposite: expanded basis **hurts** test accuracy (0.830→0.463) because additional
synth candidates distract greedy selection toward val-perfect but non-generalizing features.
The seed-pinned mint `((c0*c0)*(max>thresh))` remains outside both closures.

## Per-escape characterization

### E3-parity — basis-repro (false invention via routing)

- **Certified:** E3 PASS via `mod(count,2)` count synthesis.
- **Tax winner:** Walsh χ(0xFF) in round 1 (v1 and v2).
- **Verdict:** Parity is fully reachable from Walsh; E3 discovered a **routing path** (synthesis)
  to a feature already in the χ_S closure. Contributes to the 67% reproducible rate that **fails**
  the 33% non-reproducible invention bar.

### E11 sum_mod7 — basis-repro (false invention via world pool)

- **Certified:** E11 novel world feature `sum(g)%7==0`.
- **Tax winner:** `sum%mod_3` + `sum%mod_7` family (round 3/7 in v1; round 7 in v2).
- **Verdict:** The "novel" LLM proposal lives in the handed **world pool** `{2,3,5,7,11,13}`.
  E11's Boolean-family novelty gate was correct; the arithmetic escape is basis-redundant.
  Mod synth (`synth#37`, `#43`, …) appears in v2 rounds but does not beat world mod features.

### E4-G06 — basis-repro (mint covered by monomial)

- Seed-pinned rank-compare mint classified by degree-1 monomial φ(0x01) on held-out grids.
- Minted VM tree is behaviorally redundant with a simpler basis atom.

### E5-F-B — basis-repro (pipeline honest but Walsh-equivalent)

- E5 pipeline `sum(c0,c1)→bind_xy` certified the escape; tax finds χ(0x03) directly.
- Composition is real; tax classifies as basis-redundant.

### E5-F-A — synthesis-only (v1 survivor → v2 closed)

- Strongest **v1 invention survivor** (0.508 test).
- Expanded basis recovers via `synth#105` without needing the named pipeline feature in the
  final model (pipeline `inversion→half_p` appears in round 2 but synth wins by round 6).
- Reclassified from genuinely-novel (v1) to **synthesis-only** (v2).

### E4-G00 — genuinely-novel (fork candidate)

- Val-perfect fits (1.000) on all v1/v2 rounds; test stays ≤0.83 (v1) or ≤0.463 (v2).
- Hard mint predicate `((c0*c0)*(max>thresh))` is **not** behaviorally equivalent to any
  feature in monomial + Walsh + world + VM + mod_synth + pipelines within budget 8.
- **Recommend fork:** dedicated E4 hard-mint generalization study (threshold calibration,
  deeper VM, or new mint family).

## Verdict

| Criterion | Result |
|-----------|--------|
| RQ9 v1 reproducible rate | 66.7% — **FAIL** (<30% bar) |
| Non-reproducible share | **33.3%** (2/6) — insufficient for "real invention" PASS |
| Expanded basis recovery | **1/2** v1 failures |
| Genuinely novel after v2 | **1** (E4-G00) |
| **Fork?** | **YES** — E4-G00 hard mint family |

**Conclusion:** The 33% non-reproducible rate reflects **E4-G00** and **E5-F-A** under v1.
E3-parity and E11 sum_mod7 are **not** non-reproducible — they are **basis-repro false positives**
that inflate the reproducible fraction and cause the tax FAIL. Expanded basis closes E5-F-A
(synthesis-only) but leaves E4-G00 as the sole genuinely-novel survivor and fork target.

## See also

`open_invention_rq9.zig`, `open_invention_rq9.md`, `open_invention_e26.zig`, `open_invention_e26.md`,
`open_invention_e3.zig`, `open_invention_e4.zig`, `open_invention_e5.zig`, `open_invention_e11.zig`.