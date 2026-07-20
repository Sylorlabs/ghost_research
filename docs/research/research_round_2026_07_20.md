# Research Round 2026-07-20 (Round AS) — real-artifact workbench

**Status:** LIVE — AS1/AS2 are gate-ready adapters; AS3 is a bounded multi-episode local-artifact positive. AS4 held-out local-artifact discovery pilot launched; AS5–AS6 remain gated.

## Premise

AR establishes that larger synthetic worlds are possible, but also shows that the current allocator loses to broad generic search at scale. We therefore build a controlled bridge to real artifacts instead of pretending a generated world is the outside world.

Round AS creates a workbench where a non-LLM candidate can inspect real local source/data and a small approved public web surface through evaluator-owned, read-only adapters. It must form provenance-bound predictions and interventions; no credentials, login, posting, mutation, answer lookup, hidden test outcome, or evaluation progress crosses to the candidate.

## Non-negotiable operation boundary

- No LLM, text/token prediction, embeddings, answer retrieval, training-answer trace, or human answer labels.
- **Local adapter:** snapshots an allowlisted read-only artifact set using content hashes; candidate sees bounded raw observations only, never arbitrary host files, secrets, `.git`, or evaluator state.
- **Web adapter:** allowlisted public GET-only endpoint(s), no authentication/cookies/forms/uploads/POST, rate-limited and cached with content hash plus capture timestamp. Candidate sees bounded raw response observations, not unrestricted networking.
- **Tool worker:** disposable scratch only, restricted commands/actions, finite budget. It cannot write to source artifacts or web.
- **Evaluator:** owns held-out tasks, score, and end-only comparison. Every candidate claim must precommit a prediction before the tool worker runs.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| AS1 | Terra medium | Read-only local artifact adapter | Can a candidate inspect a hashed allowlisted local code/data snapshot through raw observations and make testable predictions without arbitrary file access or source mutation? | **GATE READY** | Hashed snapshot, bounded structural query, prediction-before-test receipt; **10** mutation/traversal/out-of-scope/`.git`/secret/answer/score/progress/provenance/overlap denials. Infrastructure only. | `docs/research/local_artifact_adapter_round_as.md`, `results/local_artifact_adapter_round_as.csv`, `sparse_poly_discovery/local_artifact_adapter_round_as.zig` |
| AS2 | Terra medium | Approved public-web adapter | Can a candidate inspect a fixed public GET-only web endpoint through capture/hash/cache/rate limits and make a prediction about a fresh allowed response without unrestricted web action? | **GATE READY** | Two public unauthenticated GET captures to `api.github.com/zen` after documented fallback; status 200, provenance/hash/cache; **8** unsafe request shapes reject; cached replay byte-identical. Structural capture only. | `docs/research/approved_web_adapter_round_as.md`, `results/approved_web_adapter_round_as.csv`, `sparse_poly_discovery/approved_web_adapter_round_as.zig` |
| AS3 | Terra medium | Checkpointed workbench scheduler | Can a multi-episode candidate run for meaningful wall time over local artifact tasks, preserve only experience/provenance, resume from hashed checkpoints, and be compared to broad/random/replay workflows? | **FOUNDATION POSITIVE (bounded)** | **12.5 sec** actual parsing/test/checkpoint work, 96 evaluator-owned artifacts/192 episodes; learned provenance **9,648** beats fixed/replay 9,216, random 9,165, blank/scrub 8,736 at equal 18,432 tests. Snapshot corpus, not arbitrary host repos. | `docs/research/workbench_scheduler_round_as.md`, `results/workbench_scheduler_round_as.csv`, `sparse_poly_discovery/workbench_scheduler_round_as.zig` |
| AS4 | Terra medium | Real-artifact discovery pilot | Can the isolated candidate form a precommitted structural hypothesis about a held-out local artifact, choose a permitted local test, and replicate on a distinct artifact? | running | Parent evaluator/tool worker/candidate separation, precommitment, test, replication, simpler/attacker alternatives; no source answer label. | `docs/research/real_artifact_discovery_round_as.md`, `results/real_artifact_discovery_round_as.csv`, `sparse_poly_discovery/real_artifact_discovery_round_as.zig` |
| AS5 | Terra medium | Public-web observation transfer | Does a candidate form a bounded, reproducible prediction from approved web captures and transfer it to a fresh capture/second approved endpoint without free browsing? | blocked on AS2/AS3/AS4 | GET-only provenance, rate/cost accounting, fresh-capture replication, local alternative, and no authentication/mutation paths. | `docs/research/web_observation_transfer_round_as.md`, `results/web_observation_transfer_round_as.csv`, `sparse_poly_discovery/web_observation_transfer_round_as.zig` |
| AS6 | Luna medium | Real-workbench reduction audit | Can an independent critic reduce any apparent local/web discovery to cached answer, source leak, fixed parser rule, broad search, post-hoc claim, or capture artifact? | blocked on AS1/AS2/AS3/AS4/AS5 | Only claims surviving source/web provenance, replay, cost, alternate explanation, and scope attacks remain. | `docs/research/real_workbench_reduction_audit_round_as.md`, `results/real_workbench_reduction_audit_round_as.csv`, `sparse_poly_discovery/real_workbench_reduction_audit_round_as.zig` |

## Approved test targets

The initial local target is a deterministic allowlisted snapshot selected by the evaluator from this workspace's public source fixtures; it is content-hashed before exposure. The initial web target is a documented, public, unauthenticated GET-only endpoint with no user account or state change. The test is a capture/provenance protocol—not a claim the candidate understands the web's natural language.

## Landing protocol

Workers edit only their named source, CSV, and report. Any live network action must be limited to the fixed public GET target and recorded in its report/CSV. Fresh build, selftest, deterministic replay where applicable, exact actual wall time, and scope limits are mandatory. A successful adapter is infrastructure only; no real-world intelligence claim precedes held-out discovery and reduction audit.

## Landed evidence

Fresh coordinator builds and replays pass for AS1–AS3. AS1 is a narrow local snapshot adapter gate. AS2 executed two live, unauthenticated public GET captures after its primary demo endpoint returned 503; its cached capture replays without network and rejects unsafe request shapes. This is web observation plumbing, not web understanding. AS3 is the first bounded real-artifact-style scheduler positive: it spends 12.5 seconds doing local snapshot parsing, structural tests, checkpoint hashing/resume, and held-out evaluation, and learned provenance beats fixed broad/random/replay at equal test count. The artifacts remain evaluator-owned deterministic snapshots, not arbitrary host repositories or the open web.

AS4 now tests a stronger claim: a separate candidate must precommit a structural hypothesis about a held-out allowlisted local artifact, run only a permitted local test, replicate on a different artifact, and survive simpler/attacker alternatives. A passing result remains a narrow real-artifact process claim—not autonomous software engineering or novelty.
