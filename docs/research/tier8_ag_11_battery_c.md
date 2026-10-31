# T8-AG-11 — Battery C (Tier 7 problem invention)

**Agent:** T8-AG-11  
**Phase:** 3 (problem invention)  
**Seeds:** grid `0xF0235A11CE0FF1CE` (shared with invention engine)  
**Verdict:** **PASS**

## Deliverable

`open_invention_tier8_battery_c.zig` — fixed battery of **11** predicates outside deg2 monomial closure, sourced from E2 xor/parity family + E14 inversion-parity.

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-battery-c --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-11.log`

## Targets

| ID | Predicate | Family | mono_cov |
|----|-----------|--------|----------|
| C01 | XOR(mask=0x0F)&1 | xor_popcount | 0.485 |
| C02 | parity(XOR 0x33) | xor_popcount | 0.502 |
| C03 | XOR 0x55 | xor_popcount | 0.503 |
| C04 | XOR 0xAA | xor_popcount | 0.512 |
| C05 | XOR 0x3C | xor_popcount | 0.497 |
| C06 | XOR 0x66 | xor_popcount | 0.509 |
| C07 | XOR 0x99 | xor_popcount | 0.504 |
| C08 | parity(#≥THRESH) | mod_synthesis | 0.501 |
| C09 | inv parity | pipeline | 0.477 |
| C10 | parity(XOR 0x0F) | xor_popcount | 0.485 |
| C11 | XOR 0x37 | xor_popcount | 0.507 |

## Summary

| Gate | Required | Measured |
|------|----------|----------|
| Target count | ≥8 | **11** |
| Mean mono coverage | <0.55 | **0.498** |
| Hard targets (mono<0.55) | — | **11/11** |

Monomial-only measurement uses frozen zoo-A library + 6-round monomial forge (same discipline as `invention_baseline_compare`).

**Note:** Initial draft included rank2/product_bind targets; those scored mono_cov 0.80–1.00 on this grid and were replaced with E2 xor-hard family.

## Fork

- **T8-AG-11f** — battery C held-out replication ×2 (alternate grid seed)
- **T8-AG-15** — invention engine + strict tax on battery C