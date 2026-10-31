# AP1 — measured candidate syscall policy

**Verdict: GATE READY (bounded).** A real libseccomp-generated cBPF program
was exported to a host-owned FD and supplied to Bubblewrap through `--seccomp
FD`. Bubblewrap installed that filter before it `exec`ed the candidate. A
small trusted in-binary bootstrap then installed a second filter before reading
the opaque input frame or dispatching the candidate probe. This two-stage
ordering is necessary for the dynamically linked Zig candidate: its loader
needs `execve` and `openat` during process startup, so those calls cannot be
blocked by the first pre-exec filter without preventing the candidate from
starting at all.

The resulting stack is real enforcement, not a manifest claim:

- Pre-exec Bubblewrap cBPF returns `EPERM` for process creation, sockets and
  connects, namespace/mount changes, signals, and direct time/sleep calls.
- The trusted bootstrap loads the same deny rules plus `execve`, `execveat`,
  `open`, `openat`, `openat2`, and `creat`, before opaque-frame parsing and
  candidate-mode dispatch.
- A raw `OBS:opaque:7` input still produces the bounded `ACT:7:1` action.

## Runtime evidence

Every direct raw-syscall probe returned the configured `EPERM`: `fork`,
`clone`, `vfork`, `execve`, `openat`, `socket`, `connect`, `unshare`, `setns`,
`mount`, `kill`, `clock_gettime`, `gettimeofday`, and `nanosleep`. The CSV
records each individual observation. The test uses no process bomb or host
stressing attempt.

## Reproduction

```sh
zig build-exe sparse_poly_discovery/syscall_policy_round_ap.zig -O ReleaseSafe -lc -lseccomp -femit-bin=/tmp/ap1
/tmp/ap1 selftest
/tmp/ap1 results/syscall_policy_round_ap.csv
```

Two fresh runs generate byte-identical CSVs. `strace -f -e seccomp,prctl`
also observed Bubblewrap's `PR_SET_SECCOMP` before candidate execution and the
candidate bootstrap's subsequent `SECCOMP_SET_MODE_FILTER` load.

## Limits

This is a deny-list compatible with the Zig dynamic runtime, **not** the
ideal minimal allow-list. Unlisted syscalls remain allowed, and the trusted
bootstrap exists before the final layer is loaded. The kernel, seccomp,
Bubblewrap, dynamic loader, same Unix identity, compiler, hardware, and
physical/microarchitectural side channels remain in the trusted or residual
base. This result does not claim absolute containment. AP2's PID/resource
boundary and AP3's protocol-time work remain necessary, followed by AP4's
independent integrated attack.
