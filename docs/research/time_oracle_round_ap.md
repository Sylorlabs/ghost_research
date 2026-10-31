# AP3 — time-oracle reduction and logical-turn protocol

**Verdict: INCONCLUSIVE for time-oracle containment.**

AP3 measures a real, enabled restriction rather than treating a protocol rule as
a capability boundary. A fresh candidate process runs inside the AO1-style
Bubblewrap namespace profile (clear environment, private `tmpfs`, separate
PID/IPC/UTS/network namespaces, dropped capabilities, bounded address space and
CPU), then loads a libseccomp deny policy before either probing time or handling
the protocol. The candidate has only raw stdin/stdout.

The experiment has two independent portions.

1. A hostile direct-time probe invokes the Linux `SYS_clock_gettime`,
   `SYS_gettimeofday`, `SYS_time`, and `SYS_nanosleep` system calls after the
   filter loads. All four returned denied. The libc `nanosleep` wrapper was also
   denied.
2. A logical-turn candidate consumes exactly four opaque observations and emits
   four strict raw actions. The observations contain neither elapsed time,
   progress, score, target, evaluator-response pacing, nor a semantic label.
   Two fresh restricted executions produced byte-identical action transcripts.

## What the measurement established

- Direct kernel clock, wall-time, and sleep syscalls were denied by the enabled
  libseccomp profile in the actual candidate process.
- The fixed-turn protocol does not disclose an explicit elapsed/progress/score
  field, and an output that is not an `ACT:turn:value` frame is not an action.
- The four-turn raw observation/action exchange is deterministic on fresh
  replay. This supports logical turns as a protocol discipline, not as proof
  that real elapsed time has vanished.

## Why this is not gate-ready

On this host, libc `clock_gettime` and `gettimeofday` succeeded even after the
direct syscalls were denied. They can use the kernel-provided vDSO page entirely
in user space, where a syscall filter does not intervene. That is an observed
result, not a hypothetical caveat.

More fundamentally, direct API denial does not remove physical timing channels:
CPU progress, cache state, scheduler effects, branch behavior, and other
microarchitectural observations remain. The candidate could encode timing in
the allowed raw-action stream unless a stronger design constrains execution and
the evaluator independently controls the schedule. The strict grammar prevents
timing-*formatted* output from becoming a valid action; it cannot prove a
candidate did not choose an allowed action after observing physical time.

There is also an enforcement limitation. The seccomp filter is loaded by the
tested candidate binary itself. It is active and measured for this artifact,
but a hostile replacement candidate could omit that call. AP1 must install the
policy before untrusted candidate code begins (for example via a launcher-owned
filter FD or a dedicated small trusted wrapper), then AP4 must attack that
process-level boundary. This experiment does not claim absolute containment
against the kernel, compiler, Bubblewrap, hardware, or side channels.

## Result

AP3 is useful infrastructure evidence: direct time and sleep syscalls can be
removed while a raw fixed logical-turn protocol still runs deterministically.
It is **inconclusive** as a no-time-oracle claim because vDSO clock reads and
physical timing remain, and because the policy is not yet launcher-enforced.
It does not establish any intelligence or invention result.

## Reproduce

```sh
zig build-exe sparse_poly_discovery/time_oracle_round_ap.zig -O ReleaseSafe -lc -lseccomp -femit-bin=/tmp/ap3-time
/tmp/ap3-time selftest
/tmp/ap3-time results/time_oracle_round_ap.csv
cp results/time_oracle_round_ap.csv /tmp/ap3-first.csv
/tmp/ap3-time results/time_oracle_round_ap.csv
cmp -s /tmp/ap3-first.csv results/time_oracle_round_ap.csv
```

The expected self-test line is:

```text
round_ap_ap3 selftest PASS direct_syscalls=denied logical_turns=deterministic verdict=INCONCLUSIVE
```
