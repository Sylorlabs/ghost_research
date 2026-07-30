# AO3 — evaluator integrity and tamper evidence

**Verdict: GATE READY for deterministic evaluator-owned transcript integrity at
the declared byte-protocol layer; inconclusive for cryptographic or hostile-OS
security.**

The prototype gives the evaluator exclusive ownership of a fixed four-turn
budget, nonce stream, transcript, chain state, and end-only aggregate score. A
candidate may emit only the exact raw frame `ACT:<nonce>:<turn>:<0..3>\n`. It
cannot request or write a score, target, transcript, or evaluator state through
the declared protocol.

Each evaluator-appended record carries a deterministic chained integrity tag
over the preceding tag, evaluator-generated nonce, turn, and raw action. The
tag uses a process-private constant in this local prototype. It is deliberately
described as MAC-like bookkeeping, **not a cryptographic MAC**, and does not
establish hostile process/OS isolation.

The deterministic fixture run accepts four normal actions and then records:

- forged nonce: rejected;
- reordered action: rejected;
- replayed action and fifth action after budget: rejected;
- early score request, score mutation, and evaluator-state write: rejected by
  the strict action schema;
- transcript value alteration and tag alteration: detected by recomputation.

No interim score is emitted; the aggregate is written only at the fixed end of
the run. Two fresh executions produce byte-identical CSV evidence.

## Limits

This is local integrity evidence for the declared evaluator protocol. A
same-user hostile process could still attack host resources unless AO1/AO2 add
and test actual capability isolation. The deterministic private checksum is not
resistant to a candidate that can read process memory/source or alter the
evaluator process. This result must not be used to claim cryptographic proof,
hostile containment, or corruption-proof evaluation.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/evaluator_integrity_round_ao.zig -O ReleaseSafe -femit-bin=/tmp/ao3-integrity
/tmp/ao3-integrity selftest
/tmp/ao3-integrity results/evaluator_integrity_round_ao.csv
cp results/evaluator_integrity_round_ao.csv /tmp/ao3-first.csv
/tmp/ao3-integrity results/evaluator_integrity_round_ao.csv
cmp -s /tmp/ao3-first.csv results/evaluator_integrity_round_ao.csv
```
