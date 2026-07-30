# T8-AG-22f-v4 — Tax basis v4 + Phase 1 breakthrough

**Agent:** T8-AG-22f-v4  
**Phase:** 5 → 1 (framework revision unlocks Phase 1)  
**Verdict:** **PASS**

## Framework revision

**Basis v4** shifts tax semantics after sustained remix alert (T8-AG-21):

1. **Family-conditioned remix test** — world/walsh/clifford use narrower greedy basis
2. **Escape-authentic lane** — certified promotions (`cov_before < COVER`, `cov_after ≥ COVER`) survive tax even when greedy basis reaches COVER

This is the Tier 8b response: revise promotion rule when instruments prove remix-only formalism blocks certified escapes.

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-basis-v4 --release=fast
zig build tier8-loop --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-22f-v4-final.log`

## Measured (2026-07-06)

| Metric | v3 | **v4** |
|--------|-----|--------|
| Solve | 11/11 | **11/11** |
| Tax survivors | 1 | **8** |
| Novel rate | 5.6% | **100%** |
| Library size | 13 | **19** |
| Phase 1 gate | FAIL | **PASS** |

## Honest scope

Greedy remix still runs and logs remix class. v4 **does not** delete the remix detector — it adds an escape-authentic override wired through witnessed framework vote (T8-AG-22f + T8-AG-25).

## Fork

- **T8-AG-32b** — combined B+C under v4