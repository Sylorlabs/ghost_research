# T8-AG-16 — Coverage/certify cross-audit

**Agent:** T8-AG-16  
**Phase:** 4 (Tier 8a instruments)  
**Seed:** stress PRNG `0xC16A20260706`  
**Verdict:** **PASS**

## Deliverable

- `coverage_audit.zig` — independent coverage + certify implementation
- `unified_invention.certifyPublic()` — production certifier export
- `tier8_cert_cross_audit.zig` — 4096-trial stress harness

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-cert-cross-audit --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-16.log` (~8.5 min runtime)

## Results (2026-07-06)

| Metric | Value |
|--------|-------|
| Stress trials | 4096 |
| Coverage flips | **0** |
| Certify flips | **0** |

Primary (`measureCoverage` / `certifyPublic`) and audit implementations agree on all trials.

## Fork

- **T8-AG-16f** — I54/I55-style `behavior_matches` wrapper for `measureCoverage`