# Research Round 2026-07-20c (Round AU) — sealed integration test

**Status:** COMPLETE — three integration plumbing gates landed; no invention result.

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
| AU1 | Luna | Isolated evaluator protocol | Can candidate/worker/evaluator/sealed state communicate through a one-way receipt protocol without answer, score, path, or post-hoc channels? | **PROTOCOL READY** | Separate role processes, six hostile denials, sealed claim accepted only precommit, post-hoc rewrite denied, deterministic replay. Not a formal OS-containment proof. | `docs/research/isolated_evaluator_protocol_round_au.md`, `results/isolated_evaluator_protocol_round_au.csv`, `sparse_poly_discovery/isolated_evaluator_protocol_round_au.zig` |
| AU2 | Luna | Candidate analyzer loop | Can a non-LLM candidate make competing hypotheses, write/repair a restricted analyzer after failure receipts, and precommit a final claim? | **MECHANICS READY** | Opaque observation, three forks, compile-failure → repair receipt, four controls, post-hoc rejection, byte-identical replay. Fixed control also succeeds. | `docs/research/candidate_analyzer_loop_round_au.md`, `results/candidate_analyzer_loop_round_au.csv`, `sparse_poly_discovery/candidate_analyzer_loop_round_au.zig` |
| AU3 | Luna | Equal-budget audit | Can the candidate and all baselines be run under literally identical work budgets, with derived rather than hardcoded scores/curves? | **MEASUREMENT READY** | Seven policies each get 12 instances, 120 receipts, identical steps/tools/restarts; unequal-budget, target-leak, hardcoded-curve, and post-hoc attacks reject; replay identical. | `docs/research/equal_budget_audit_round_au.md`, `results/equal_budget_audit_round_au.csv`, `sparse_poly_discovery/equal_budget_audit_round_au.zig` |

## Landing protocol

Workers edit only their named files. The coordinator fresh-builds and replays
each component, then records all results and commits only scoped files. A full
integrated test may only be called positive after a separate adversarial audit
finds no answer channel, unequal budget, target leak, or post-hoc scoring.

## Results

Fresh coordinator tests now pass for all three components. AU1 runs candidate,
worker, and evaluator as separate role processes with one-way request/receipt
files; six hostile probes and a post-hoc rewrite deny. AU2 demonstrates an
opaque three-fork candidate loop that repairs a restricted analyzer after a
compile receipt, but a fixed control also succeeds. AU3 enforces equal inputs,
steps, tools, restarts, and receipt counts across seven policies and derives
summaries from its ledger.

**Round verdict:** the integration plumbing is complete. It is still not a
real inventor experiment: fixtures are synthetic, AU1 is protocol rather than
formal OS containment, AU2's fixed control ties, and the components have not
yet run together over sealed real artifacts. The next wave is one vertical
integration test followed by an independent reduction audit.
