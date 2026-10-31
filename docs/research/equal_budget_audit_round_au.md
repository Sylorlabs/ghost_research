# AU3 — Equal-budget measurement audit

**Status:** MEASUREMENT READY. This is not an intelligence result.

AU3 prevents the Round AS3 failure mode: each of seven policies receives the
same 12 opaque deterministic instances, 120 receipts, 5 steps/instance,
2 tool calls/step, one restart/instance, and the identical receipt schema.
The harness derives hit totals and all reported numbers by scanning emitted
receipt rows; it contains no result curves or winner verdict literals.

Policies are candidate, fixed, broad, random, replay, no-memory, and
no-repair. They differ only in a precommitted deterministic action rule. The
fixture target is evaluator-side and is never passed to the policy rule.

Fresh `selftest` emits two ledgers and requires byte-identical replay. It also
injects and rejects unequal row budgets and different-input/target-leak shapes.
Hardcoded curves are structurally excluded because no curve field exists; the
only summary is reconstructed from receipts. Claims are written per receipt
before the aggregate is computed, which makes post-hoc score rewriting
auditable.

Run:

```sh
zig run sparse_poly_discovery/equal_budget_audit_round_au.zig -- selftest
zig run sparse_poly_discovery/equal_budget_audit_round_au.zig -- run results/equal_budget_audit_round_au.csv
```

**Limits:** the fixtures are deliberately synthetic and opaque. AU3 proves only
that this measurement protocol enforces equality and replay; it does not show
learning, tool invention, real-artifact transfer, or intelligence.
