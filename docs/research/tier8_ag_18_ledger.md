# T8-AG-18 — Promotion ledger

**Agent:** T8-AG-18  
**Phase:** 4 (Tier 8a instruments)  
**Verdict:** **PASS**

## Deliverable

`invention_ledger.zig` — binary promotion log wired into `equivalence_tax.gatePromoteEx()`.

Each record: seq, tax basis version, feature tag/param, cert_ok, tax_survivor, remix_family, coverage floats.

## Reproduce

```bash
cd sparse_poly_discovery
zig build tier8-ledger-smoke --release=fast
```

Output: `/tmp/tier8-swarm/invention_ledger.bin`  
Log: `/tmp/tier8-swarm/T8-AG-18.log`

## Measured (2026-07-06)

| Field | Value |
|-------|-------|
| Records | 18 |
| Tax survivors | 1 |
| Remix blocked | 17 |
| Battery solve | 11/11 |
| Ledger/tax alignment | 18/18 checked |

## Fork

- **T8-AG-19** — replay ledger on prior basis versions (drift detector)