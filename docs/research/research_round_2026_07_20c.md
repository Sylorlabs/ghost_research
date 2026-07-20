# Research Round 2026-07-20c (Round AU) — sealed integration test

**Status:** LIVE — 0/3 complete.

## Premise

AT established three workshop primitives but no integrated inventor. AU builds
the test rig that prevents another AS3/AS4-style self-deception: a genuinely
separate evaluator protocol, a non-LLM candidate that writes and repairs a tiny
analyzer from opaque receipts, and a literal equal-budget measurement harness.

## Required boundaries

- Candidate, worker, evaluator, and sealed task/answer state must be distinct
  programs/files/process roles. Candidate never reads hidden task, answer, score,
  progress, or evaluator code/state.
- Candidate can form competing hypotheses and generate/repair source only in the
  AT2 restricted language. A passed component is not arbitrary-code execution.
- Every baseline gets identical instances, budgets, restart policy, I/O surface,
  and receipt shape. Curves must be derived from ledger rows.
- No LLM, network, credentials, embeddings, answer lookup, or real-artifact
  intelligence claim. Initial fixtures remain opaque and deterministic.

## Verdict table

| # | Role | Experiment | Question | Status | Required evidence | Planned artifacts |
|---|---|---|---|---|---|---|
| AU1 | Luna | Isolated evaluator protocol | Can candidate/worker/evaluator/sealed state communicate through a one-way receipt protocol without answer, score, path, or post-hoc channels? | running | Distinct roles, hostile-denial tests, clean replay, explicit residual containment limit. | `docs/research/isolated_evaluator_protocol_round_au.md`, `results/isolated_evaluator_protocol_round_au.csv`, `sparse_poly_discovery/isolated_evaluator_protocol_round_au.zig` |
| AU2 | Luna | Candidate analyzer loop | Can a non-LLM candidate make competing hypotheses, write/repair a restricted analyzer after failure receipts, and precommit a final claim? | running | Fork/repair receipts and fixed/random/replay/no-repair/post-hoc controls. No discovery claim. | `docs/research/candidate_analyzer_loop_round_au.md`, `results/candidate_analyzer_loop_round_au.csv`, `sparse_poly_discovery/candidate_analyzer_loop_round_au.zig` |
| AU3 | Luna | Equal-budget audit | Can the candidate and all baselines be run under literally identical work budgets, with derived rather than hardcoded scores/curves? | running | Per-policy ledger, equal-budget assertions, leak/curve/post-hoc attacks, replay. | `docs/research/equal_budget_audit_round_au.md`, `results/equal_budget_audit_round_au.csv`, `sparse_poly_discovery/equal_budget_audit_round_au.zig` |

## Landing protocol

Workers edit only their named files. The coordinator fresh-builds and replays
each component, then records all results and commits only scoped files. A full
integrated test may only be called positive after a separate adversarial audit
finds no answer channel, unequal budget, target leak, or post-hoc scoring.
