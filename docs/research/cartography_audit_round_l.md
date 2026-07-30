# L5 — cartography audit of the revised sealed API and L4 expedition

**Verdict: L4 is a valid negative, not a block and not a positive.** The
revised L3 API supplies public diagnostics and candidate testing, so the trial
is defined. L4 made one strict exact win, not the two required by its frozen
criterion.

## Independent findings

- **L1:** the atlas is evidence on its controlled corpus only; it does not yet
  establish generalization to unknown target families.
- **L2:** its detector consumes only four trace maxima, but its published CSV
  contains audit columns and its known/blank construction cycles by target ID.
  It remains a limited controlled test.
- **L3:** diagnostics and query replies expose aggregate score, count, and
  charged-call fields—not formula, mask, or audit fields. The boundary is
  protocol-level, not OS isolation. Query scoring uses the same twelve seeded
  examples exposed as labels in the transcript, so it is not a fresh holdout.
- **L4 eligibility:** `L3-00` and `L3-01` are blank; `L3-02` is represented
  at 12/12.
- **L4 enumeration:** every canonical threshold candidate identity 0–79 occurs
  exactly once for each blank token. Candidate ordering cannot explain the
  outcome.
- **L4 result:** `L3-00` gets 10/12 versus existing menu 11/12; `L3-01` gets
  12/12 versus 10/12. That is one strict exact win, while two were required.

## Accounting limitation

The L4 source executes 80 candidate calls plus 332 redundant sentinel calls to
reach 412 on each blank token. Its CSV records the 80 canonical calls and the
412-call summary, but not individual padding calls. Source replay supports the
total, yet the raw ledger is not complete per-call accounting. This prevents a
strong future positive cost claim; it cannot make L4's failure on `L3-00` a
positive or a protocol block.

## Consequence

The public API fixed the missing test-bench interface. It did not demonstrate
autonomous family invention: the extension language was predeclared, evaluation
used exposed labels, and the extension failed to transfer across both blank
tokens. A future positive needs a fresh sealed test split and a ledger that
records every charged call.

## Reproduce

```bash
rm -rf /tmp/zig-l5-cache /tmp/zig-l5-global /tmp/cartography_l5
zig build-exe sparse_poly_discovery/cartography_audit_round_l.zig -O ReleaseFast \
  --cache-dir /tmp/zig-l5-cache --global-cache-dir /tmp/zig-l5-global \
  -femit-bin=/tmp/cartography_l5
/tmp/cartography_l5 results/cartography_audit_round_l.csv
/tmp/cartography_l5 selftest > /tmp/cartography_l5.selftest.csv
cmp results/cartography_audit_round_l.csv /tmp/cartography_l5.selftest.csv
```
