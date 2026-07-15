# Q4 — provenance-qualified material forge

**Verdict: CONTROLLED STRICT POSITIVE.** Starting only with Q1's two public,
typed generic atoms and Q2's anonymous residual summaries, the forge combines
the provenance-qualified `bounded_count_comparison` and `boolean_relation_fold`
materials into a new `counted_relation` primitive. It is frozen before any
score-private closure and transfers across three evaluator-private mechanism
variants.

Harness: `sparse_poly_discovery/material_forge_round_q.zig`. Public,
aggregate-only ledger: `results/material_forge_round_q.csv`.

## Aggregate closure

| Arm | Aggregate fresh acceptance | Total charged cost |
|---|---:|---:|
| Forged count-then-relation material | **24/24** | 4/session |
| Count component | 0/24 | 4/session |
| Relation component | 0/24 | 4/session |
| Fixed composition | 0/24 | 4/session |
| Blind composition | 8/24 | 4/session |

The score-private ledger has no per-session result. It records only anonymous
events, public residual class, content lineage, pre-score commitment, charged
actions, and arm. The evaluator releases the above campaign totals only after
closure.

## Material lineage and admission

The new primitive is not an opaque import. Its content lineage is the canonical
ordered combination of Q1's admitted raw atoms:

```text
cf4ccde68a0fdf19  bounded_count_comparison
3a8490803f0413dd  boolean_relation_fold
→ forge(cf4ccde68a0fdf19+3a8490803f0413dd)
```

Both source materials have typed Q1 passports, and Q3-style provenance checks
are charged for every arm. The harness treats an alias as identical content by
fingerprint; its forged fingerprint differs structurally from each component,
the fixed composition, and the blind reversed composition.

## Controls and limits

- Four actions per arm/session are ledgered: scout, quarantine, forge, and
  pre-score test. Every arm pays all four.
- Anonymous traversal reversal byte-compares; candidate ordering cannot alter
  the selection.
- The selftest checks lineage, privacy vocabulary, no per-session score,
  renamed-component nonredundancy, closure-only aggregate release, and line
  count.
- This proves bounded material forging from a supplied safe registry. It does
  **not** prove literal external-world acquisition: Q1's material universe is
  still a deterministic approved fixture, and the residual vocabulary remains
  deliberately aligned to its public passports.

## Reproduce

```bash
rm -rf /tmp/zig-q4-cache /tmp/zig-q4-global /tmp/material_forge_q4
zig build-exe sparse_poly_discovery/material_forge_round_q.zig -O ReleaseFast \
  --cache-dir /tmp/zig-q4-cache --global-cache-dir /tmp/zig-q4-global \
  -femit-bin=/tmp/material_forge_q4
/tmp/material_forge_q4 run results/material_forge_round_q.csv
/tmp/material_forge_q4 selftest
```
