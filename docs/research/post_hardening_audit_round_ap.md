# AP4 — post-hardening hostile runtime audit

**Verdict: GATE READY within the declared local Linux/process threat model.**
This is a runtime attack of the combined launcher, not a source-only review.
Fresh hostile candidate modes were executed through AO1's Bubblewrap profile
(private mount namespace, PID/IPC/UTS/network namespaces, dropped
capabilities, empty environment, private tmpfs work directory and closed
extra descriptors), AP1's Bubblewrap-owned pre-exec seccomp BPF plus the
post-loader bootstrap filter, AP2's address-space/CPU/FD/output bounds, and an
evaluator-owned AO3-style strict transcript and budget.

The candidate received one opaque observation. The parent evaluator held its
hidden target/reward file outside the mount namespace and accepted only one
exact raw action. It never supplied a score during the run.

## Executed attacks

| Route | Runtime observation | Result |
|---|---|---|
| Evaluator file | `SECRET:EPERM` | denied |
| `/proc` / descriptor inspection | `PROC_FD:EPERM` after final `openat` denial | denied |
| Environment and cwd | one non-secret environment entry and `/work` | contained; no evaluator data |
| Process, exec, file, socket, mount, signal | each direct raw syscall returned `EPERM` | denied |
| Network / IPC | fresh network and IPC namespaces plus socket denial | denied by the combined profile |
| Score request, multi-frame injection, oversize output | strict evaluator rejected whole hostile stdout | denied; transcript unchanged |
| Forged, reordered and replayed action | strict nonce/turn/budget validation rejected | denied; transcript unchanged |
| Transcript/budget/score corruption | every rejected frame left chain and turn unchanged | contained |
| Bounded PID/resource attempt | one million direct `fork` attempts completed only as seccomp `EPERM` returns; parent resource bounds remained external | contained |
| Direct clock and sleep syscalls | `EPERM` | denied |
| libc/vDSO `clock_gettime` and `gettimeofday` | succeeded without a kernel syscall | residual only |

The vDSO observation is deliberately not erased by the verdict. It means this
profile does **not** eliminate physical or user-space timing side channels.
In this executed test, however, the candidate's time read had no channel to
read evaluator state, no interim score/response-pacing field, no network/IPC
route, and no ability to alter the transcript. It is therefore recorded as a
residual side-channel assumption rather than an executed evaluator leak or
corruption path.

## Interpretation

`GATE_READY` here is narrow: every executed evaluator-leak, evaluator-
corruption, process-creation, network, filesystem, protocol, direct-time, and
resource route was denied or contained, while a normal opaque action still
worked. It does not establish absolute impossibility. The dynamic loader and
trusted bootstrap, the deny-list's unlisted syscalls, Bubblewrap, seccomp,
kernel, compiler, hardware, and physical/microarchitectural side channels
remain in the trusted/residual base.

This clears the process-boundary prerequisite for replaying AM2 unchanged
through the wall. It does not itself certify AM2's behavioral claim.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/post_hardening_audit_round_ap.zig \
  -O ReleaseSafe -lc -lseccomp -femit-bin=/tmp/ap4-audit \
  --cache-dir /tmp/zig-ap4-cache --global-cache-dir /tmp/zig-ap4-global
/tmp/ap4-audit selftest
/tmp/ap4-audit results/post_hardening_audit_round_ap.csv
cp results/post_hardening_audit_round_ap.csv /tmp/ap4-first.csv
/tmp/ap4-audit results/post_hardening_audit_round_ap.csv
cmp -s /tmp/ap4-first.csv results/post_hardening_audit_round_ap.csv
```

Fresh self-test and two independent result runs were byte-identical.
