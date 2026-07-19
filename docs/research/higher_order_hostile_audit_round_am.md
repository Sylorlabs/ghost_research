# Round AM / AM6 — independent hostile reconstruction

**Verdict: INCONCLUSIVE — do not upgrade AM2/AM4/AM5 to an independently
isolated foundation.** The reported synthetic contrasts and equal charged-contact
arithmetic reconstruct from source and generated ledgers, but policy, hidden
target construction, and evaluator are compiled in the same process. AM2 also
assigns `degree(c, record)` directly rather than deriving it across an enforced
environment boundary.

## What independently reconstructed

- AM2 ledger: topology 24,960 at 1,536 contacts versus fixed vector 1,560,
  last outcome 8,320, graph/schedule 9,100, and other listed controls.
- AM4 ledger: chain 3,600 at 1,920 contacts versus broad coverage 1,660 and
  topology/value/arbitration ablations.
- AM5 ledger: portfolio 5,760 at 4,320 contacts versus schedule 1,400; its
  same-reuse wrong-record control is 0.
- Contact accounting independently recomputes as `96×16=1,536`,
  `120×16=1,920`, and `96×3×15=4,320`.

## Hostile finding

Static controls and causal ablations exist, so the recorded contrast is real
within these deterministic fixtures. But AM4 places `hiddenQueryRecord` and
`evaluateAfterCharge` alongside `runPolicy`; AM5 similarly places
`targetAction` and `reward` alongside `runPolicy`. A different candidate in
the same compilation unit could call those helpers. The source manifest checks
declared record fields only—it cannot enforce that information boundary.

No separate evaluator process, capability boundary, syscall policy, or hostile
runtime containment was exercised. This is not a negative result about the
fixture contrast. It is **inconclusive** for autonomy/security because the
claimed evaluator isolation is not actually enforced.

## Required repair

Move hidden world/evaluator construction into a capability-limited separate
process. The candidate should receive raw observations and submit raw actions
only, with no callable target/reward helper. Replay AM2–AM5 under the same
contact budgets, then rerun this audit.

## Reproduce

```bash
mkdir -p /tmp/zig-am6-cache /tmp/zig-am6-global
zig build-exe sparse_poly_discovery/higher_order_hostile_audit_round_am.zig \
  -femit-bin=/tmp/higher-order-hostile-am6 \
  --cache-dir /tmp/zig-am6-cache --global-cache-dir /tmp/zig-am6-global
/tmp/higher-order-hostile-am6 selftest
/tmp/higher-order-hostile-am6 run results/higher_order_hostile_audit_round_am.csv
```
