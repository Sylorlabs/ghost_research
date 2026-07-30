# T8-AG-19 — Ledger drift replay

**Agent:** T8-AG-19  
**Phase:** 4 (Tier 8a instruments)  
**Verdict:** **PASS**

## Deliverable

`tier8_ledger_drift.zig` — replays promotion-ledger captures under tax basis v3; flags drift flips and retroactive remix when basis narrows.

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-ledger-drift --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-19.log`

## Measured (2026-07-06)

| Field | Value |
|-------|-------|
| Battery solve | 11/11 |
| Replay captures | 18 |
| Ledger records | 18 |
| v3 re-replay drift flips | **0** |
| Retroactive novel (v3 remix → v2 novel) | 1 |

## Interpretation

Zero drift flips means ledger verdicts are **stable** under v3 re-replay. One retroactive novel under v2 confirms basis expansion is **honestly stricter** — a promotion blocked at v3 would have been allowed on the narrower v2 basis.

## Fork

- **T8-AG-17** — formalize basis version registry + monotonic novel-rate check