# S2 — Strong evaluator isolation

**Round:** S (architecture-completion wave)
**Status:** LIMITED POSITIVE — an enforced Linux namespace boundary, not a full production isolation deployment
**Harness:** `sparse_poly_discovery/strong_evaluator_isolation_round_s.zig`
**Ledger:** `results/strong_evaluator_isolation_round_s.csv`

## Question

Can the answer-bearing evaluator state be protected from a hostile policy process
by a real OS-enforced boundary rather than API denials and same-user `0600` file
modes?

## Threat model

The policy is treated as untrusted *after it is launched in the supplied
Bubblewrap sandbox*. It may run shell utilities and attempt direct evaluator
filesystem reads, persistent-budget reads/reset, `/proc` inspection, public
capability abuse, answer-token scanning, and unsupported manifest/score/state/
path/restart/reset/join operations. The evaluator's private manifest and budget
remain on the host outside the policy mount namespace.

This does **not** claim protection if untrusted code is allowed to execute on the
host outside Bubblewrap, is handed an evaluator file descriptor, or is given
host-administration privileges. That would be a category error, not a failed
test of this boundary.

## Actual boundary and result

The harness creates evaluator-owned storage with `0600` manifest and budget
files, but file permissions are only defense-in-depth. It launches each
hostile-policy attempt in Bubblewrap with new user, mount, PID, IPC, and UTS
namespaces; a fresh `/tmp`; a private `/proc`; no evaluator directory mount; no
writable evaluator capability; and an explicitly read-only receipt containing
only `anonymous_calibration_only` and `aggregate_closure_only`.

| Attack | Actual result |
|---|---|
| Direct manifest / budget read | **Denied:** host evaluator paths absent from sandbox `/tmp` |
| Host evaluator process inspection | **Denied:** a live, uniquely named host evaluator sentinel is absent from sandbox `/proc/*/cmdline` |
| Manifest/score/state/path/join request | **Denied:** no such capability is mounted |
| Restart or budget reset | **Denied:** no command or evaluator-state write mount |
| Answer leakage scan | **Denied:** no answer-bearing tokens in public receipt |
| Replay | **Pass:** two fresh hostile-policy namespaces both pass all denials |

This is materially stronger than R1: an attack runs in a real namespace and
cannot bypass the policy API by directly opening the host storage or inspecting
the evaluator process.

## Honest limits

This host allows unprivileged user/mount/PID namespaces and Bubblewrap, but the
following stronger controls were directly probed and are unavailable here:

| Control | Result | Consequence |
|---|---|---|
| Separate Unix evaluator identity | `setresuid` denied | Same-host defense depends on mandatory sandbox launch |
| Isolated network namespace | Bubblewrap loopback setup denied | Policy egress is not contained by this harness |
| Docker daemon/container deployment | unavailable | No independent container principal here |
| Unix-socket RPC | host runtime denies AF_UNIX bind | no live RPC service was falsely claimed |

Therefore this is a **limited positive**, not final production-grade evaluator
isolation. A deployment-grade close still needs a dedicated evaluator account
or VM/container, a network-egress policy, evaluator-owned durable storage, and
an authenticated narrow RPC endpoint. The harness explicitly refuses to call
same-UID file modes, an absent socket, or a failed network namespace “strong
isolation.”

## Reproduce

```bash
zig build-exe sparse_poly_discovery/strong_evaluator_isolation_round_s.zig -O ReleaseSafe \
  --cache-dir /tmp/zig-s2-cache --global-cache-dir /tmp/zig-s2-global -femit-bin=/tmp/s2
/tmp/s2 results/strong_evaluator_isolation_round_s.csv
/tmp/s2 selftest
```
