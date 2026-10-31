# AI3 — independent hostile sandbox breakout audit

**Verdict: VALID NEGATIVE.** I fresh-built a separate attacker binary and
ran it inside the actual AI1 Bubblewrap profile, not merely through an
in-process allow/deny API. The tested profile was:

```text
bwrap --unshare-all --new-session --die-with-parent --clearenv \
  --ro-bind <attacker> /worker --proc /proc --dev /dev --tmpfs /tmp \
  /worker probe <attack>
```

It does successfully hide host `/etc`, host `HOME`, and the host process tree.
The actual Zig child-launch path also denied an intentionally open private
descriptor: the attacker scanned `/proc/self/fd/3..63` for a launcher-held
sentinel and did not receive it. That is a real observed denial for this
launcher path, not a claim based only on Bubblewrap's name.

However, the boundary is **not capability-clean**. The hostile worker was
able to create an Internet socket, execute the only mounted worker binary as a
child, create a local Unix socket, signal namespace PID 1 with signal 0, read a
wall clock, and emit arbitrary extra stdout. New namespaces remove host
visibility; they do not remove these syscalls. The immutable executable bind
also has no independent hash/attestation or separate launcher identity.

## Actual attack evidence

| Attack | Observed | Interpretation |
|---|---|---|
| Host filesystem `/etc/passwd` | denied | Host filesystem not mounted. |
| Host environment (`HOME`) | denied | `--clearenv` worked in the hostile process. |
| Launcher-held private descriptor | denied | The actual Zig child launch did not pass the opened descriptor. This is not a general Bubblewrap guarantee; launchers must retain explicit FD hygiene. |
| Network socket creation | **allowed** | Network namespace prevents host networking but does not block the socket syscall. |
| Execute `/worker` again | **allowed** | A hostile worker can self-spawn without a syscall filter. |
| AF_UNIX socket creation | allowed locally | Host IPC is hidden, but local IPC remains possible. |
| Host process tree | denied | PID namespace showed only the sandbox namespace. |
| `kill(1, 0)` | allowed locally | It cannot address a host PID, but retains namespace-level process signalling. |
| Malformed / extra stdout | allowed by raw sandbox | AI2's actual collector separately rejected its 17-byte extra-output fixture; raw containment alone does not enforce the protocol. |
| Clock | allowed | No evaluator feedback was observed, but the sandbox does not remove timing. |
| Provenance substitution | unresolved | File bind is not binary attestation, an authority split, or a signed launch record. |

I independently fresh-built and ran AI2's transport selftest as a cross-check.
It byte-replayed and rejected short output, extra output, malformed input, and
noncanonical final streams; its interactive and reverse-read probes observed
EOF. That validates AI2's narrow transport claim, but it does not repair the
AI1 syscall breakouts above.

## Why this is a valid negative rather than an execution failure

The attack harness completed and replayed deterministically. It found real
remaining capability paths. Thus the correct result is not “sandbox failed to
run”; it is that this Linux Bubblewrap profile cannot establish the requested
claim that the mutant has no network/process/IPC/timing capability. AI4–AI6
must remain gated.

## Required next boundary

Before a capability-clean organism experiment, use an enforceable syscall
allowlist (for example, a correctly installed seccomp filter) plus explicit
close-all-except-stdio FD handling in a minimal separate launcher, and re-run
this external audit. The collector must retain AI2's exact post-exit stream
validation. Do not treat namespace isolation as a substitute for either.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/sandbox_breakout_audit_round_ai.zig -O ReleaseSafe \
  -femit-bin=/tmp/round-ai-ai3-audit --cache-dir /tmp/zig-cache-ai3 \
  --global-cache-dir /tmp/zig-global-ai3
/tmp/round-ai-ai3-audit selftest
/tmp/round-ai-ai3-audit run results/sandbox_breakout_audit_round_ai.csv

zig build-exe sparse_poly_discovery/one_way_transport_round_ai.zig -O ReleaseSafe \
  -femit-bin=/tmp/round-ai-ai2-audit
/tmp/round-ai-ai2-audit selftest
```

Expected AI3 selftest: `round_ai_ai3 selftest PASS deterministic=true
verdict=VALID_NEGATIVE network_spawn_breakouts=true fd_attack_denied=true`.
