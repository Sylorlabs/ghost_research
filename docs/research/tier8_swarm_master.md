# Tier 8 swarm — living master report

**North star:** [Tier 8 Mega Plan](tier8_mega_plan.md) — **Tier 8 is the goal.**

**Status:** Wave 0 — plan committed; agents not yet dispatched.  
**Repo:** `/home/micah/Desktop/Sylorlabs/ghost_research`

---

## Program position

| Milestone | Status |
|-----------|--------|
| Tier 2–3 production (`invention-engine`) | **PASS** — 11/11, 372 evals |
| Tier 3 quint arity | **PASS** — 1.000 |
| Tier 5 measurement (E26) | **PARTIAL** — 3/20 novel, 85% repro |
| Tier 5 promotion gate | **NOT STARTED** — T8-AG-01 |
| Tier 6 proposer loop | **PARTIAL** — verify-learn / RQ7 harnesses exist |
| Tier 7 battery C | **NOT STARTED** — T8-AG-11 |
| Tier 8 loop | **NOT STARTED** — T8-AG-32 |

---

## Agent registry (dispatch queue)

| ID | Phase | Task | Verdict | Doc |
|----|-------|------|---------|-----|
| T8-AG-00a | 0 | invention-engine ×2 | pending | — |
| T8-AG-00b | 0 | baseline compare | pending | — |
| T8-AG-00c | 0 | E26 snapshot | pending | — |
| T8-AG-01 | 1 | tax gate in promote() | pending | — |
| T8-AG-02 | 1 | solve vs novel tradeoff | pending | — |
| … | … | see mega plan | … | … |

Full registry: 35 primary + 12 fork slots in [tier8_mega_plan.md](tier8_mega_plan.md).

---

## Wave schedule

| Wave | Agents | Parallel? |
|------|--------|-----------|
| 0 | 00a–00c | yes |
| 1 | 01, 06, 11, 16 | yes (after Wave 0 PASS) |
| 2 | PASS forks | yes |
| 3 | 31–35 integration | serial |

---

## Reproduce (current gates)

```bash
cd sparse_poly_discovery && zig build invention-engine --release=fast
zig build invention-baseline-compare --release=fast
zig build open-invention-e26 --release=fast
```

Target (Phase 7):

```bash
zig build tier8-loop --release=fast   # not built yet
```

---

Updates append per-agent rows as sub-agents complete. Do not mark Tier 8 program PASS until Phase 7 gates in mega plan are met.