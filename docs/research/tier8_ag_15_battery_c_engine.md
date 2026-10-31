# T8-AG-15 — Invention engine on Battery C

**Agent:** T8-AG-15  
**Phase:** 3 (problem invention)  
**Seeds:** grid `0xF0235A11CE0FF1CE`  
**Verdict:** **PASS**

## Deliverable

`tier8_battery_c_engine.zig` — runs full invention ladder + xor-route + mod/pipeline escalation on Battery C targets.

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-battery-c-engine --release=fast
zig build tier8-battery-c-engine-strict --release=fast
```

Logs: `/tmp/tier8-swarm/T8-AG-15.log`, `T8-AG-15-strict.log`

## Results (2026-07-06)

| Mode | monomial_only | invention | Tax novel |
|------|---------------|-----------|-----------|
| tax off | **0/11** | **11/11** | — |
| strict tax v3 | **0/11** | **11/11** | 0/2 (0%) |

**PASS bar met:** invention solve (11) **>** monomial_only (0).

### Solve routes (tax off)

| Family | Route | Count |
|--------|-------|-------|
| xor_popcount | xor-route mask search | 9 |
| mod_synthesis | Walsh q38 (C08) | 1 |
| pipeline | inversion→half_p (C09) | 1 |

Tier 7 gate partial: battery-C targets solved via xor/pipeline/Walsh — not battery-B family. Strict tax blocked 2 Walsh promotions as remix; xor-route solves do not require library promotion.

## Fork

- **T8-AG-15f** — battery C with growable library persistence across targets
- **T8-AG-11f** — held-out grid seed replication