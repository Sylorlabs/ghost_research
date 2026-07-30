# O5 — active closed-loop expedition

**Verdict: CONTROLLED STRICT POSITIVE.** The frozen active loop reaches
**24/24** fresh evaluator-owned tests, while equal-cost fixed grammar,
blind-probe grammar, and no-probe family-prior controls each reach **12/24**.
It wins separately on all three independent hidden cohorts (8/8 each).

Harness: `sparse_poly_discovery/active_closed_loop_round_o.zig`. Ledger:
`results/active_closed_loop_round_o.csv`.

## Protocol

This is a new 24-token evaluator-owned suite, distinct in tokens, ordering,
and cohort partition from O4. For every opaque token the policy sees only an
`amber`/`violet` public trace. The trace remains balanced against the hidden
grammar bit, so the passive/family-prior route is 12/24. Frozen public history
selects one of two allowed aggregate probes for each trace. The policy may
spend exactly four persistent calls:

1. read the public trace;
2. buy one allowed aggregate probe (or consume an inert equal-cost slot);
3. commit one public nonredundant grammar before score;
4. receive evaluator-owned fresh score.

The active arm maps only its permitted aggregate reply to its committed
grammar. It never receives formulas, family names, masks, target IDs,
manifest data, or test labels. Fixed, blind, and no-probe controls receive
the identical four-call session budget; every arm logs a rejected fifth call.

## Result

| Arm | Fresh exact | Charged cost / target |
|---|---:|---:|
| Active closed loop | **24/24** | 4 |
| Fixed grammar/menu | 12/24 | 4 |
| Blind probe/grammar | 12/24 | 4 |
| No-probe family prior | 12/24 | 4 |

## Verification

- three independent evaluator-owned cohorts: active is 8/8 in each and beats
  fixed/blind in each;
- trace remains counterfactually balanced; the win comes from the charged
  aggregate diagnostic, not passive routing;
- public grammar commitment is emitted before the evaluator-owned score;
- full row-per-action ledger, rejected over-budget call, and persistent cost;
- token/case reversal preserves the aggregate verdict;
- privacy scan rejects private field names, and only opaque tokens appear;
- no candidate duplication: the two committed public grammars differ.

This is a controlled protocol result. The probe alphabet, frozen history,
grammar alphabet, and evaluator scoring interface are supplied. It shows an
active experimental loop can beat equal-cost fixed and blind controls on a
fresh decoupled suite; it does not show open-ended probe or grammar invention.

## Reproduce

```bash
rm -rf /tmp/zig-o5-cache /tmp/zig-o5-global /tmp/active_closed_loop_o5
zig build-exe sparse_poly_discovery/active_closed_loop_round_o.zig -O ReleaseFast \
  --cache-dir /tmp/zig-o5-cache --global-cache-dir /tmp/zig-o5-global \
  -femit-bin=/tmp/active_closed_loop_o5
/tmp/active_closed_loop_o5 run results/active_closed_loop_round_o.csv
/tmp/active_closed_loop_o5 selftest
```
