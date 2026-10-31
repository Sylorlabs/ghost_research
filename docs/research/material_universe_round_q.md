# Q1 — deterministic material universe and provenance registry

**Verdict: FOUNDATION PASSED.** Q1 implements a deterministic fixture registry
for approved discovery material. It is explicitly *not* literal web, filesystem,
or physical-world exploration: it models the safe supply-chain boundary needed
before such adapters can be admitted.

Harness: `sparse_poly_discovery/material_universe_round_q.zig`. Ledger:
`results/material_universe_round_q.csv`.

## Registry result

Five typed, content-addressed materials are admitted in canonical hash order:
two generic program atoms, one synthetic simulator descriptor, one public prior
forge descriptor, and one safe local-corpus fixture. Each row contains its
source class, content hash, public capability descriptor, cost, policy/license
tag, lineage, and admission state.

The registry is a material passport system, not an answer channel. It rejects
evaluator/test manifests, hidden-answer vocabulary, missing provenance, and
renamed duplicates (same content hash). Public descriptors are scanned for
private evaluator terminology.

## Controls

- Reverse input traversal byte-compares with canonical registry traversal.
- A renamed copy has the original content hash and cannot be newly admitted.
- Missing policy/lineage fails validation.
- Evaluator/test/answer-bearing source content fails validation.
- Hash replay and public-descriptor privacy are checked in `selftest`.

## Scope boundary

This fixture proves provenance mechanics only. Q2 must demonstrate useful
retrieval; Q3 must quarantine any candidate that leaks, duplicates, or lacks
transfer evidence. No literal Internet/world claim is made by Q1.

## Reproduce

```bash
rm -rf /tmp/zig-q1-cache /tmp/zig-q1-global /tmp/material_universe_q1
zig build-exe sparse_poly_discovery/material_universe_round_q.zig -O ReleaseFast \
  --cache-dir /tmp/zig-q1-cache --global-cache-dir /tmp/zig-q1-global \
  -femit-bin=/tmp/material_universe_q1
/tmp/material_universe_q1 run results/material_universe_round_q.csv
/tmp/material_universe_q1 selftest
```
