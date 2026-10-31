# T8-AG-21 — Remix rate monitor

**Agent:** T8-AG-21  
**Phase:** 5 (Tier 8b framework revision)  
**Verdict:** **PASS**

## Deliverable

`remix_rate_monitor.zig` + `tier8_remix_monitor.zig` — rolling 5-run novel rate; fires alert when mean <20%.

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-remix-monitor --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-21.log`

## Measured (2026-07-06)

| Run | Seed | Novel rate |
|-----|------|------------|
| 1–3 | GRID_SEED..+2 | 5.6% |
| 4 | +3 | 5.3% |
| 5 | +4 | 10.0% |

Mean: **6.4%** | Alert: **FIRED**

## Fork

- **T8-AG-21f** — proposer-path remix alert