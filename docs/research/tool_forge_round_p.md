# P5 — tool/material forge from answer-free experience

**Verdict: CONTROLLED STRICT POSITIVE.** Starting with a supplied generic raw
computational atom grammar—not named task tools—P5 combines P2-style canonical
causal experience with P4-style aggregate forged-measurement replies to retain
one nonredundant operation before fresh evaluator-owned scoring. It wins across
three independent hidden task kinds, while fresh outcomes remain score-private.

Harness: `sparse_poly_discovery/tool_forge_round_p.zig`. Ledger:
`results/tool_forge_round_p.csv`.

## Aggregate campaign closure

| Arm | Fresh aggregate | Persistent cost |
|---|---:|---:|
| Forged raw-atom operation | **24/24** | 3/session |
| Raw-atom baseline | 0/24 | 3/session |
| Fixed generic composition | 0/24 | 3/session |
| Blind composition | 8/24 | 3/session |

The three evaluator-owned kinds each contain eight anonymous fresh sessions.
No public row identifies a session, its kind, its hidden relation, its selected
winner, or its individual fresh result. The closure releases totals only.

## What was forged

The raw substrate contains bounded Boolean folds, Boolean combination, and
count comparison. The policy recalls a P2-compatible causal tendency, runs the
P4-style generic aggregate measurement, and composes a structural operation:
XNOR-fold, count-compare, or XOR-then-count. It freezes that operation before
the evaluator scores the fresh session. The operation is structurally distinct
from the raw XOR fold and from the frozen generic-composition control.

This does **not** prove unconstrained invention: the instruction substrate,
evaluator, causal classes, and bounded composition grammar are supplied. It
does prove an answer-free experience → measurement → material-composition loop
with multi-kind transfer under equal persistent charged cost.

## Controls

- **Score-private:** no identity, relation, individual fresh outcome, winner,
  or target-to-operation link appears in policy-visible output.
- **Answer-free memory:** recall is a canonical causal tendency, never a row
  lookup or final test result.
- **Equal cost and complete ledger:** each of 24 sessions × four arms has three
  individual charged actions: recall, measurement, and pre-score commitment.
- **Pre-score commitment:** the selected operation is written before sealed
  observation is scored.
- **Order/token/duplicate:** reversed anonymous arrival byte-compares; output
  privacy scan rejects private vocabulary; a renamed raw operation fails closed.
- **Multi-kind transfer:** the forged process succeeds across all three
  evaluator-owned kinds, rather than only one coincidental fixture.

## Reproduce

```bash
rm -rf /tmp/zig-p5-cache /tmp/zig-p5-global /tmp/tool_forge_p5
zig build-exe sparse_poly_discovery/tool_forge_round_p.zig -O ReleaseFast \
  --cache-dir /tmp/zig-p5-cache --global-cache-dir /tmp/zig-p5-global \
  -femit-bin=/tmp/tool_forge_p5
/tmp/tool_forge_p5 run results/tool_forge_round_p.csv
/tmp/tool_forge_p5 selftest
```
