# M6 — independent Round M audit

**Verdict: M5 survives as a NARROWED CONTROLLED STRICT POSITIVE.** The claimed
numbers are real in the published deterministic protocol: the closed loop is
**72/72**, versus frozen existing menu **36/72** and trace-blind control
**54/72**, with exactly **29 individually recorded charged calls per arm per
target**. This audit does not invalidate that bounded claim.

Harness: `sparse_poly_discovery/round_m_audit.zig`.
Audit ledger: `results/round_m_audit.csv`.

## Independent replay

Fresh-cache builds and deterministic selftests passed for all five upstream
harnesses. The audit then read the canonical ledgers directly.

| Component | Audit result |
|---|---|
| M1 | Pass: public train/query/test contract, persistent restart accounting, and exhausted next-call check are present. It remains protocol-level, not OS isolation. |
| M2 | Pass, controlled: trace-only splitter reports 12/12 heldout versus 6/12 unsplit. It is an intentionally synthetic two-region construction. |
| M3 | Pass, limited: fresh within-region transfer 48/48; cross-region and equal-cost menu 24/48. |
| M4 | Pass, controlled: trace-derived two-candidate grammar 48/48 against equal-cost frozen menu 24/48 on its separate four cells. |
| M5 | Pass: 522 action rows = 6 opaque targets × 3 arms × 29 calls. Every target/arm contains exactly calls 1–29 once. Closed loop has 96 training queries, 6 frozen choices, and 72 fresh tests; each control has 102 pretest charges and 72 fresh tests. |

The M5 public ledger contains only the six M5 opaque tokens and no M4 tokens,
private-region field, seed, formula, family label, hidden field, or test label.
The source’s reversed token/candidate replay also passed.

The audit initially found an M5 header/action-row field-count mismatch. The
coordinator corrected the header, regenerated the canonical M5 ledger, and
reran this audit. The final ledger has a matching ten-field schema and the
same accounting totals; this defect no longer narrows the result.

## Why the claim is narrowed

The new outcome is not a general discovery result. The sealed target generator
was deliberately built so its two-number public trace selects one of two public
bit predicates; the query phase chooses polarity. Thus the result proves the
full **enforced, fresh-test loop** works in this supplied two-slot synthetic
world. It does not show that the system discovered a new region ontology,
invented an unconstrained tool language, or can generalize outside this
trace-to-predicate alignment. M1/M5 state files are persistent protocol
boundaries, not a separately protected evaluator service.

The fair statement is therefore:

> Within the fixed public alphabet and intentionally aligned synthetic target
> generator, M5 has a genuine equal-cost fresh-test win. It is not evidence of
> open-ended autonomous map-making.

## Reproduce

```bash
rm -rf /tmp/zig-m6-cache /tmp/zig-m6-global /tmp/round_m_audit
zig build-exe sparse_poly_discovery/round_m_audit.zig -O ReleaseFast \
  --cache-dir /tmp/zig-m6-cache --global-cache-dir /tmp/zig-m6-global \
  -femit-bin=/tmp/round_m_audit
/tmp/round_m_audit run results/round_m_audit.csv
/tmp/round_m_audit selftest
cmp results/round_m_audit.csv /tmp/round_m_audit.selftest.csv
```
