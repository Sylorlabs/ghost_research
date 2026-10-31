# T8-AG-00 — Wave 0 baseline lock

**Date:** 2026-07-06  
**Verdict:** **PASS**

| Agent | Harness | Result |
|-------|---------|--------|
| T8-AG-00a | `invention-engine` ×2 | **11/11**, 372 evals (identical) |
| T8-AG-00b | `invention-baseline-compare` | **PASS** — 11/7/3/2/2, 372 vs 2320/6160 |
| T8-AG-00c | `open-invention-e26` | 3 novel survivors, ~85% repro |

Logs: `/tmp/tier8-swarm/T8-AG-00a_run1.log`, `T8-AG-00b.log`, `T8-AG-00c.log`

Fork: T8-AG-00d flaky audit — not needed (runs identical).