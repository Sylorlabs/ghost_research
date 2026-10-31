# Research Round 2026-07-17 (Round AI) — process-level organism isolation

**Status:** GATED — AI1/AI2/AI3 replayed as valid-negative containment results; AI4–AI6 remain blocked.

**Goal:** Replace AH's in-process convention with an actual operating-system boundary. The raw-medium mutant must execute as a separately launched, unprivileged process. It may receive only an initial raw state and a uniform local-law executable. It must not obtain filesystem, environment, network, process-spawn, IPC, parent/evaluator memory, evaluator handles, templates, scores, callbacks, answer data, retry control, or a post-run feedback channel. The evaluator may receive final raw state only after process exit.

The claimed boundary is valid only if it is demonstrated on this machine with reproducible attack attempts. `bwrap`, `unshare`, `setpriv`, or an API wrapper are mechanisms to test, not evidence by name. A blocked kernel feature, user-namespace policy, inherited descriptor, mount leak, process leak, or timing/writeback channel is a **VALID NEGATIVE** or **BLOCKED** infrastructure result, never an autonomy result.

## Non-negotiable transport contract

```text
evaluator --[one initial raw byte stream]--> mutant process
mutant --[one final raw byte stream after exit]--> collector
collector --[one-way post-run provenance]--> evaluator
```

No reverse channel may exist. The mutant interface contains no task, target, score, semantic decoder, observation/action API, candidate/mutation menu, boundary/template, repair, viability, reproduction scheduler, file path, environment secret, callback, socket, subprocess, or dynamic external import. The immutable exterior is only launcher/sandbox policy, finite execution budget, uniform local transport, provenance, evaluator-private worlds, and authority/safety.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| AI1 | Terra medium | Raw-medium process sandbox | Can a separately launched raw-medium worker be prevented from accessing filesystem, environment, network, process control, parent/evaluator memory, inherited descriptors, and external imports under the actual local kernel policy? | **VALID NEGATIVE** | Real bwrap blocks `/etc/passwd`, `HOME`/`PATH`, external shell/imports, host IPC and host process tree. But actual worker `AF_INET` socket creation and `fork`/wait succeed without syscall policy. | `docs/research/raw_process_sandbox_round_ai.md`, `results/raw_process_sandbox_round_ai.csv`, `sparse_poly_discovery/raw_process_sandbox_round_ai.zig` |
| AI2 | Terra medium | One-way evaluator transport | Can a launcher/collector guarantee initial-state-only input and final-state-after-exit-only output, with no evaluator score/answer/retry/timing/writeback channel? | **VALID NEGATIVE** | Real pipes accept exact 16-byte post-exit output, reject malformed/short/extra streams, return EOF on reverse read, and expose empty env/no FD3. Protocol cannot itself deny filesystem/process/socket/IPC/timing syscalls. | `docs/research/one_way_transport_round_ai.md`, `results/one_way_transport_round_ai.csv`, `sparse_poly_discovery/one_way_transport_round_ai.zig` |
| AI3 | Luna medium | Independent sandbox breakout audit | Can an external hostile worker break or falsify AI1/AI2 through namespaces, mounts, procfs, inherited FDs, environment, symlinks, sockets, signals, process trees, timing, malformed output, or launcher provenance? | **VALID NEGATIVE** | Independent audit confirms host files/env/tree and held FD deny, but worker can create sockets, self-spawn, make local IPC, signal namespace PID1, read clock, and emit arbitrary stdout. | `docs/research/sandbox_breakout_audit_round_ai.md`, `results/sandbox_breakout_audit_round_ai.csv`, `sparse_poly_discovery/sandbox_breakout_audit_round_ai.zig` |
| AI4 | Terra medium | Capability-clean loop birth | Can unprivileged raw matter in the verified AI1–AI3 process boundary form a persistent constraint from many random starts? | blocked on AI1/AI2/AI3 | External-only post-run measurement shows spontaneous persistence, perturb/recovery, and private-law transfer over equal-material controls; no process capability violation. | `docs/research/isolated_loop_birth_round_ai.md`, `results/isolated_loop_birth_round_ai.csv`, `sparse_poly_discovery/isolated_loop_birth_round_ai.zig` |
| AI5 | Terra medium | Capability-clean heredity | Can an isolated persistent lineage vary and retain physical mechanisms across changed media without a host mutation/reproduction service? | blocked on AI4 | Emergent physical inheritance/variation with no forbidden process capability and external hostile audit. | `docs/research/isolated_heredity_round_ai.md`, `results/isolated_heredity_round_ai.csv`, `sparse_poly_discovery/isolated_heredity_round_ai.zig` |
| AI6 | Terra medium | End-to-end containment audit | Does the full behavior claim survive binary/launch policy/process tree/FD/mount/network/IPC/provenance and human-scaffold reconstruction? | blocked on AI4/AI5 | Independent reproduction confirms the mutant is unable—not merely instructed not—to access human semantic and operational scaffolds. | `docs/research/process_containment_audit_round_ai.md`, `results/process_containment_audit_round_ai.csv`, `sparse_poly_discovery/process_containment_audit_round_ai.zig` |

## Landing protocol

Workers edit only their assigned source, CSV, and report. Any sandbox launch must use a disposable `/tmp` workspace, never modify system configuration, and record the kernel/launcher capability actually observed. Every landing must fresh-build, selftest, deterministically replay where applicable, include hostile attacks, and label **POSITIVE**, **VALID NEGATIVE**, or **BLOCKED**. The coordinator independently replays and alone updates this master, the TOC, and the index.

## Coordinator verdict (2026-07-17)

Fresh independent coordinator builds, selftests, actual launches, and byte-identical CSV comparisons pass for AI1–AI3. AI1 establishes a real Bubblewrap namespace boundary for host filesystem, environment, external imports, host IPC and host process-tree visibility. AI2 establishes exact one-way post-exit transport with malformed/reverse-stream rejection and no inherited FD3. AI3 independently confirms those denials and the held-FD denial.

The raw-only capability claim fails because the worker's syscall authority is still too broad: actual socket creation, self-spawn/fork, local IPC, signaling, clock access and arbitrary stdout are possible. The one-way collector rejects malformed output but cannot remove those powers. This is a valid negative—not a failed sandbox run—and AI4–AI6 remain blocked.

The next prerequisite is a minimal process launcher with explicit close-all-except-stdio descriptor handling plus an enforceable syscall allowlist (for example seccomp) that permits only read/write of the contracted streams, exit, and required memory/runtime syscalls. It must be verified under the independent AI3 breakout suite. If the local kernel/container policy prevents seccomp, document that infrastructure block rather than weaken the claim.
