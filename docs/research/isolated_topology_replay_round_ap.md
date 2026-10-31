# AP5 — isolated replay of AM2 intervention topology

**Verdict: FOUNDATION POSITIVE, bounded to this sealed causal-family fixture.**

AP5 reran AM2 at its original budget (96 cohorts x 16 charged raw contacts,
1,536 contacts per arm), but moved the candidate outside the evaluator
executable. The evaluator owns the hidden target, changed causal law, private
recoding, nonce, transcript, and end-only reward. For every cohort it starts a
fresh separately compiled C candidate under the AP4-equivalent Bubblewrap
profile. The candidate sees only one opaque raw frame containing three earned
intervention-to-later dependency observations and one shifted query observation;
it returns a bounded record index. It has no target/reward symbols or linkage.
Each evaluator invocation creates its candidate source and executable under a
PID-unique `/tmp/ap5-candidate-<pid>` path, so independent fresh replays cannot
race over a shared candidate path; the invocation removes those temporary files
afterwards.

The earned topology policy scored **24,960 / 96**. Every equal-cost control was
lower: fixed graph/vector/schedule 9,100; last outcome 8,320; random and
shuffled 10,140; replay 7,800; answer-scrub and topology ablation 7,540.
All arms accepted 96 bounded frames and spent exactly 1,536 charged contacts.

## Boundary receipt

Each fresh candidate is a separate `/candidate` executable in a private
Bubblewrap mount namespace with empty environment, private `/tmp` and `/work`,
closed extra descriptors, user/PID/IPC/UTS/network namespaces, dropped
capabilities, and evaluator paths absent. Candidate startup then installs a
second seccomp filter denying process creation, exec, open, sockets, mounts,
signals, and direct clock/sleep syscalls; the launcher imposes address-space,
CPU, FD, output, and wall-time bounds. The AP4 hostile attack remains the
boundary receipt for these launcher conditions.

This is not an absolute containment theorem. Kernel, Bubblewrap, seccomp,
dynamic-loader/bootstrap, compiler, hardware, and residual vDSO/physical timing
are named trusted/residual assumptions. The result demonstrates that the AM2
behavioral contrast survives this tested process wall; it does not establish
open-ended autonomy or general intelligence.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/isolated_topology_replay_round_ap.zig \
  -O ReleaseSafe -lc -femit-bin=/tmp/ap5 \
  --cache-dir /tmp/zig-ap5-cache --global-cache-dir /tmp/zig-ap5-global
/tmp/ap5 selftest
/tmp/ap5 run /tmp/ap5-first.csv
/tmp/ap5 run results/isolated_topology_replay_round_ap.csv
cmp -s /tmp/ap5-first.csv results/isolated_topology_replay_round_ap.csv
```

`selftest` is a two-frame clean-room smoke test and prints an explicit PASS.
The separate full `run` command performs the original 96 x 16 ledger; two full
runs are compared byte-for-byte above. Keeping those concerns separate avoids
thousands of namespace launches inside a generic test harness process group.
