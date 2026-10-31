# T8-AG-06 — Learned guide → verify-learn discover path

**Agent:** T8-AG-06 (Phase 2)  
**Date:** 2026-07-06  
**Verdict:** **PASS**

## Deliverable

- `unified_invention.zig`: `runSingleTargetGuided()` — bootstrap + guided escalation
- `verify_learn_invent.zig`: `discover_feature` tries guided path before hardness fallback

## Run

```bash
cd boundary_crossing && zig build verify-learn-invent --release=fast
```

Log: `/tmp/tier8-swarm/T8-AG-06.log`

## Results

- Unified invention: **7/7** certified (unchanged)
- Plain English invention: **4/4** certified outcomes
- Guided discover path wired; falls back to hardness router + `runSingleTarget` on miss

## Tier 6 gate

Proposer subordinated to certifier: **PASS** for parity discover REPL path.