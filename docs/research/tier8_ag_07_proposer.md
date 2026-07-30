# T8-AG-07 — RQ7 proposer + strict tax gate

**Agent:** T8-AG-07  
**Phase:** 2 (proposer loop)  
**Verdict:** **FAIL**

## Deliverable

`open_invention_tier8_rq7.zig` — feeds first 50 entries from `rq7_proposals.json` through RQ7 `accLogit` certification (≥0.90 held-out), then applies tax basis v3 via `gatePromoteEx`.

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-rq7-tax --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-07.log`

## Measured (2026-07-06)

| Field | Value |
|-------|-------|
| Proposals scanned | 50 (of 100) |
| Certified pairs (accLogit ≥0.90) | 13 |
| Tax survivors | **1** |
| Tax checked / novel / blocked | 13 / 1 / 12 |
| Sole survivor | `sum_mod7_indicator` on sum_mod (test=1.000) |

## Baseline comparison

RQ7 without tax (100 proposals): **25** certified, **9** novel (`classifyFamily`).  
Tax v3 collapses proposer survivorship to **1/13** — the expanded remix basis blocks Walsh/oriented/pair proposals that RQ7 counted as novel.

## Root cause

Phase 1 novelty gate remains the bottleneck: tax v3 is **correct but strict**. Proposer path does not yet emit features outside the v3 remix cone at sufficient rate.

## Fork (per mega plan)

- **FAIL → T8-AG-06b** — deterministic English-template proposer for CI
- **PASS → T8-AG-07f** — family diversity fork (not triggered)