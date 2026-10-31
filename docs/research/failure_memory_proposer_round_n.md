# N3 — frozen failure-memory proposer

**Verdict: CONTROLLED LIMITED POSITIVE.** A proposer that derives a
diagnostic-conditioned primitive ranking from a frozen ledger of prior raw
outcomes selects the successful primitive on **12/12** held-out opaque cases.
The globally best family-prior control scores **6/12** and the history-free
round-robin blind control scores **4/12**.

Harness: `sparse_poly_discovery/failure_memory_proposer_round_n.zig`.
Ledger: `results/failure_memory_proposer_round_n.csv`.

## What is available to the proposer

Before any held-out case is considered, it receives 24 shuffled public rows:
an aggregate diagnostic bin (`d0` through `d3`), a public primitive name, and
the observed result of that historical trial. For a new case it receives only
its aggregate diagnostic bin. It computes empirical success rates per
diagnostic/primitive cell and freezes the highest ranked primitive before the
evaluator returns that case's result.

The chooser is not passed an opaque token, target identity, formula,
mechanism/family label, mask, hidden parameters, audit/test label, or a
pre-written diagnostic-to-winner table. The public history is raw successes
and failures; its ranking is calculated from those rows.

## Result

| Policy | Held-out correct choices | Comparison |
|---|---:|---|
| Frozen failure-memory ranking | **12/12** | learned per-diagnostic empirical rank |
| Family-prior control | 6/12 | one global historical winner, tie-broken publicly |
| Blind control | 4/12 | round-robin, no history |

The current diagnostic alone is deliberately only a residual-bin symbol: no
fixed trace-direction rule is included in the policy. The improvement comes
from joining that symbol with historical outcomes. This is a controlled
proposal-selection result, not evidence of open-ended representation learning:
the primitive alphabet, four diagnostic bins, finite history, evaluator, and
synthetic outcome process remain supplied.

## Leakage and robustness attacks

- **History-order shuffle:** reverse the 24 historical rows; aggregate ranks
  and all totals are unchanged.
- **Opaque-ID/order attack:** reverse held-out presentation. IDs are logged for
  audit but never supplied to `choose`; totals remain unchanged.
- **Duplicate/candidate-order attack:** every diagnostic cell contains two
  identical-success repetitions for each primitive; the winning primitive is
  not a one-row accident. The controls are separately scored.
- **Private-field scan:** selftest rejects ledger appearances of winner,
  hidden data, formulas, family labels, masks, audit data, and test labels.
- **Deterministic replay:** two shuffled runs reproduce the same 12/12, 6/12,
  4/12 totals.

## Reproduce

```bash
rm -rf /tmp/zig-n3-cache /tmp/zig-n3-global /tmp/failure_memory_n3
zig build-exe sparse_poly_discovery/failure_memory_proposer_round_n.zig -O ReleaseFast \
  --cache-dir /tmp/zig-n3-cache --global-cache-dir /tmp/zig-n3-global \
  -femit-bin=/tmp/failure_memory_n3
/tmp/failure_memory_n3 run results/failure_memory_proposer_round_n.csv
/tmp/failure_memory_n3 selftest
```
