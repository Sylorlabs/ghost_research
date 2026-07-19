# Research Round 2026-07-18e (Round AO) — capability-hardened evaluator boundary

**Status:** PARTIALLY LANDED — AO1/AO3 restrictions hold for many real attacks, but AO4 is inconclusive: candidate clock reads and process creation remain exposed. AO5–AO6 stay blocked on syscall/cgroup hardening.

## Premise

Round AN established a real parent-evaluator/fresh-child raw protocol and a parser-level deny gate, but did not test the actual child process against filesystem, environment, descriptor, process, IPC, timing, corruption, or resource attacks. Therefore AM's behavior remains unreplayed behind a credible boundary.

Round AO makes the boundary concrete. It does not promise absolute impossibility: the conclusion is restricted to **no demonstrated escape or corruption route within the declared, tested local Linux threat model and trusted computing base**. Kernel, hardware, compiler, privileged host, and untested side-channel assumptions must remain explicit.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| AO1 | Terra medium | Capability-hardened candidate launcher | Can the evaluator launch a candidate with only protocol pipes, scrubbed environment, closed descriptors, restricted filesystem/workdir, no network, bounded output/CPU/memory, and no writable evaluator state? | **GATE READY** | Runtime Bubblewrap probes verify mount/PID/IPC/UTS/network namespaces, empty env, private tmpfs cwd, no evaluator path, capability drop, no extra descriptors, 64 MiB/1 CPU sec limits, bounded protocol. Seccomp/UID/MAC remain absent. | `docs/research/capability_launcher_round_ao.md`, `results/capability_launcher_round_ao.csv`, `sparse_poly_discovery/capability_launcher_round_ao.zig` |
| AO2 | Terra medium | Live escape-surface reconnaissance | What capability routes exist against AN1's current same-user child and what concrete attack fixtures must AO1 defeat? | **INCONCLUSIVE** | AN1-style child exposes env, cwd, `/proc`, adjacent files, stdout, and clock. This honestly invalidates the old boundary and supplies safe fixtures; signals/fork/IPC-network/tamper remain marked untested. | `docs/research/live_escape_recon_round_ao.md`, `results/live_escape_recon_round_ao.csv`, `sparse_poly_discovery/live_escape_recon_round_ao.zig` |
| AO3 | Luna medium | Evaluator integrity boundary | Can evaluator state, nonce/transcript lineage, budget accounting, and end-only score be made tamper-evident and reject candidate-originated corruption? | **GATE READY** | Fixed evaluator nonce/budget/transcript rejects forged/reordered/replayed actions, budget overrun, early score/state writes, and detects tag/value alteration. Protocol integrity only, not cryptographic/OS proof. | `docs/research/evaluator_integrity_round_ao.md`, `results/evaluator_integrity_round_ao.csv`, `sparse_poly_discovery/evaluator_integrity_round_ao.zig` |
| AO4 | Terra medium | Integrated live escape audit | Does the AO1 launcher plus AO3 evaluator survive AO2's actual hostile child-process fixtures at runtime? | **INCONCLUSIVE** | Evaluator file/env/FD/host-process/network/protocol/transcript attacks hold, but child can read monotonic clock and fork/reap. No seccomp time/process policy or cgroup PID control; boundary not ready. | `docs/research/integrated_escape_audit_round_ao.md`, `results/integrated_escape_audit_round_ao.csv`, `sparse_poly_discovery/integrated_escape_audit_round_ao.zig` |
| AO5 | Terra medium | Clean-room AM2 replay | Does AM2 topology survive the hardened, attacked evaluator boundary at equal original budget? | blocked on syscall/cgroup hardening | Exact AM2 controls/budget replay through raw protocol with no candidate-side target/reward access. | `docs/research/hardened_topology_replay_round_ao.md`, `results/hardened_topology_replay_round_ao.csv`, `sparse_poly_discovery/hardened_topology_replay_round_ao.zig` |
| AO6 | Terra medium | Clean-room AM4/AM5 replay | Do AM4 allocation and AM5 portfolio survive the hardened boundary at original equal budgets? | blocked on AO4/AO5 | All baseline, wrong-route, and ablation contrasts survive under capability-limited process execution. | `docs/research/hardened_allocation_portfolio_round_ao.md`, `results/hardened_allocation_portfolio_round_ao.csv`, `sparse_poly_discovery/hardened_allocation_portfolio_round_ao.zig` |

## Landing protocol

Workers edit only their named source, CSV, and report. Artifacts must fresh-build, self-test, deterministically replay, record exact privileges and tested attack routes, and distinguish **GATE READY**, **FOUNDATION POSITIVE**, **VALID NEGATIVE**, **INCONCLUSIVE**, or **BLOCKED**. The coordinator independently verifies, updates indexes, commits, and pushes.

## Landed evidence

Fresh coordinator builds and byte-identical replays pass for AO1–AO3. AO1 closes the specific AN1 exposures at launch using actual Bubblewrap namespaces, a cleared environment, private tmpfs workdir, unmounted evaluator private path, descriptor audit, capability drop, network namespace, and `prlimit` resource bounds. AO2 correctly finds the unmodified AN1-like child porous and is **inconclusive**, not a negative behavioral result; its findings are the attack checklist AO4 must run against AO1. AO3 makes declared evaluator transcript/budget/nonce corruption detectable at protocol level, but its local chained tag is not cryptographic or hostile-OS protection.

**Consequence:** AO4 is the decisive boundary test. It must launch actual hostile child fixtures through AO1, exercise the AO2 surfaces, and verify AO3 transcript integrity. No AM replay may begin from receipts alone.

## AO4 verdict

Fresh coordinator build and byte-identical replay pass. AO4 demonstrates that the actual AO1 Bubblewrap child denies the executed evaluator-file, environment, descriptor, host-process, network, malformed-protocol, and evaluator-transcript attacks. However, it also demonstrates two live remaining capabilities: monotonic clock read and safe fork/reap of one child. This is **inconclusive for hostile containment**, not a negative behavioral result or a crash. The required repair is an enforceable candidate-compatible syscall and PID/cgroup policy, followed by the same integrated audit. AM replays remain blocked until that test passes.
