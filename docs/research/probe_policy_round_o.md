# O2 — active probe-policy learner

**Verdict: CONTROLLED POSITIVE.** On a deterministic trace-decoupled fixture,
a policy that learns which public diagnostic probe to purchase from frozen
public history routes the successful public candidate on **12/12 held-out
cases**. Equal-cost fixed-probe and blind-probe controls reach **9/12**;
family-prior and no-probe controls reach **6/12**.

Harness: `sparse_poly_discovery/probe_policy_round_o.zig`. Ledger:
`results/probe_policy_round_o.csv`.

## Protocol

The policy receives a public base trace (`amber` or `violet`) and eight frozen
public history rows. The history establishes only which of two predeclared
public experiments is informative for each trace class. It does **not** reveal
which candidate is right: each trace class has an even 3/3 split between
`candidate_a` and `candidate_b` in the held-out set.

For a held-out opaque token, every arm spends three evaluator-owned calls:

1. read the base trace;
2. spend the probe slot (controls receive an inert equal-cost slot where
   appropriate);
3. route and score one public candidate.

The learned arm buys the history-selected probe; its public reply determines
the route. The fixed arm always buys `probe_left`; blind alternates probes;
family-prior and no-probe route the public tie-break candidate. A fourth call
is recorded as rejected for every session, demonstrating persistent budget
authority.

## Result

| Arm | Held-out correct | Charged calls/case |
|---|---:|---:|
| Learned probe policy | **12/12** | 3 |
| Fixed probe | 9/12 | 3 |
| Blind probe | 9/12 | 3 |
| Family prior | 6/12 | 3 |
| No probe | 6/12 | 3 |

This establishes the next lever after Round N's valid negative: when passive
traces carry no route information, a learned choice of an allowed *active
experiment* can acquire it at an equal enforced cost. It remains controlled:
the probe alphabet, trace classes, public history, candidates, fixture, and
scoring interface are supplied. It is not open-ended experiment invention.

## Robustness checks

- reverse held-out order and frozen-history order;
- alternate blind probe order / duplicate-balanced 3/3 trace-by-candidate
  fixture;
- opaque tokens are ledger-only and never passed to policy;
- scan generated public ledger for formula, family label, hidden data, masks,
  test labels, or manifest fields;
- log every action row and reject a fourth session call.

## Reproduce

```bash
rm -rf /tmp/zig-o2-cache /tmp/zig-o2-global /tmp/probe_policy_o2
zig build-exe sparse_poly_discovery/probe_policy_round_o.zig -O ReleaseFast \
  --cache-dir /tmp/zig-o2-cache --global-cache-dir /tmp/zig-o2-global \
  -femit-bin=/tmp/probe_policy_o2
/tmp/probe_policy_o2 run results/probe_policy_round_o.csv
/tmp/probe_policy_o2 selftest
```
