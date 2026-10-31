# E28 — DeepSeek expert route invention

**Date:** 2026-06-30  
**Question:** Can hardness router + unified loop invent features predicting expert activation from captured L30 activations (no full model forward)?

## Run

```bash
cd sparse_poly_discovery
zig build open-invention-e28 --release=fast
```

Requires on-disk captures in `deepseekexperiment/`:
- `acts_T128_off8000.bin` — post-ffn_norm expert inputs, 128 tokens × 61 layers
- `gate_L30_w.bin` — L30 gate weights `[384, 7168]` f32
- `e11_positions_off8000.csv` — held-out text position metadata (offset-8000 CLAUDE.md window)

## Protocol

1. **Load** L30 activations (128 tokens) and gate matrix; compute ground-truth `sqrtsoftplus(x·W_gate)` scores per expert.
2. **Substrate** — project each 7168-dim activation into an 8-cell grid (per-dimension-group RMS energy, quintile-quantized 0–5). This is the sparse_poly_discovery invention substrate applied to real expert inputs.
3. **Split** — train positions 0–88 (70%), invention-val 89–101, held-out 102–127 (last 30% of e11 window = unseen stream positions).
4. **Hardness router** (E14/Q38 analog) — probe monomial vs extremal hardness per expert target; classify `single_sufficient` / `q38_compound` / `unknown`.
5. **Unified loop routes** (one per expert, no manual hints):
   - monomial forge / Walsh menu
   - spectral menu `cos(ω·count)` (unified_invention T5 escape)
   - world pool `sum%mod_p`, `sign%mod_p`
   - mod synthesis (depth≤3 over count/inv/sum)
   - xor_popcount (RQ2 GF(2) readout)
   - composed pipelines (oriented, inv→parity, sum→bind)
6. **Baseline** — constant mean gate-score predictor (train mean → held-out R²).
7. **Certify** — held-out R² > 0 and ≥5% lift vs baseline.
8. **RQ9 novelty** — invented feature must not correlate ≥0.995 with any monomial φ_S, Walsh χ_S, or world-pool indicator on held-out samples (spectral, mod-synthesis, and pipelines are outside the RQ9 tax basis).

## Pass bar

| Criterion | Threshold |
|-----------|-----------|
| Activation prediction lift | ≥5% relative vs mean baseline |
| Held-out R² | > 0 (certified positive predictive power) |
| RQ9 novelty | feature ∉ mono+Walsh+world closure |

## Results (2026-06-30, `--release=fast`)

```
Candidate experts: 16 (spectral prescreen + pinned)
Certified: 16/16 experts with hold_r2>0 and lift≥5%
RQ9-novel: 16/16 (mod_synthesis programs outside mono+Walsh+world tax)

CHAMPION: L30 expert e38
  Hardness: q38_compound
  Route: mod_synthesis (hardness router → unified escalation)
  Feature: mod_prog#465
  Baseline R²: -0.128
  Held-out R²: 0.188
  Lift: 28.0%
  RQ9 novel: true

VERDICT: PASS
E28_RESULT pass=true expert=38 hold_r2=0.188 lift=0.280 novel=16/16
```

Other certified experts include e54 (hold_r2=0.071, lift=46.8%), e266 (0.130, 57.6%), e368 (0.141, 27.3%).
All use captured acts+gate only — no live model forward.

## Key files

| File | Role |
|------|------|
| `open_invention_e28.zig` | E28 harness |
| `hardness_router.zig` | Q38 task-class types |
| `unified_invention.zig` | COVER threshold, invention loop lineage |
| `open_invention_e14.zig` | Grid hardness router + route selection |
| `open_invention_rq9.zig` | Novelty tax definition |

## Honest bounds

- Uses **captured activation dumps only** — no live V4 forward pass.
- 8-cell substrate is a lossy projection of 7168-dim inputs; lift measures invention on the **substrate**, not raw activation space.
- 128-token window limits statistical power; held-out set is 26 positions.
- Gate scores computed from dumped weights; top-6 routing labels derived offline.

See also: `deepseekexperiment/docs/e11_perplexity_2026_06_11.md`, `hardness_router_integration.md`, `open_invention_e14.md`.