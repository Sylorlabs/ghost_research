# Research Round 2026-07-18f (Round AP) — syscall, process, and time containment

**Status:** LIVE — AP1/AP2/AP3 launched in parallel. AP4–AP6 are gated on measured enforcement.

## Premise

AO4 demonstrated that Bubblewrap namespaces, private mounts, no network, scrubbed environment, descriptor closure, and protocol integrity close many real routes. It also demonstrated two live residual capabilities: the candidate can read monotonic time and fork/reap a process. Thus AO is inconclusive for hostile containment and AM replays remain blocked.

Round AP closes only what it can actually measure: a pre-exec candidate syscall policy, process/PID and resource boundary, and direct time-oracle reduction using logical fixed turns. It must never call this absolute security: OS/kernel, Bubblewrap, seccomp implementation, compiler, hardware, and microarchitectural scheduling remain explicit trusted or residual surfaces.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| AP1 | Terra medium | Candidate syscall policy | Can the real candidate launcher enforce a pre-exec policy that denies process creation, exec, new filesystem/namespace/socket/IPC/signal routes, and direct clock reads while preserving minimal raw-action operation? | running | Runtime probes show listed calls deny under the policy, baseline raw protocol runs, and policy activation precedes untrusted candidate logic. Residual syscalls/TCB named. | `docs/research/syscall_policy_round_ap.md`, `results/syscall_policy_round_ap.csv`, `sparse_poly_discovery/syscall_policy_round_ap.zig` |
| AP2 | Terra medium | PID and resource boundary | Can the candidate be bounded to one process with measured limits on CPU, memory, file descriptors, output, and wall execution, using cgroup/PID controller where available or an explicitly weaker fallback? | running | Actual enforced limits are runtime-observed; fork/PID attempts deny/contain; unavailable primitives are not represented as protections. | `docs/research/pid_resource_boundary_round_ap.md`, `results/pid_resource_boundary_round_ap.csv`, `sparse_poly_discovery/pid_resource_boundary_round_ap.zig` |
| AP3 | Luna medium | Time-oracle reduction | Can direct clock, sleep, and timing-feedback routes be denied/reduced while fixed logical-turn protocol remains deterministic, and can residual physical timing be separated from evaluator leakage? | running | Direct time probes deny or contain; evaluator supplies no elapsed/progress field; logical protocol replay holds; residual scheduler/hardware timing risk explicit. | `docs/research/time_oracle_round_ap.md`, `results/time_oracle_round_ap.csv`, `sparse_poly_discovery/time_oracle_round_ap.zig` |
| AP4 | Terra medium | Post-hardening hostile audit | Does the AP launcher survive AO4's full hostile runtime suite, including clock and fork, with evaluator integrity intact? | blocked on AP1/AP2/AP3 | All executed attack routes deny/contain; transcript holds; residual TCB is measured and named. | `docs/research/post_hardening_audit_round_ap.md`, `results/post_hardening_audit_round_ap.csv`, `sparse_poly_discovery/post_hardening_audit_round_ap.zig` |
| AP5 | Terra medium | Isolated AM2 topology replay | Does AM2 topology survive an attacked, hardened boundary at its original equal budget? | blocked on AP4 | Exact original controls/budget through evaluator-owned raw protocol; no target/reward capability in candidate. | `docs/research/isolated_topology_replay_round_ap.md`, `results/isolated_topology_replay_round_ap.csv`, `sparse_poly_discovery/isolated_topology_replay_round_ap.zig` |
| AP6 | Terra medium | Isolated AM4/AM5 replay | Do causal allocation and portfolio transfer survive an attacked, hardened boundary at their original equal budgets? | blocked on AP4/AP5 | Exact AM4/AM5 controls, wrong-route and ablations survive under capability-limited execution. | `docs/research/isolated_allocation_portfolio_round_ap.md`, `results/isolated_allocation_portfolio_round_ap.csv`, `sparse_poly_discovery/isolated_allocation_portfolio_round_ap.zig` |

## Landing protocol

Workers edit only their named source, CSV, and report. Every landing fresh-builds, selftests, deterministically replays, records exact enforced primitives and attack outcomes, labels unavailable controls honestly, and distinguishes **GATE READY**, **FOUNDATION POSITIVE**, **VALID NEGATIVE**, **INCONCLUSIVE**, or **BLOCKED**. The coordinator independently verifies, documents, commits, and pushes.

