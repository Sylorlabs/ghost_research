# T8-AG-01b — E26-expanded tax basis (v2)

**Agent:** T8-AG-01b (Phase 1 fork)  
**Date:** 2026-07-06  
**Verdict:** **PASS** — tax v2 allows novel promotions; solve rate restored

## Changes

- `equivalence_tax.zig` `BASIS_VERSION = 2`
- Exclude candidate from static pool (no self-remix)
- Add xor_popcount top-16, clifford_g2, budget 8
- Import `open_invention_e2.zig` for xor readout

## Results

| Metric | v1 strict | v2 strict |
|--------|-----------|-----------|
| Solved | 10/11 | **11/11** |
| Novel allowed | 0 | **2** |
| Remix blocked | 21 | 15 |
| Novel rate | 0% | **11.8%** |
| Library | 11 | 13 |

Log: `/tmp/tier8-swarm/T8-AG-01b_strict.log`

## Fork

→ **T8-AG-02** per-target tax failure taxonomy; target ≥40% novel rate via pipelines/mod-synth basis (E26-full).