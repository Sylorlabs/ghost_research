# Research Round 2026-07-18e (Round AO) — capability-hardened evaluator boundary

**Status:** LIVE — AO1/AO2/AO3 launched in parallel. AO4–AO6 are gated on an attacked, enforceable boundary.

## Premise

Round AN established a real parent-evaluator/fresh-child raw protocol and a parser-level deny gate, but did not test the actual child process against filesystem, environment, descriptor, process, IPC, timing, corruption, or resource attacks. Therefore AM's behavior remains unreplayed behind a credible boundary.

Round AO makes the boundary concrete. It does not promise absolute impossibility: the conclusion is restricted to **no demonstrated escape or corruption route within the declared, tested local Linux threat model and trusted computing base**. Kernel, hardware, compiler, privileged host, and untested side-channel assumptions must remain explicit.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| AO1 | Terra medium | Capability-hardened candidate launcher | Can the evaluator launch a candidate with only protocol pipes, scrubbed environment, closed descriptors, restricted filesystem/workdir, no network, bounded output/CPU/memory, and no writable evaluator state? | running | Executable launcher demonstrates its restrictions and fail-closed behavior; actual available primitives and residual TCB are measured, not assumed. | `docs/research/capability_launcher_round_ao.md`, `results/capability_launcher_round_ao.csv`, `sparse_poly_discovery/capability_launcher_round_ao.zig` |
| AO2 | Terra medium | Live escape-surface reconnaissance | What capability routes exist against AN1's current same-user child and what concrete attack fixtures must AO1 defeat? | running | Reproducible reconnaissance records tested file/env/FD/process/IPC/clock/resource/transcript routes without claiming a clean boundary; produces adversarial fixtures for the later integrated audit. | `docs/research/live_escape_recon_round_ao.md`, `results/live_escape_recon_round_ao.csv`, `sparse_poly_discovery/live_escape_recon_round_ao.zig` |
| AO3 | Luna medium | Evaluator integrity boundary | Can evaluator state, nonce/transcript lineage, budget accounting, and end-only score be made tamper-evident and reject candidate-originated corruption? | running | Independent integrity fixtures reject forged/reordered/replayed/tampered transcript and budget/score mutations; residual trust is explicit. | `docs/research/evaluator_integrity_round_ao.md`, `results/evaluator_integrity_round_ao.csv`, `sparse_poly_discovery/evaluator_integrity_round_ao.zig` |
| AO4 | Terra medium | Integrated live escape audit | Does the AO1 launcher plus AO3 evaluator survive AO2's actual hostile child-process fixtures at runtime? | blocked on AO1/AO2/AO3 | Every tested route denies or is contained, transcript remains valid, and all residual routes/TCB are documented. | `docs/research/integrated_escape_audit_round_ao.md`, `results/integrated_escape_audit_round_ao.csv`, `sparse_poly_discovery/integrated_escape_audit_round_ao.zig` |
| AO5 | Terra medium | Clean-room AM2 replay | Does AM2 topology survive the hardened, attacked evaluator boundary at equal original budget? | blocked on AO4 | Exact AM2 controls/budget replay through raw protocol with no evaluator capability path. | `docs/research/hardened_topology_replay_round_ao.md`, `results/hardened_topology_replay_round_ao.csv`, `sparse_poly_discovery/hardened_topology_replay_round_ao.zig` |
| AO6 | Terra medium | Clean-room AM4/AM5 replay | Do AM4 allocation and AM5 portfolio survive the hardened boundary at original equal budgets? | blocked on AO4/AO5 | All baseline, wrong-route, and ablation contrasts survive under capability-limited process execution. | `docs/research/hardened_allocation_portfolio_round_ao.md`, `results/hardened_allocation_portfolio_round_ao.csv`, `sparse_poly_discovery/hardened_allocation_portfolio_round_ao.zig` |

## Landing protocol

Workers edit only their named source, CSV, and report. Artifacts must fresh-build, self-test, deterministically replay, record exact privileges and tested attack routes, and distinguish **GATE READY**, **FOUNDATION POSITIVE**, **VALID NEGATIVE**, **INCONCLUSIVE**, or **BLOCKED**. The coordinator independently verifies, updates indexes, commits, and pushes.

