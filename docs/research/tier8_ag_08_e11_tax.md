# T8-AG-08 — E11 replay + strict tax gate

**Agent:** T8-AG-08  
**Phase:** 2 (proposer loop)  
**Verdict:** **PASS**

## Deliverable

`open_invention_tier8_e11.zig` — replays `e11_proposals.json` on E11 grid seed with tax basis v3.

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-e11-tax --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-08.log`

## Measured (2026-07-06)

| Field | Value |
|-------|-------|
| Proposals | 20 |
| Grid seed | 0xE11C0DE20260629 |
| Certified pairs | 8 |
| Tax survivors | **1** |
| Tax checked / novel / blocked | 8 / 1 / 7 |
| Survivor | `sum_mod7_indicator` on sum_mod (test=1.000) |

## Interpretation

E11's arithmetic-world novel (`sum_mod7_indicator`) survives strict tax v3 — the same feature blocked as remix across Walsh/oriented proposals in RQ7. This satisfies the **Tier 6 gate** minimum: ≥1 tax-survivor from a proposer path.

## Fork

- **T8-AG-09** — anti-hallucination noise suite