# T8-AG-01 — Equivalence tax promotion gate

**Agent:** T8-AG-01 (Phase 1)  
**Date:** 2026-07-06  
**Verdict:** **PASS** (wired + measured) — **PARTIAL** on Phase 1 novelty gate

## Deliverable

- `sparse_poly_discovery/equivalence_tax.zig` — greedy remix detector
- Wired into `unified_invention.zig` `certify()` via `eqtax.gatePromote()`
- `zig build invention-engine-strict-tax --release=fast` (`--strict-tax` flag)

## Run

```bash
cd sparse_poly_discovery
zig build invention-engine --release=fast                    # tax off: 11/11
zig build invention-engine-strict-tax --release=fast         # tax on
```

Log: `/tmp/tier8-swarm/T8-AG-01_strict.log`

## Results (strict tax on)

| Metric | tax off | tax on |
|--------|---------|--------|
| Solved | 11/11 | **10/11** |
| Battery evals | 372 | 1383 |
| Library size | 19 | 11 |
| Tax checked | — | 21 |
| Novel allowed | — | **0** |
| Remix blocked | — | **21** |
| Novel rate | — | **0.0%** |

## Interpretation

The tax **works as designed**: every certify+promote attempt was reproducible by greedy search over frozen lib + expanded static basis (monomials, pairs, top Walsh, world mods). Promotions blocked; solves still reach 10/11 via frozen zoo lib + RQ1 mod/pipeline fallbacks.

Phase 1 gate wants ≥40% novel rate **or** ≥3 tax-survivors — **not met**. This is honest: current static basis is rich enough to remix all ladder promotions.

## Fork dispatch

- **PASS (wired)** → **T8-AG-02** measure tradeoff (done in this log)
- **FAIL novelty gate** → **T8-AG-01b** expand tax basis toward E26 full (xor_popcount, pipelines, mod synth) OR exclude family-equivalent only

## Next

T8-AG-01b: align promotion tax basis with E26 v2 so blocked promotions correlate with E26 reproducible escapes; hunt tax-survivors that match E26 novel list.