# P6 — independent forge audit

**Verdict: CONFIRMED, NARROWED.** Fresh-cache rebuilds of P1–P5 reproduced
their published CSVs byte-for-byte and all five selftests passed. The audit
confirms the Round P controlled forge result, while narrowing its meaning to a
supplied synthetic substrate and protocol-level privacy boundary.

Harness: `sparse_poly_discovery/round_p_audit.zig`. Ledger:
`results/round_p_audit.csv`.

## Confirmed

- **Score-private experience boundary:** P3's fixed attacks recover identity at
  1/12 and balanced hidden family, fresh outcome, winner, and target-to-tool
  association only at 6/12 chance. Eight injected answer-bearing fields are
  quarantined. The canonical record has no free-text, target, or answer-side
  join field.
- **Published answer boundary:** P1, P4, and P5 public schemas contain no
  target identity, token, family/formula, per-target fresh score/result,
  winner, or manifest column. P5's four closure rows are aggregate-only.
- **Forged measurement:** P4's count-then-compare program is nonredundant
  relative to the parity baseline and reproduces 12/12 versus 6/12 at one
  charged execution per validation session.
- **Forged operation and accounting:** P5 reproduces 24/24 aggregate fresh
  successes versus raw/fixed 0/24 and blind 8/24. Its public ledger contains
  exactly 288 charged actions: 24 sessions × four arms × recall/measurement/
  pre-score commitment. Every arm is charged three calls per session.
- **Replay defenses:** predecessor selftests cover normal/reverse traversal,
  duplicate/nonredundancy checks, persistent budgets, and private vocabulary
  scans. P5's per-kind forged shapes are structurally distinct from the raw
  XOR and fixed controls.

## Narrowed interpretation

This is **not** a broad, open-ended forge claim. The Boolean/count-comparison
atom grammar, causal classes, evaluator, task fixture, and scoring protocol are
supplied. Isolation is a deterministic **protocol boundary**, not an OS- or
process-isolated secret evaluator; an adversary able to inspect harness memory
or files is outside the demonstrated threat model. The result is therefore a
controlled answer-free experience → forged measurement → raw-atom composition
positive, not proof of unrestricted autonomous tool invention.

## Reproduce

```bash
rm -rf /tmp/zig-p6-cache /tmp/zig-p6-global /tmp/round_p_audit
zig build-exe sparse_poly_discovery/round_p_audit.zig -O ReleaseFast \
  --cache-dir /tmp/zig-p6-cache --global-cache-dir /tmp/zig-p6-global \
  -femit-bin=/tmp/round_p_audit
/tmp/round_p_audit run results/round_p_audit.csv
/tmp/round_p_audit selftest
```
