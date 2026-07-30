# Q6 — independent Round Q expedition audit

**Verdict: CONFIRMED, WITH SCOPE NARROWED.** Fresh-cache rebuilds and selftests
of Q1–Q5 pass. The Q5 public ledger reproduces byte-for-byte, has 675 lines,
and confirms the aggregate score-private result: full expedition **24/24**,
fixed **0/24**, blind **8/24**, prior **0/24**, at six charged calls per arm
and session.

Harness: `sparse_poly_discovery/round_q_audit.zig`. Audit ledger:
`results/round_q_audit.csv`.

## Attacks and result

- **Provenance:** Q1 typed hashes/passports and Q3's missing/forged lineage,
  alias, forbidden-origin, evaluator-join, correlation, post-test selection,
  and free-text quarantine attacks pass.
- **Scout privacy:** Q2's public descriptor route contains no answer join; Q5
  ledger contains no target, formula, family, winner, score, token, manifest,
  private shape, or hidden-outcome field.
- **Forge novelty:** the canonical three-material fingerprint is present and
  Q4's component/fixed/blind/renamed controls reproduce.
- **Accounting:** 96 pre-score commitments, 96 sealed sixth calls, and 96
  rejected seventh calls are individually present; all four arms pay the same
  persistent six-call schedule. Aggregate closure is only after those rows.
- **Replay integrity:** fresh-cache Q1–Q5 selftests pass; Q5 regenerated CSV
  byte-compares to the canonical ledger.

## Interpretation

The controlled strict positive is confirmed: within the approved material
fixture, answer-free residuals and public provenance suffice for the full
scout → quarantine → forge → commitment → sealed-test loop to beat all listed
equal-cost controls.

It is **not** literal external-world discovery. The material universe,
descriptor vocabulary, and evaluator contract are supplied fixtures. The
boundary is protocol-sealed, not OS/process-isolated: this audit found no
evidence of an externally isolated evaluator or a live corpus/web adapter.
Those are missing-evidence limitations, not evidence of a leak in this run.

## Reproduce

```bash
rm -rf /tmp/zig-q6-audit-cache /tmp/zig-q6-audit-global /tmp/round_q_audit
zig build-exe sparse_poly_discovery/round_q_audit.zig -O ReleaseFast \
  --cache-dir /tmp/zig-q6-audit-cache --global-cache-dir /tmp/zig-q6-audit-global \
  -femit-bin=/tmp/round_q_audit
/tmp/round_q_audit run results/round_q_audit.csv
/tmp/round_q_audit selftest
```
