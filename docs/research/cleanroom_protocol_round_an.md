# AN1 — clean-room evaluator/candidate protocol

**Verdict: GATE READY for the declared protocol boundary; INCONCLUSIVE for hostile OS containment.**

The evaluator is the parent process and independently launches a fresh candidate
child for each of eight fixed turns. The candidate receives one bounded opaque
observation frame (`O:nonce:observation`) and can return only one bounded action
frame (`A:nonce:0..3`) on stdout. Hidden observation construction, target/reward,
recoding nonce, aggregate score, and the transcript live in the evaluator.

The action schema has an exact nonce, range, newline, and 32-byte limit. A
candidate request for `SCORE` is denied; a malformed/oversized nonce/action plus
extra output is denied. No progress or score is sent during the eight turns;
only the evaluator writes the end-of-run aggregate. The CSV is deterministic
under two fresh executions.

This demonstrates a real local process and byte protocol separation, not a
security theorem. The candidate is still a same-user local process with inherited
OS rights: no seccomp syscall policy, namespace, UID separation, hardware root,
or adversarial binary containment is present. Therefore it is appropriate for
replaying behavioral experiments behind an evaluator-owned protocol, but not yet
for claiming that a malicious candidate cannot inspect/corrupt host resources.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/cleanroom_protocol_round_an.zig -O ReleaseSafe -femit-bin=/tmp/an1-cleanroom
/tmp/an1-cleanroom selftest
/tmp/an1-cleanroom results/cleanroom_protocol_round_an.csv
cp results/cleanroom_protocol_round_an.csv /tmp/an1-first.csv
/tmp/an1-cleanroom results/cleanroom_protocol_round_an.csv
cmp -s /tmp/an1-first.csv results/cleanroom_protocol_round_an.csv
```
