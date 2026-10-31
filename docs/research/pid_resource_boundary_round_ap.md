# AP2 — PID and resource boundary

**Verdict: GATE READY for the exercised Bubblewrap-plus-hard-rlimit profile;
not a general cgroup or hostile-kernel containment proof.**

AP2 takes AO1's namespace/mount profile and adds a candidate-local wrapper that
lowers *both* soft and hard limits immediately after Bubblewrap has finished
its own setup and before candidate logic runs. The opaque candidate has one
stdin/stdout action channel; the evaluator owns the outside one-second wall
timeout and bounded stdout capture.

## Measured result

| Surface | Runtime observation | Result |
|---|---|---|
| Candidate baseline | one opaque raw action completed | pass |
| Process creation | one `fork` attempt returned `FORK:DENY` | enforced in this launch |
| File descriptors | only five retained `/dev/null` handles opened before the hard eight-FD limit | enforced |
| Address space | touching a 96 MiB allocation failed under 64 MiB hard `RLIMIT_AS` | enforced |
| CPU | non-yielding spin was signalled/killed at the one-second CPU/wall bound | enforced |
| Wall execution | a two-second sleep could not emit success before evaluator timeout | enforced |
| Output | 2 KiB stdout probe was stopped by the parent 192-byte capture cap | enforced |

The host exposes cgroup v2 controllers, including `pids`, but the current
same-user cgroup does **not** expose a writable `pids.max` leaf or delegated
subtree. AP2 therefore did not create a dedicated cgroup and does not claim a
cgroup process-count proof. The fallback is a hard `RLIMIT_NPROC=1` set inside
the post-Bubblewrap PID-namespace init. It demonstrably denied the one-child
probe in this actual environment. It is still not equivalent to a dedicated
cgroup: Linux accounts `RLIMIT_NPROC` by UID and behavior can depend on the
outer UID mapping and existing processes. A launch where this limit cannot be
lowered must be reported as **not enforced**, not assumed safe.

No seccomp syscall filter, separate host UID/MAC policy, hardware isolation,
or timing-side-channel closure is established by AP2. AP1 must independently
deny forbidden process/clock syscalls; AP4 must attack the integrated profile.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/pid_resource_boundary_round_ap.zig -O ReleaseSafe -femit-bin=/tmp/ap2-boundary
/tmp/ap2-boundary selftest
/tmp/ap2-boundary results/pid_resource_boundary_round_ap.csv
cp results/pid_resource_boundary_round_ap.csv /tmp/ap2-first.csv
/tmp/ap2-boundary results/pid_resource_boundary_round_ap.csv
cmp -s /tmp/ap2-first.csv results/pid_resource_boundary_round_ap.csv
```

The CSV is the authoritative receipt. `GATE_READY` is conditional on every
listed runtime probe recording `ENFORCED`; it does not overstate untested OS,
kernel, compiler, or hardware behavior.
