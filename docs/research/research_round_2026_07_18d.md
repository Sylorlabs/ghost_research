# Research Round 2026-07-18d (Round AN) — capability-limited clean-room evaluation

**Status:** LIVE — AN1/AN2/AN3 launched in parallel. AN4–AN6 are gated on an enforceable boundary.

## Premise

Round AM produced reproducible bounded fixture contrasts for earned causal topology, experiment allocation, and anonymous portfolios, but AM6 found that policy and callable target/reward helpers share compilation units. The behavioral numbers remain evidence about those fixtures; they are not evidence of enforced evaluator isolation, autonomy, security, or general intelligence.

Round AN repairs the experimental architecture before extending capability. It asks whether a candidate can be prevented—within a declared and independently attacked local threat model—from reading or corrupting hidden world/evaluator state while retaining only a fixed raw-observation/raw-action protocol. No claim may say "impossible" without a formal trusted-computing-base proof; the permitted conclusion is limited to **no demonstrated path within the declared, tested boundary**.

## Frozen clean-room contract

- **World/evaluator owner:** a separate process owns hidden rules, targets, reward conversion, recoding, nonce generation, and evaluator-only results.
- **Candidate:** has only bounded raw observations in and bounded raw actions out. It has no file, network, shell, environment-secret, evaluator, score, target, answer, label, or world-family capability.
- **Protocol:** length-delimited schema, strict action domain, fixed turns/budgets, no progress score, deterministic transcript/provenance capture, fail-closed malformed-message handling.
- **Threat-model limit:** local OS/kernel/compiler/hardware are trusted only to the stated extent. Boundary tests must distinguish protocol isolation from full hostile containment.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| AN1 | Terra medium | Clean-room evaluator protocol | Can a separate evaluator and candidate communicate solely through bounded raw observations/actions while preserving sealed hidden state and deterministic transcripts? | running | Candidate lacks evaluator/world capabilities by construction; normal protocol replay succeeds; hidden reward/target never crosses protocol; malformed messages fail closed. | `docs/research/cleanroom_protocol_round_an.md`, `results/cleanroom_protocol_round_an.csv`, `sparse_poly_discovery/cleanroom_protocol_round_an.zig` |
| AN2 | Terra medium | Capability-escape hostile audit | Can an independent attacker find file, environment, inherited-handle, process, IPC, protocol, timing, corruption, or resource-exhaustion paths from candidate to evaluator state? | running | Explicit attack fixtures reject or contain every tested path; residual TCB and untested OS/kernel/compiler risks are named. No "absolute impossibility" claim. | `docs/research/cleanroom_escape_audit_round_an.md`, `results/cleanroom_escape_audit_round_an.csv`, `sparse_poly_discovery/cleanroom_escape_audit_round_an.zig` |
| AN3 | Luna medium | Open-ended discovery evaluator design | Can a no-answer-key evaluation protocol score falsifiable causal claims by intervention, replication, simplicity, and independent replay rather than human invention matching? | running | Rejects answer matching and training/trace leakage; admits only pre-commit claim→prediction→intervention→replication evidence; clearly design/gate only. | `docs/research/open_discovery_protocol_round_an.md`, `results/open_discovery_protocol_round_an.csv`, `sparse_poly_discovery/open_discovery_protocol_round_an.zig` |
| AN4 | Terra medium | Clean-room topology replay | Does AM2 topology still beat all equal-cost controls through AN1's enforced process/protocol boundary? | blocked on AN1/AN2 | Same AM2 budgets and recoding/law-shift controls replay through the clean room; no candidate-side target/reward access. | `docs/research/cleanroom_topology_replay_round_an.md`, `results/cleanroom_topology_replay_round_an.csv`, `sparse_poly_discovery/cleanroom_topology_replay_round_an.zig` |
| AN5 | Terra medium | Clean-room allocation and portfolio replay | Do AM4 allocation and AM5 portfolio positives survive the clean room at same budgets, including wrong-route and ablation controls? | blocked on AN1/AN2/AN4 | AM4/AM5 contrasts survive independent process boundary and hostile capability audit. | `docs/research/cleanroom_allocation_portfolio_round_an.md`, `results/cleanroom_allocation_portfolio_round_an.csv`, `sparse_poly_discovery/cleanroom_allocation_portfolio_round_an.zig` |
| AN6 | Terra medium | Open discovery pilot | Can the isolated inventor generate and test a self-originated falsifiable causal claim without a hidden human answer key or answer-matching reward? | blocked on AN1/AN2/AN3 | A precommitted claim, predicted intervention, replication, and attacker replay succeed; novelty is recorded as provenance/corpus-relative, never assumed. | `docs/research/open_discovery_pilot_round_an.md`, `results/open_discovery_pilot_round_an.csv`, `sparse_poly_discovery/open_discovery_pilot_round_an.zig` |

## Landing protocol

Workers edit only their named source, CSV, and report. Each artifact must fresh-build, self-test, deterministically replay, state exact command/budgets, distinguish **FOUNDATION POSITIVE**, **GATE READY**, **VALID NEGATIVE**, **INCONCLUSIVE**, or **BLOCKED**, and name residual trust assumptions. The coordinator alone updates this master, TOC, and index, runs independent replay, commits, and pushes landed evidence.

