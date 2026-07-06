# Tier 8 swarm — living master report

**North star:** [Tier 8 Mega Plan](tier8_mega_plan.md) — **Tier 8 is the goal.**

**Status:** Wave 0 **PASS** | Wave 1 **PASS** | Wave 2 T8-AG-01b + T8-AG-06 **PASS**
**Repo:** `/home/micah/Desktop/Sylorlabs/ghost_research`  
**Scratch:** `/tmp/tier8-swarm/`

---

## Program position

| Milestone | Status |
|-----------|--------|
| Tier 2–3 production (`invention-engine`) | **PASS** — 11/11, 372 evals |
| Tier 5 tax gate v2 (`--strict-tax`) | **PASS** — 11/11, **2 novel**, 11.8% rate |
| Tier 5 novelty gate (≥40% novel) | **PARTIAL** — T8-AG-02 next |
| Tier 6 guided discover REPL | **PASS** — `runSingleTargetGuided` wired |
| `tier8-loop` orchestrator | **BUILT** — `zig build tier8-loop` |
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
| T8-AG-02 | 1 | pending | E26-full basis + taxonomy |
| T8-AG-06 | 2 | **PASS** | [tier8_ag_06_guided_discover.md](tier8_ag_06_guided_discover.md) |
| T8-AG-11 | 3 | pending | battery C |

---

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-dispatch --release=fast
zig build invention-engine --release=fast
zig build invention-engine-strict-tax --release=fast
zig build invention-baseline-compare --release=fast
zig build tier8-loop --release=fast          # Pass A + Pass B
zig build open-invention-e26 --release=fast
```

---

## Key finding (Wave 1)

Strict tax blocks **100%** of promotions (21/21) as basis-remix under current static basis — confirming E26's 85% reproducible story at promotion time. Solve rate drops 11→10; library 19→11. **Tier 5 honesty achieved; Tier 5 survivors not yet.**

Next army wave: **T8-AG-01b** (E26-full tax basis) + **T8-AG-06** (proposer loop) in parallel.