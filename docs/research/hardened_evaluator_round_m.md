# M1 — hardened evaluator and complete call ledger

**Verdict: positive evaluation infrastructure, not a discovery result.**

Harness: `sparse_poly_discovery/hardened_evaluator_round_m.zig`; raw charged
call ledger: `results/hardened_evaluator_round_m.ledger.csv`; checks:
`results/hardened_evaluator_round_m.csv`.

M1 replaces Round L's recorded-only budget with evaluator-owned persistent
state. The public train view contains only opaque tokens, opaque inputs, and
labels. The evaluator privately owns the target parameters and emits aggregate
scores only for diagnostics, candidate queries, and a fresh test split. It
records every charged action as one ledger row.

The deterministic selftest makes 12 charged calls: one baseline, one
diagnostic, three policy queries (one after a simulated separate-process
restart), two fresh-test calls, and five explicit padding calls. A thirteenth
query is rejected. The policy-schema attack adding `test_label` is rejected;
the public train view contains no private target field.

## Boundary

The state file survives a process restart, so restarting policy code cannot
reset budget. In an actual deployment, the evaluator must be a separately run
service or protected account that owns both state and private manifest. This
harness makes **no OS-isolation claim**: a user able to read this source and
the state path can bypass protocol boundaries. It is nevertheless a complete,
deterministic protocol/ledger foundation for M2–M6.

Reproduce:

```bash
zig build-exe sparse_poly_discovery/hardened_evaluator_round_m.zig -O ReleaseFast \
  --cache-dir /tmp/zig-m1-cache --global-cache-dir /tmp/zig-m1-global \
  -femit-bin=/tmp/hardened_m1
/tmp/hardened_m1 selftest results/hardened_evaluator_round_m.csv
```
