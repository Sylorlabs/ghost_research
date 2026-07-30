# Research Round 2026-07-20 (Round AS) — real-artifact workbench

**Status:** COMPLETE — AS1/AS2 remain narrow protocol gates; AS3/AS4 are retracted by AS6; AS5 is a valid negative. No Round AS discovery positive survives.

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
| AS3 | Terra medium | Checkpointed workbench scheduler | Can a multi-episode candidate run for meaningful wall time over local artifact tasks, preserve only experience/provenance, resume from hashed checkpoints, and be compared to broad/random/replay workflows? | **RETRACTED / INVALID** | Corpus/target/scoring are generated in one executable; only learned policy gets long wall time; checkpoint curve is literal output. Retained as a scheduler/replay scaffold only. | `docs/research/workbench_scheduler_round_as.md`, `results/workbench_scheduler_round_as.csv`, `sparse_poly_discovery/workbench_scheduler_round_as.zig` |
| AS4 | Terra medium | Real-artifact discovery pilot | Can the isolated candidate form a precommitted structural hypothesis about a held-out local artifact, choose a permitted local test, and replicate on a distinct artifact? | **RETRACTED / INVALID** | Parent calculates target then writes an identifying sentinel into the child input; changed encoding repeats the same answer leak. Bubblewrap cannot repair an stdin answer channel. | `docs/research/real_artifact_discovery_round_as.md`, `results/real_artifact_discovery_round_as.csv`, `sparse_poly_discovery/real_artifact_discovery_round_as.zig` |
| AS5 | Terra medium | Public-web observation transfer | Does a candidate form a bounded, reproducible prediction from approved web captures and transfer it to a fresh capture/second approved endpoint without free browsing? | **VALID NEGATIVE** | The earned opaque-frame prediction is correct, but fixed/broad/replay/shuffled/answer-scrubbed structural controls are also correct. It shows a generic shortcut, not learned web transfer. | `docs/research/web_observation_transfer_round_as.md`, `results/web_observation_transfer_round_as.csv`, `sparse_poly_discovery/web_observation_transfer_round_as.zig` |
| AS6 | Luna medium | Real-workbench reduction audit | Can an independent critic reduce any apparent local/web discovery to cached answer, source leak, fixed parser rule, broad search, post-hoc claim, or capture artifact? | **COMPLETE — REDUCTION CONFIRMED** | AS3 and AS4 do not survive; AS1/AS2 survive only as protocol gates; AS5 remains an honest valid negative. | `docs/research/real_workbench_reduction_audit_round_as.md`, `results/real_workbench_reduction_audit_round_as.csv`, `sparse_poly_discovery/real_workbench_reduction_audit_round_as.zig` |

## Approved test targets

The initial local target is a deterministic allowlisted snapshot selected by the evaluator from this workspace's public source fixtures; it is content-hashed before exposure. The initial web target is a documented, public, unauthenticated GET-only endpoint with no user account or state change. The test is a capture/provenance protocol—not a claim the candidate understands the web's natural language.

## Landing protocol

Workers edit only their named source, CSV, and report. Any live network action must be limited to the fixed public GET target and recorded in its report/CSV. Fresh build, selftest, deterministic replay where applicable, exact actual wall time, and scope limits are mandatory. A successful adapter is infrastructure only; no real-world intelligence claim precedes held-out discovery and reduction audit.

## Landed evidence

Fresh coordinator builds and replays pass for AS1–AS3. AS1 is a narrow local snapshot adapter gate. AS2 executed two live, unauthenticated public GET captures after its primary demo endpoint returned 503; its cached capture replays without network and rejects unsafe request shapes. This is web observation plumbing, not web understanding. AS3 is the first bounded real-artifact-style scheduler positive: it spends 12.5 seconds doing local snapshot parsing, structural tests, checkpoint hashing/resume, and held-out evaluation, and learned provenance beats fixed broad/random/replay at equal test count. The artifacts remain evaluator-owned deterministic snapshots, not arbitrary host repositories or the open web.

AS4 now tests a stronger claim: a separate candidate must precommit a structural hypothesis about a held-out allowlisted local artifact, run only a permitted local test, replicate on a different artifact, and survive simpler/attacker alternatives. A passing result remains a narrow real-artifact process claim—not autonomous software engineering or novelty.

## AS4 result

Fresh coordinator build and byte-identical replay pass. A separate bounded child makes four opaque precommitted structural predictions and four changed-encoding replications over allowlisted local snapshots, exceeding all listed equal-frame controls. The child sees no paths or artifact text; the evaluator owns snapshot reads and results. This is a narrow structural-process positive only: it does not show semantic reading, bug finding, autonomous engineering, novelty, or transfer beyond the selected artifact family. AS5 now tests an equally bounded public web-capture transfer process.

## AS5 result

Fresh coordinator self-test and two cached replays pass byte-identically; the live ledger records exactly two unauthenticated public HTTPS GET captures. The candidate's sealed structural prediction (nonempty and mostly printable) is true of the second capture, but fixed, broad, replay, shuffled, and answer-scrubbed structural controls make the identical prediction and are true too. **AS5 is therefore a valid negative:** the protocol is reproducible and safely bounded, but it does not establish learned transfer, web understanding, browsing, or discovery. AS6 is the remaining independent reduction audit of all Round AS claims.

## AS6 correction and final verdict

Fresh local build, self-test, and byte-identical replay of the independent audit pass. **AS3 and AS4 are retracted.** AS3's supposed local-artifact corpus and target are generated inside the evaluator executable; its controls are not given equal wall time; and its advertised curve is literal output. AS4's parent computes the answer index, marks that index in the frame, and gives the mark to the child; its recoding reruns the same leak. AS1 and AS2 remain useful, narrow allowlist/provenance/replay plumbing; AS5 remains an honest valid negative. Round AS therefore closes with **no surviving real-artifact or web-discovery positive**. Its durable result is the audit rule: isolate evaluator/candidate, remove answer channels, run controls at genuinely equal budgets, and derive all reported curves from recorded computation before calling any result learned discovery.
