# M4 — trace-derived proposal grammar

**Verdict: CONTROLLED LIMITED POSITIVE.** On the evaluator-owned fresh split,
a two-production public grammar derived only from aggregate trace direction
scores **48/48**, versus the frozen equal-cost existing menu's **24/48**. This
passes M4's narrow fresh-test gate, but does not establish open-ended grammar
invention: the trace construction and two generic bit-predicate productions
are deliberately small and synthetic.

Harness: `sparse_poly_discovery/proposal_grammar_round_m.zig`.
Complete ledger: `results/proposal_grammar_round_m.csv`.

## Protocol

For each opaque target the policy sees only an aggregate two-number trace
(`9:3` or `3:9`). It derives a grammar slot from the greater coordinate and
emits exactly two public-syntax candidates:

```text
bit(slot) == 0
bit(slot) == 1
```

There is no target token, hidden family name, formula, mask, target parameter,
audit field, or fresh-test label in the derivation. The evaluator scores both
candidates on eight TRAIN examples, freezes the better candidate, then scores
it on 12 disjoint TEST examples. Tokens are output identifiers only.

The candidate arm charges 16 TRAIN queries, one frozen-choice action, and 12
fresh tests: 29 rows per target. The frozen existing-menu control has 17
individual padding calls and 12 individual fresh-test calls: also 29. There
are no summarized calls.

## Result

| Arm | Fresh evaluator-owned test | Cost per target |
|---|---:|---:|
| Trace-derived grammar | **48/48** | 29 charged calls |
| Frozen existing menu | 24/48 | 29 charged calls |

The strict fresh-test comparison wins by 24 decisions. Each declared trace
region has two targets and both receive the same generic syntax generation;
the result therefore transfers within this controlled region construction.

## Attacks and limits

- **Private-data scan:** the emitted ledger rejects/contains none of
  `hidden_kind`, formulas, family labels, seeds, masks, audit material, or test
  labels.
- **Token/candidate order:** `selftest` reruns reversed target order and
  reversed candidate presentation; the outcome totals remain 48/48 and 24/48.
- **Nonredundancy:** the two productions give opposite outputs on every input;
  TRAIN selection selects a unique perfect production rather than renaming a
  duplicate.
- **Train/fresh separation:** inputs use disjoint evaluator-owned bands; TEST
  is scored only after the frozen choice row.

This is not yet a claim that an unconstrained learner invented the bit
predicate language from arbitrary failures. The grammar alphabet, trace
dimension, controlled target mechanisms, and verifier remain supplied. M5
must test whether this bounded map→split→propose result survives its closed
loop and M6 must independently audit it.

## Reproduce

```bash
rm -rf /tmp/zig-m4-cache /tmp/zig-m4-global /tmp/proposal_grammar_m4
zig build-exe sparse_poly_discovery/proposal_grammar_round_m.zig -O ReleaseFast \
  --cache-dir /tmp/zig-m4-cache --global-cache-dir /tmp/zig-m4-global \
  -femit-bin=/tmp/proposal_grammar_m4
/tmp/proposal_grammar_m4 run results/proposal_grammar_round_m.csv
/tmp/proposal_grammar_m4 selftest
```
