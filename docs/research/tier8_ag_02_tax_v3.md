# T8-AG-02 — E26-full tax basis v3

**Agent:** T8-AG-02  
**Phase:** 1 (Tier 5 tax gate)  
**Seeds:** grid `0xF0235A11CE0FF1CE`, battery `0xE1B10D20A11CE01`  
**Verdict:** **PARTIAL** (basis complete; novelty gate not met)

## Deliverable

`equivalence_tax.zig` `BASIS_VERSION=3` — expanded greedy remix basis:

| Family | v2 | v3 |
|--------|----|----|
| monomial / pair / Walsh / world | yes | yes |
| xor top-16 | yes | yes |
| clifford_g2 | yes | yes |
| E5 pipelines (7×7) | no | **yes** |
| mod-synth depth≤3 | no | **yes** |

## Reproduce

```bash
cd sparse_poly_discovery
zig build invention-engine-strict-tax --release=fast
zig build tier8-loop --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-02-loop.log`

## Measured (2026-07-06)

| Metric | v2 | v3 |
|--------|----|----|
| Solve rate | 11/11 | **11/11** |
| Tax checked | 21 | 18 |
| Novel allowed | 2 | **1** |
| Remix blocked | 19 | **17** |
| Novel rate | 11.8% | **5.6%** |
| Phase 1 gate (≥40% novel) | FAIL | **FAIL** |

## Interpretation

Full E26 basis **tightens** remix detection: pipelines + mod-synth reproduce more certified escapes without the candidate, so fewer promotions survive. Solve rate unchanged at 11/11.

**Per-target taxonomy (blocked = remix under v3 basis):**

- Walsh χ promotions (B5/B6/B7/B8): reproducible via pair-router or Walsh column
- World sum%mod (B3): reproducible via mod-synth
- Inversion parity (B11): reproducible via pipeline half_p
- Monomial forge (B1/B2): reproducible via static monomial pool

**Novel survivor (1/18):** one growable pair promotion not greedy-reproduced at budget 8 under full basis.

## Fork

- **T8-AG-02f** — per-target failure taxonomy JSON (pair vs walsh vs pipeline remix class)
- **T8-AG-03** — downstream lift for the single v3 novel survivor