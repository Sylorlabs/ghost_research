# AO1 — capability-hardened candidate launcher

**Verdict: GATE READY for the restrictions exercised at runtime.**

AO1 replaces AN1's merely separate child with a Bubblewrap-launched candidate.
The evaluator parent owns the hidden target/reward file and only sends the
candidate an opaque observation over stdin. The candidate can respond on stdout
with a bounded action. It receives a clear environment, private `/tmp` and
`/work` tmpfs mounts, a fresh user/PID/IPC/UTS/network namespace, and all Linux
capabilities dropped. `prlimit` imposes a 64 MiB address-space limit and a
one-CPU-second limit, which the child reads back from `/proc/self/limits`. The
evaluator private directory is not mounted.

Runtime probes record the candidate's cwd, environment, `/proc/self/fd` count,
absence and write-denial of the evaluator file, a valid raw action, a forbidden
score request, and oversized action handling. A fresh network namespace was
actually created (`--unshare-net` launch succeeded; its loopback has no traffic).
Fresh build and byte-identical CSV replay are required by `selftest`.

This is not an impossibility claim. Same-user kernel/OS, Bubblewrap, Zig,
compiler, hardware, namespace implementation, and the evaluator remain trusted.
No seccomp syscall allow-list, separate Unix identity, MAC policy, or hardware
virtualization is demonstrated here. The next hostile audit must attack the real
child launcher rather than treat this capability receipt as complete containment.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/capability_launcher_round_ao.zig -O ReleaseSafe -femit-bin=/tmp/ao1-launcher
/tmp/ao1-launcher selftest
/tmp/ao1-launcher results/capability_launcher_round_ao.csv
cp results/capability_launcher_round_ao.csv /tmp/ao1-first.csv
/tmp/ao1-launcher results/capability_launcher_round_ao.csv
cmp -s /tmp/ao1-first.csv results/capability_launcher_round_ao.csv
```
