# Tier 8 swarm — living master report

**North star:** [Tier 8 Mega Plan](tier8_mega_plan.md) — **Tier 8 is the goal.**

**Status:** Wave 0–2 **PASS** | Wave 3 **PASS** (T8-AG-11, T8-AG-15) | T8-AG-02 **PARTIAL**
**Repo:** `/home/micah/Desktop/Sylorlabs/ghost_research`  
**Scratch:** `/tmp/tier8-swarm/`

---

## Program position

| Milestone | Status |
|-----------|--------|
| Tier 2–3 production (`invention-engine`) | **PASS** — 11/11, 372 evals |
| Tier 5 tax gate v2 (`--strict-tax`) | **PASS** — 11/11, 2 novel, 11.8% |
| Tier 5 tax gate v3 (E26-full basis) | **PARTIAL** — 11/11, 1 novel, 5.6% |
| Tier 5 novelty gate (≥40% novel) | **FAIL** — taxonomy logged (mono 10 / walsh 6 / pipe 1) |
| Tier 6 guided discover REPL | **PASS** — `runSingleTargetGuided` wired |
| Tier 7 battery C harness | **PASS** — 11 targets, mean mono 0.498 |
| Tier 7 invention on battery C | **PASS** — 11/11 vs mono 0/11 |
| `tier8-loop` orchestrator | **BUILT** — Pass A + Pass B |
| `tier8-dispatch` registry | **BUILT** — 8 agents registered |
| Tier 8 complete | **NOT STARTED** |

---

## Agent registry

| ID | Phase | Verdict | Doc / log |
|----|-------|---------|-----------|
| T8-AG-00a | 0 | **PASS** | [tier8_ag_00_wave0.md](tier8_ag_00_wave0.md) |
| T8-AG-00b | 0 | **PASS** | `T8-AG-00b.log` |
| T8-AG-00c | 0 | **PASS** | `T8-AG-00c.log` |
| T8-AG-01 | 1 | **PASS** | [tier8_ag_01_tax_gate.md](tier8_ag_01_tax_gate.md) |
| T8-AG-01b | 1 | **PASS** | [tier8_ag_01b_tax_v2.md](tier8_ag_01b_tax_v2.md) |
| T8-AG-02 | 1 | **PARTIAL** | [tier8_ag_02_tax_v3.md](tier8_ag_02_tax_v3.md) |
| T8-AG-02f | 1 | **PASS** | [tier8_ag_02f_taxonomy.md](tier8_ag_02f_taxonomy.md) |
| T8-AG-06 | 2 | **PASS** | [tier8_ag_06_guided_discover.md](tier8_ag_06_guided_discover.md) |
| T8-AG-11 | 3 | **PASS** | [tier8_ag_11_battery_c.md](tier8_ag_11_battery_c.md) |
| T8-AG-11f | 3 | **PASS** | [tier8_ag_11f_replication.md](tier8_ag_11f_replication.md) |
| T8-AG-15 | 3 | **PASS** | [tier8_ag_15_battery_c_engine.md](tier8_ag_15_battery_c_engine.md) |

---

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-dispatch --release=fast
zig build invention-engine --release=fast
zig build invention-engine-strict-tax --release=fast
zig build invention-baseline-compare --release=fast
zig build tier8-loop --release=fast          # Pass A + Pass B (tax v3)
zig build tier8-battery-c --release=fast   # T8-AG-11
zig build tier8-battery-c-engine --release=fast   # T8-AG-15
zig build open-invention-e26 --release=fast
```

---

## Key finding (Wave 3)

**Tax v3** adds E5 pipelines (49) + mod-synth (depth≤3) to the remix basis. Solve stays **11/11** but novel rate drops to **5.6%** (1/18) — fuller basis blocks more promotions honestly. Phase 1 ≥40% gate still open.

**Battery C + invention:** mono **0/11**, invention **11/11** (xor-route + Walsh + pipeline). Strict tax blocks Walsh promotions as remix but solve rate unchanged.

Next army wave: **T8-AG-02f** (remix taxonomy JSON) + **T8-AG-11f** (battery C seed replication).