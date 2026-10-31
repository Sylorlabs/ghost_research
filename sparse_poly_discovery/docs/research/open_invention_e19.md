# Experiment E19 — Wake-sleep LLM proposer (E11 production)

**Status:** built and measured. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-e19 --release=fast
```

(~8–12 min, ReleaseFast; loads `e11_proposals.json` + `rq7_proposals.json` as LLM seed menu)

## What this is

DreamCoder-style **wake–sleep** over the E11 grid harness:

1. **WAKE** — proposer submits 50 JSON feature structs per round (500 total over 10 rounds).
2. **CERTIFY** — engine alone judges logistic readout; held-out test ≥ 0.90 required (same as E11/RQ7).
3. **SLEEP** — certified features enter a growing **library**; later rounds **condition** on library entries (mutations + catalog continuation).

No external API. Seeds come from `e11_proposals.json` (20) and `rq7_proposals.json` (100); the harness extends them with a systematic catalog (Walsh, spectral ω-grid, XOR/oriented witnesses, world mod, monomial masks).

**Targets (5 families, RQ7 scale):** parity | hidden_pair (2,5) | sum_mod (%7) | oriented (v1>v0) | monomial_sign φ_{2,5}

**Novelty gate (RQ9 tax):** Pearson |ρ| ≥ 0.995 vs precomputed basis — monomial φ_S (deg≤4) + Walsh χ_S + world pool + VM depth≤6. Spectral and pipelines are **excluded** from the tax (per `open_invention_rq9.zig`).

## Pass bar

| Metric | Threshold | Measured |
|--------|-----------|----------|
| Certified proposal rate | ≥ 15% of 500 proposals certify on ≥1 target | **5.4%** (27/500) |
| RQ9-novel features | ≥ 5 unique features escape basis | **10** |

**Verdict: FAIL** (cert rate); **PASS** (RQ9 novelty).

## Measured results (reference run, seed `0xE19C0DE20260629`)

```
Proposals submitted     : 500  (10 rounds × 50)
Certified pairs         : 36 / 2500 (1.4% per proposal×target)
Unique proposals w/ cert: 27 / 500 (5.4%)
Cert pairs / proposal   : 7.2%
Library final size      : 27
RQ9-novel features      : 10
```

### Per-round library growth

| Round | Certified pairs | New library | Library size |
|-------|-----------------|-------------|--------------|
| 1 | 15 | 11 | 11 |
| 2 | 9 | 7 | 18 |
| 3 | 6 | 6 | 24 |
| 4–5 | 0 | 0 | 24 |
| 6 | 1 | 1 | 25 |
| 7 | 1 | 1 | 26 |
| 8–9 | 0 | 0 | 26 |
| 10 | 1 | 1 | 27 |

Rounds 1–3 consume the LLM seed menu (e11+rq7) and bulk spectral/Walsh catalog; library-conditioned slots (rounds ≥4) add mutations of promoted features.

### RQ9-novel promotions (representative)

- Library-conditioned spectral mutations certifying on **parity** (rounds 6, 10) — escape RQ9 VM+mono+Walsh+world closure.
- **oriented** / **hidden_pair** / **monomial_sign** witnesses from seed menu (rounds 2–3) — novel vs RQ9 basis though some are E11-class under Walsh/spectral/monomial gate.

## Findings

**Q1 — Wake-sleep library compounds, but slowly.** Library grows 11 → 27 over 10 rounds; rounds 4–9 plateau until late spectral mutations re-certify. Conditioning works (round-2 oriented/hidden promotions feed later mutations) but most catalog slots are low-yield on the **fixed** five targets.

**Q2 — Certified rate misses 15% bar.** With only five fixed predicates, the ceiling of distinct certifying structs is ~25–30 (rq7-scale menu), not 75. Measured 5.4% unique proposal rate / 7.2% pairs-per-proposal — honest shortfall, not certifier leniency.

**Q3 — RQ9 novelty PASS (10 ≥ 5).** Ten unique features sit outside the rich mono+Walsh+world+VM basis on held-out grids. Wake-sleep **does** promote basis-escaping features into the library (spectral-count mutations, oriented/antisymmetric witnesses).

**Q4 — Engine remains honest judge.** Creative long shots (median, gcd, harmonic mean) fail; only ≥0.90 held-out test promotions enter the library.

## Verdict

| Metric | Value |
|--------|-------|
| Proposals | 500 |
| Certified unique proposals | 27 (5.4%) |
| Certified pairs | 36 |
| Library size | 27 |
| RQ9-novel | 10 |
| **Overall** | **FAIL** (cert rate); partial **PASS** (novelty) |

## Files

| Artifact | Path |
|----------|------|
| Harness | `open_invention_e19.zig` |
| Build | `zig build open-invention-e19` |
| Seeds | `e11_proposals.json`, `rq7_proposals.json` |
| Basis tax | logic from `open_invention_rq9.zig` |
| Doc | `docs/research/open_invention_e19.md` |

See: `open_invention_e11.md`, `open_invention_rq7.md`, `open_invention_rq9.md`.