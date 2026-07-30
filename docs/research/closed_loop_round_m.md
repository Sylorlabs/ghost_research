# M5 — enforced closed-loop expedition

**Verdict: CONTROLLED STRICT POSITIVE.** Within this deliberately bounded
synthetic alphabet, the policy-safe loop (map trace → split slot → derive two
public candidates → TRAIN query → freeze → fresh TEST) scores **72/72** on six
post-M4 evaluator-owned cells. The frozen existing-menu control scores
**36/72** and a trace-blind fixed candidate scores **54/72**, at the same enforced cost of
**29 calls per arm per target**.

Harness: `sparse_poly_discovery/closed_loop_round_m.zig`.
Complete per-action ledger: `results/closed_loop_round_m.csv`.

## What the policy can and cannot use

The policy sees an opaque token plus a two-number aggregate trace. It derives
one public grammar slot from trace direction, queries two opposite bit
predicates on eight TRAIN examples each, and freezes the better candidate
before evaluator-owned TEST. It never receives a target expression, family
name, parameter, target identity beyond its opaque token, fresh-test label, or
per-test correctness reply. The six evaluator cells are distinct from M4's
four cells.

## Enforced comparison

| Arm | Fresh aggregate | Cost per target |
|---|---:|---:|
| Closed loop | **72/72** | 29 charged calls |
| Frozen existing menu | 36/72 | 29 charged calls |
| Trace-blind fixed candidate | 54/72 | 29 charged calls |

Each evaluator session begins with a 29-call state file. The policy reloads
that state between its two TRAIN candidate batches; it cannot reset the
counter. After the 29th call, a 30th call is rejected. Every charged action is
one CSV row: 16 TRAIN queries + one frozen choice + 12 fresh tests for the
closed loop; 17 pretest charges + 12 fresh tests for each control.

## Attacks and limits

- **Reverse token and candidate order:** `selftest` reruns both orders; totals
  remain identical.
- **Duplicate candidate:** each pair is logical opposites, so selection cannot
  rename a duplicate as a new family.
- **Privacy:** ledger fresh rows say `sealed`; a private-field scan rejects
  evaluator mechanism fields, target seeds, and fresh-test labels.
- **Accounting/restart:** all three arms finish exactly at 29 calls per target;
  the attempted extra policy call is rejected after reload.
- **Bounded result:** the trace dimension, operator alphabet, verifier, and
  controlled evaluator regions remain supplied. This proves an enforced fresh
  generalization loop in that setup, not open-ended map-making or an
  OS-isolated service boundary.

## Reproduce

```bash
rm -rf /tmp/zig-m5-cache /tmp/zig-m5-global /tmp/closed_loop_m5
zig build-exe sparse_poly_discovery/closed_loop_round_m.zig -O ReleaseFast \
  --cache-dir /tmp/zig-m5-cache --global-cache-dir /tmp/zig-m5-global \
  -femit-bin=/tmp/closed_loop_m5
/tmp/closed_loop_m5 run results/closed_loop_round_m.csv
/tmp/closed_loop_m5 selftest
```
