# O3 — independent active-probe protocol audit

**Verdict: PASS — the audit fixture admits conditional information only through charged probe replies; its public base trace, token, and test labels do not provide the answer.** This is a protocol-integrity result, not solver evidence.

Harness: `sparse_poly_discovery/probe_audit_round_o.zig`. Ledger: `results/probe_audit_round_o.csv`.

## Method and attacks

The audit independently builds six public base traces and counterfactually pairs every trace with both evaluator-private families. Eight train tokens (four paired signatures) may receive probes; four held-out tokens (two paired signatures) may not. Any deterministic base-trace classifier is therefore right once and wrong once per held-out signature: the frozen base router is **2/4**, at the family prior.

A charged candidate probe returns only an aggregate score (`12` or `8`) for the candidate just submitted. It never returns formula, family name, target ID, mask, threshold, seed, audit data, or a held-out label. This is legitimate conditional experimental evidence: the same candidate gets different aggregate responses on a counterfactual pair. It is not a public-token shortcut.

The CSV records every action in four cost-matched arms:

| Arm | Train tokens | Calls each | Total charged |
|---|---:|---:|---:|
| Policy probes | 8 | 3 | 24 |
| Fixed menu | 8 | 3 | 24 |
| Blind menu | 8 | 3 | 24 |
| No-probe control | 8 | 3 | 24 |

The no-probe control consumes evaluator budget but receives `NA`, not a score. Policy state is persisted after every action and read after a simulated restart. A held-out probe attack is denied before a response or label is created.

## Result

The ledger contains **96 individual train action rows**, one held-out denial, and two summaries. It passes base-trace, token-ID, token-rename, ordering, counterfactual-duplicate, private-field, held-out-label, restart persistence, and equal-cost tests. The base router is 2/4 held-out; each arm spends 24 calls (96 total).

## Scope limit

This proves an API design can expose experimental evidence without handing over an answer key. It does **not** prove that a policy uses probes well, that this synthetic score model is natural, or that OS/process isolation protects evaluator privacy. Solver success must be established separately.

## Reproduce

```bash
rm -rf /tmp/zig-o3-cache /tmp/zig-o3-global /tmp/probe_audit_round_o
zig build-exe sparse_poly_discovery/probe_audit_round_o.zig -O ReleaseFast \
  --cache-dir /tmp/zig-o3-cache --global-cache-dir /tmp/zig-o3-global \
  -femit-bin=/tmp/probe_audit_round_o
/tmp/probe_audit_round_o results/probe_audit_round_o.csv
/tmp/probe_audit_round_o selftest > /tmp/probe_audit_round_o.selftest.csv
cmp results/probe_audit_round_o.csv /tmp/probe_audit_round_o.selftest.csv
```
