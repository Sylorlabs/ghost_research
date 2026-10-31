# AI1 — raw-medium process sandbox

**Verdict: VALID NEGATIVE.** This is a real local process and namespace
boundary, not an API convention: a static worker was launched by Bubblewrap
0.11.0 with fresh user, PID, mount, IPC, UTS, and network namespaces. Its
mount table contains only its static `/worker` executable, fresh `/tmp`,
`/proc`, and `/dev`; its environment is cleared. It receives eight raw bytes
on stdin and emits eight transformed raw bytes on stdout. Fresh runs replay
byte-identically.

It does not meet the Round AI containment gate. Two hostile worker probes
actually succeeded: an `AF_INET` socket creation and `fork` followed by
`waitpid`. A private network namespace prevents access to the host network,
and a private PID namespace hides the host process tree, but neither is a
syscall prohibition. Bubblewrap alone, with no supplied seccomp BPF policy,
leaves those syscalls available. Therefore a mutant is not prevented from
using *all* process or network mechanisms; it is invalid to claim a
capability-clean organism runtime from this launcher.

## What ran

The test uses a uniquely created disposable `/tmp/ai1-build*` compilation
directory and a statically linked Zig executable. Static linking matters here:
the worker needs no dynamic loader or shared-library mount. The launcher is:

```text
bwrap --unshare-all --new-session --die-with-parent --clearenv
  --ro-bind <static-worker> /worker --proc /proc --dev /dev --tmpfs /tmp
  /worker worker
```

No system configuration, root privilege, persistent mount, or sudo operation
was used. `bwrap`, `unshare`, and `setpriv` were present locally. Bubblewrap's
fresh namespace launcher executed successfully on Linux
`7.0.11-76070011-generic`.

## Evidence ledger

| Attack or property | Actual result | Interpretation |
|---|---|---|
| Raw stdin to raw stdout | pass | The worker consumed exactly eight raw bytes and produced exactly eight bytes. |
| Fresh replay | pass | Two separately launched namespaces produced byte-identical output. |
| Host filesystem via actual worker `open("/etc/passwd")` | denied | The worker received an OS-level open failure because no host root mount exists. |
| Host environment | denied | `--clearenv` supplied no inherited secret or variable. |
| Host IPC | denied | Fresh IPC namespace exposes no host IPC objects. |
| Host parent/process tree | denied | Fresh PID namespace `/proc` does not expose the host parent tree. |
| Evaluator data | denied by mount/interface | No evaluator file, callback, or descriptor is intentionally mounted. |
| Inherited descriptors | restricted | stdin/stdout/stderr remain the transport descriptors; no evaluator FD is passed. |
| Actual `AF_INET` socket syscall | **available** | Namespace isolates it from host interfaces but does not forbid the syscall. |
| Actual `fork`/`waitpid` syscall | **available** | PID namespace hides host processes but does not prohibit child creation. |

The source and complete raw ledger are [raw_process_sandbox_round_ai.zig](../../sparse_poly_discovery/raw_process_sandbox_round_ai.zig)
and [raw_process_sandbox_round_ai.csv](../../results/raw_process_sandbox_round_ai.csv).

## Why this is a negative result, not an operational failure

The experiment succeeded at demonstrating exactly what the selected mechanism
provides: mount, environment, IPC, host-PID, and external-import isolation in a
separate process. It also found a concrete limitation through executed worker
code rather than assuming the mechanism was stronger than it is. That is a
valid negative for the claim that the mutant may use *only* raw transport.

This does not measure intelligence, persistence, self-assembly, or
open-endedness. It is infrastructure evidence only.

## Required next boundary

The missing layer is a separately tested syscall policy, such as a BPF
seccomp filter installed before untrusted worker execution, or an equivalently
enforceable local mechanism. It must permit only the raw transport, memory,
exit, and bounded time primitives actually required by the medium, while
denying network socket, fork/clone/exec, filesystem-open beyond preopened
transport, IPC, signal abuse, and descriptor duplication. That policy must be
tested from inside the worker and independently audited; merely naming seccomp
will not count.

## Reproduce

```bash
task_dir=$(mktemp -d /tmp/ai1-build.XXXXXX)
zig build-exe sparse_poly_discovery/raw_process_sandbox_round_ai.zig \
  -O ReleaseSafe -femit-bin="$task_dir/ai1" -fstrip -static \
  --cache-dir "$task_dir/cache" --global-cache-dir "$task_dir/global"
"$task_dir/ai1" selftest
"$task_dir/ai1" run results/raw_process_sandbox_round_ai.csv
```

Expected self-test:

```text
round_ai_ai1 selftest PASS deterministic=true bwrap_real=true
verdict=VALID_NEGATIVE residual=network_and_spawn_syscalls
```
