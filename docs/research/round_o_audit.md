# O6 — independent Round O red-team audit

**Verdict: CONFIRMED, NARROWED.** Fresh-cache rebuilds and independent ledger
recount confirm O5's controlled outcome: active **24/24**, fixed **12/24**,
blind **12/24**, and no-probe **12/24**, with four charged calls per token.
The result survives the stated trace, order, counterfactual-pair, duplicate,
cost, and commitment attacks.

Harness: `sparse_poly_discovery/round_o_audit.zig`. Ledger:
`results/round_o_audit.csv`.

## Replayed checks

- O1--O5 rebuild and selftest under separate fresh Zig caches.
- O1/O2/N2 support passive-trace decoupling: the trace-only route is at its
  balanced prior, not a hidden grammar router.
- The active reply is a charged aggregate conditional measurement, not a
  formula, family label, ID, mask, manifest, or target-name field.
- O5's frozen probe choice and grammar commitment occur before `fresh_test`;
  the 24 O5 tokens and three cohorts are distinct from O4.
- Exact ledger recount: 480 action rows, 120 per arm, 96 fresh-score rows,
  96 explicit rejected fifth calls, and 4 calls for every arm/token session.
- Equal-cost controls reproduce 24/24 active versus 12/24 each for fixed,
  blind, and no-probe. The active arm wins each stated 8-token cohort.

## Narrowing

O5's published reproducibility CSV includes a per-token `fresh_test` score
(`0` or `1`) after grammar commitment. Its frozen source has no post-score
branch, so this cannot explain the recorded within-run choice or invalidate
the equal-cost result. But it does mean the artifact is **protocol-sealed,
not score-private**: a later policy given that ledger could learn outcomes.
A stronger successor must withhold per-token test scores and release only
post-session aggregates, ideally through OS/process isolation.

The central result remains deliberately bounded. The probe alphabet, history,
two grammar choices, synthetic target relation, and evaluator are supplied;
this is not open-ended experiment or grammar invention.

## Reproduce

```bash
rm -rf /tmp/zig-o6-cache /tmp/zig-o6-global /tmp/round_o_audit
zig build-exe sparse_poly_discovery/round_o_audit.zig -O ReleaseFast \
  --cache-dir /tmp/zig-o6-cache --global-cache-dir /tmp/zig-o6-global \
  -femit-bin=/tmp/round_o_audit
/tmp/round_o_audit run results/round_o_audit.csv
/tmp/round_o_audit selftest
```
