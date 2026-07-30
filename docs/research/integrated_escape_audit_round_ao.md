# AO4 — integrated runtime escape and evaluator-integrity audit

**Verdict: INCONCLUSIVE for hostile containment.**

AO4 launches deliberately hostile candidate fixtures through the actual AO1
Bubblewrap profile: fresh user/PID/IPC/UTS/network namespaces, clear environment,
private /tmp and /work tmpfs mounts, no mounted evaluator directory, only
stdio, dropped Linux capabilities, 64 MiB address-space limit, and one CPU
second. The evaluator parent retains a private target file and a one-record
nonce/turn/transcript chain. Each hostile run is fresh; after every run AO4
checks that the evaluator transcript is unchanged.

## What held at runtime

- Empty environment and sandbox-created cwd reveal no evaluator secret.
- Evaluator-private file read, write, and directory traversal were denied.
- No inherited descriptor above stdio was observed.
- /proc exposes only the child PID namespace; it cannot identify the host
  evaluator process from that view.
- Loopback connection attempt failed in the fresh network namespace; no IPC
  capability is mounted.
- Multi-line stdout injection, score request, oversized output, forged nonce,
  replay/reorder, and attempted score mutation were rejected as whole invalid
  actions. The evaluator nonce/budget/transcript chain stayed unchanged.

## What did not hold

The hostile child successfully read a monotonic clock and successfully created
and reaped one child process. These are bounded, safe probes: no resource storm
or host-stressing fork bomb was attempted. They nevertheless prove AO1 does not
yet have a syscall policy that removes timing or process-creation surfaces.
The current prlimit bounds CPU and address space, but does not turn fork or
clock reads into denied operations.

Therefore this is not a negative intelligence result and not a failed runtime
execution. It is an **inconclusive security audit**: the storage, namespace,
descriptor, network, and protocol portions held for the executed attacks, but
the complete “no possible corruption or escape” claim is not supported.

The remaining trusted computing base and untested surfaces are explicit:
seccomp filtering, distinct UID/MAC policy, cgroup/PID-count limit, kernel,
Bubblewrap, compiler, hardware, and microarchitectural side channels. No
absolute-security claim is made.

## Required repair before AM replays

Add an enforceable syscall/cgroup profile appropriate for the candidate language
runtime, then rerun this exact hostile audit. A GATE READY result requires all
executed routes to be denied or contained, including a process-creation and
timing policy; it cannot be inferred from source inspection alone.

## Reproduce

    zig build-exe sparse_poly_discovery/integrated_escape_audit_round_ao.zig -O ReleaseSafe -femit-bin=/tmp/ao4-audit
    /tmp/ao4-audit selftest
    /tmp/ao4-audit results/integrated_escape_audit_round_ao.csv
    cp results/integrated_escape_audit_round_ao.csv /tmp/ao4-first.csv
    /tmp/ao4-audit results/integrated_escape_audit_round_ao.csv
    cmp -s /tmp/ao4-first.csv results/integrated_escape_audit_round_ao.csv
