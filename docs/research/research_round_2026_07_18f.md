# Research Round 2026-07-18f (Round AP) — syscall, process, and time containment

**Status:** LIVE — AP4 is gate-ready within the declared local Linux/process threat model; AP5 is a bounded isolated topology positive; vDSO/physical timing stays explicit residual. AP6 now replays AM4/AM5 through the same boundary.

## Premise

AO4 demonstrated that Bubblewrap namespaces, private mounts, no network, scrubbed environment, descriptor closure, and protocol integrity close many real routes. It also demonstrated two live residual capabilities: the candidate can read monotonic time and fork/reap a process. Thus AO is inconclusive for hostile containment and AM replays remain blocked.

Round AP closes only what it can actually measure: a pre-exec candidate syscall policy, process/PID and resource boundary, and direct time-oracle reduction using logical fixed turns. It must never call this absolute security: OS/kernel, Bubblewrap, seccomp implementation, compiler, hardware, and microarchitectural scheduling remain explicit trusted or residual surfaces.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| AP1 | Terra medium | Candidate syscall policy | Can the real candidate launcher enforce a pre-exec policy that denies process creation, exec, new filesystem/namespace/socket/IPC/signal routes, and direct clock reads while preserving minimal raw-action operation? | **GATE READY (bounded)** | Real two-stage seccomp: Bubblewrap pre-exec filter plus trusted bootstrap before opaque parsing. Direct fork/clone/exec/open/socket/mount/signal/time probes return EPERM; raw action works. Deny-list residual remains. | `docs/research/syscall_policy_round_ap.md`, `results/syscall_policy_round_ap.csv`, `sparse_poly_discovery/syscall_policy_round_ap.zig` |
| AP2 | Terra medium | PID and resource boundary | Can the candidate be bounded to one process with measured limits on CPU, memory, file descriptors, output, and wall execution, using cgroup/PID controller where available or an explicitly weaker fallback? | **GATE READY (bounded)** | Runtime hard `RLIMIT_NPROC=1` denies fork; 8 FD, 64 MiB, CPU/wall, and output caps enforce. cgroup `pids.max` is unavailable and not claimed. | `docs/research/pid_resource_boundary_round_ap.md`, `results/pid_resource_boundary_round_ap.csv`, `sparse_poly_discovery/pid_resource_boundary_round_ap.zig` |
| AP3 | Luna medium | Time-oracle reduction | Can direct clock, sleep, and timing-feedback routes be denied/reduced while fixed logical-turn protocol remains deterministic, and can residual physical timing be separated from evaluator leakage? | **INCONCLUSIVE** | Direct syscall and sleep probes deny; logical turns replay. libc vDSO clock reads succeed without syscalls, physical timing remains, and candidate-loaded filter is not hostile replacement protection. | `docs/research/time_oracle_round_ap.md`, `results/time_oracle_round_ap.csv`, `sparse_poly_discovery/time_oracle_round_ap.zig` |
| AP4 | Terra medium | Post-hardening hostile audit | Does the AP launcher survive AO4's full hostile runtime suite, including clock and fork, with evaluator integrity intact? | **GATE READY (bounded)** | Evaluator-file/proc/FD/process/network/protocol/transcript/direct-time/resource attacks deny or contain. vDSO clock succeeds but has no observed evaluator leak/corruption path; residual physical timing named. | `docs/research/post_hardening_audit_round_ap.md`, `results/post_hardening_audit_round_ap.csv`, `sparse_poly_discovery/post_hardening_audit_round_ap.zig` |
| AP5 | Terra medium | Isolated AM2 topology replay | Does AM2 topology survive an attacked, hardened boundary at its original equal budget? | **FOUNDATION POSITIVE (bounded)** | Separate C candidate under Bubblewrap/seccomp/limits scores **24,960 / 96** at original 1,536 contacts per arm, above graph/vector/schedule 9,100, last 8,320, random/shuffled 10,140, replay 7,800, answer/ablation 7,540. | `docs/research/isolated_topology_replay_round_ap.md`, `results/isolated_topology_replay_round_ap.csv`, `sparse_poly_discovery/isolated_topology_replay_round_ap.zig` |
| AP6 | Terra medium | Isolated AM4/AM5 replay | Do causal allocation and portfolio transfer survive an attacked, hardened boundary at their original equal budgets? | running | Exact AM4/AM5 controls, wrong-route and ablations survive under capability-limited execution. | `docs/research/isolated_allocation_portfolio_round_ap.md`, `results/isolated_allocation_portfolio_round_ap.csv`, `sparse_poly_discovery/isolated_allocation_portfolio_round_ap.zig` |

## Landing protocol

Workers edit only their named source, CSV, and report. Every landing fresh-builds, selftests, deterministically replays, records exact enforced primitives and attack outcomes, labels unavailable controls honestly, and distinguishes **GATE READY**, **FOUNDATION POSITIVE**, **VALID NEGATIVE**, **INCONCLUSIVE**, or **BLOCKED**. The coordinator independently verifies, documents, commits, and pushes.

## Landed evidence and boundary

Fresh coordinator builds and byte-identical replays pass for AP1–AP3. AP1 demonstrates launcher-owned two-stage seccomp enforcement for the specified direct syscall probes, including fork and direct time. AP2 demonstrates a real hard-rlimit fallback that denies one safe fork probe and enforces measured FD, memory, CPU/wall, and output bounds; host cgroup PID delegation is unavailable. AP3 catches the remaining crucial distinction: direct clock syscalls deny, but libc clock reads can use vDSO in user space, and physical timing survives any simple syscall filter. Therefore AP3 is **inconclusive**, not a failure.

**Consequence:** AP4 must run AO4's full hostile suite through the combined AP1+AP2 launcher, including direct and vDSO time plus process creation. It must report whether the vDSO clock is merely an untrusted timing surface with no evaluator channel or an actual leakage/corruption path. No AM replay is authorized by direct-syscall receipts alone.

## AP4 verdict

Fresh coordinator build and byte-identical replay pass. The combined profile denies or contains executed evaluator-file, `/proc`/FD, host-process, network/IPC, fork/clone/exec/open/socket/mount/signal, malformed/forged protocol, transcript/budget/score corruption, direct time/sleep, and bounded resource attacks. libc vDSO time reads still succeed in user space; in this runtime test they have no observed evaluator-data, interim-score, network/IPC, or corruption channel. This is therefore a **bounded gate-ready process boundary**, not a claim that timing side channels disappear. AP5 may now replay AM2 unchanged at its original budget.

## AP5 verdict

Fresh coordinator build passes an explicit two-frame clean-room smoke test and two independent full ledgers that byte-compare. The full AM2 original budget remains 96 cohorts × 16 contacts = 1,536 per arm. A separately compiled C candidate, mounted alone beneath the AP4-equivalent evaluator boundary, earns topology material 24,960/96 and strictly exceeds every listed equal-cost control. The original `RLIMIT_NPROC=1` setting cannot be applied before Bubblewrap namespace setup; AP5 documents this and relies on tested PID namespace plus candidate seccomp fork/clone denial instead. This is bounded process-isolated foundation evidence, not an absolute containment or open-ended autonomy result.
