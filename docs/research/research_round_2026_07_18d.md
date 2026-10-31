# Research Round 2026-07-18d (Round AN) — capability-limited clean-room evaluation

**Status:** PARTIALLY LANDED — AN1/AN2/AN3 are gate-ready at protocol/design tier. AN4–AN6 remain blocked because AN2 did not yet attack the actual same-user child process boundary.

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
| AN1 | Terra medium | Clean-room evaluator protocol | Can a separate evaluator and candidate communicate solely through bounded raw observations/actions while preserving sealed hidden state and deterministic transcripts? | **GATE READY** | Real parent evaluator/fresh child candidate runs 8 opaque turns; forbidden score and forged protocol requests deny; no score crosses until end. Protocol boundary only. | `docs/research/cleanroom_protocol_round_an.md`, `results/cleanroom_protocol_round_an.csv`, `sparse_poly_discovery/cleanroom_protocol_round_an.zig` |
| AN2 | Terra medium | Capability-escape hostile audit | Can an independent attacker find file, environment, inherited-handle, process, IPC, protocol, timing, corruption, or resource-exhaustion paths from candidate to evaluator state? | **GATE READY (parser only)** | 15/15 hostile payloads reject and 1 valid raw action admits, but this audit does not attack AN1's launched child process. It leaves OS/process/host containment untested. | `docs/research/cleanroom_escape_audit_round_an.md`, `results/cleanroom_escape_audit_round_an.csv`, `sparse_poly_discovery/cleanroom_escape_audit_round_an.zig` |
| AN3 | Luna medium | Open-ended discovery evaluator design | Can a no-answer-key evaluation protocol score falsifiable causal claims by intervention, replication, simplicity, and independent replay rather than human invention matching? | **GATE READY** | 1/1 precommitted causal record admits; 9/9 answer/trace/post-hoc/correlation/decoder/feedback fixtures reject. Evaluation infrastructure only. | `docs/research/open_discovery_protocol_round_an.md`, `results/open_discovery_protocol_round_an.csv`, `sparse_poly_discovery/open_discovery_protocol_round_an.zig` |
| AN4 | Terra medium | Clean-room topology replay | Does AM2 topology still beat all equal-cost controls through AN1's enforced process/protocol boundary? | blocked on process-level escape audit | Same AM2 budgets and recoding/law-shift controls replay through the clean room; no candidate-side target/reward access. AN2's parser-only audit is insufficient. | `docs/research/cleanroom_topology_replay_round_an.md`, `results/cleanroom_topology_replay_round_an.csv`, `sparse_poly_discovery/cleanroom_topology_replay_round_an.zig` |
| AN5 | Terra medium | Clean-room allocation and portfolio replay | Do AM4 allocation and AM5 portfolio positives survive the clean room at same budgets, including wrong-route and ablation controls? | blocked on AN1/AN2/AN4 | AM4/AM5 contrasts survive independent process boundary and hostile capability audit. | `docs/research/cleanroom_allocation_portfolio_round_an.md`, `results/cleanroom_allocation_portfolio_round_an.csv`, `sparse_poly_discovery/cleanroom_allocation_portfolio_round_an.zig` |
| AN6 | Terra medium | Open discovery pilot | Can the isolated inventor generate and test a self-originated falsifiable causal claim without a hidden human answer key or answer-matching reward? | blocked on AN1/AN2/AN3 | A precommitted claim, predicted intervention, replication, and attacker replay succeed; novelty is recorded as provenance/corpus-relative, never assumed. | `docs/research/open_discovery_pilot_round_an.md`, `results/open_discovery_pilot_round_an.csv`, `sparse_poly_discovery/open_discovery_pilot_round_an.zig` |

## Landing protocol

Workers edit only their named source, CSV, and report. Each artifact must fresh-build, self-test, deterministically replay, state exact command/budgets, distinguish **FOUNDATION POSITIVE**, **GATE READY**, **VALID NEGATIVE**, **INCONCLUSIVE**, or **BLOCKED**, and name residual trust assumptions. The coordinator alone updates this master, TOC, and index, runs independent replay, commits, and pushes landed evidence.

## Landed evidence and boundary

Fresh coordinator builds and byte-identical replays pass for AN1–AN3. AN1 proves a real evaluator-parent/fresh-candidate-child raw protocol for eight fixed opaque turns; score and malformed requests deny and no score arrives before completion. AN2 proves its parser rejects 15/15 seeded hostile payloads, but explicitly did **not** exercise the AN1 child process's filesystem, environment, inherited descriptors, `/proc`, IPC, timing, resource, or corruption surfaces. AN3 gives the no-answer-key gate: an admitted record must precommit a raw causal prediction and survive held-out replication plus alternatives; it is not autonomous discovery evidence.

**Consequence:** do not replay AM claims yet. The required next foundation input is a process-level hostile audit against the actual AN1 launcher, ideally tightening candidate capabilities (UID/namespace/seccomp/descriptor closure as available) and reporting residual TCB. Only then can AN4–AN5 test whether causal behavior survives the clean room.
