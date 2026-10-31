# T8-AG-17 — Tax basis version registry

**Agent:** T8-AG-17  
**Phase:** 4 (Tier 8a instruments)  
**Verdict:** **PASS**

## Deliverable

`tier8_tax_basis_version.zig` — documents basis levels 1/2/3 and audits replay captures for monotonic novel-rate shrinkage as basis expands.

| Level | Label | xor | pipeline | mod-synth |
|-------|-------|-----|----------|-----------|
| 1 | v1-static | no | no | no |
| 2 | v2-xor | yes | no | no |
| 3 | v3-full | yes | yes | yes |

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-basis-version --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-17.log`

## Measured (2026-07-06)

| Level | Novel | Rate |
|-------|-------|------|
| v1-static | 2/18 | 0.111 |
| v2-xor | 2/18 | 0.111 |
| v3-full | 1/18 | 0.056 |

Per-capture monotonic violations: **0**  
Aggregate rate monotonic: **true**

## Interpretation

Basis expansion from v2→v3 blocks one additional promotion (11.1% → 5.6% novel rate) without creating per-capture inconsistencies. Registry is safe to extend.