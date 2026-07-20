# Research Round 2026-07-20b (Round AT) — real inventor workshop bootstrap

**Status:** LIVE — 0/3 complete.

## Premise

Round AS closed by retracting its apparent discovery positives: AS3 had unequal
budgets/generated targets and AS4 leaked its answer into the child frame. This
round does not claim an inventor exists. It builds the minimum honest workshop
an inventor would need: a knownness gate that avoids reinventing established
claims, a sandboxed scratch-program forge, and an append-only frontier map for
multiple competing hypotheses and failed attempts.

## Non-negotiable boundary

- No LLM, embeddings, answer retrieval, evaluator labels, or hidden-task text
  reaches the planner/inventor.
- Any research/knownness result is provenance-bound evidence, not truth or an
  answer; it must be locally reproduced before reuse.
- Candidate-authored source runs only in disposable scratch through a restricted
  worker; no network, credentials, source-artifact writes, evaluator access, or
  arbitrary host commands.
- The evaluator and hidden tests stay separate. Every success needs equal-budget
  controls, clean replay, and an adversarial reduction audit.
- "Exhausted" means only the current reachable frontier under declared budget
  and tools—not that reality has no remaining possibilities.

## Verdict table

| # | Role | Experiment | Question | Status | Required evidence | Planned artifacts |
|---|---|---|---|---|---|---|
| AT1 | Luna | Knownness/research broker | Can the system decide whether a proposed claim is already known, mismatched, unverified, or unknown from frozen provenance without receiving an answer key? | running | Hashed citation fixtures, leakage denials, replay, and classification distinct from truth/evaluation. | `docs/research/knownness_broker_round_at.md`, `results/knownness_broker_round_at.csv`, `sparse_poly_discovery/knownness_broker_round_at.zig` |
| AT2 | Luna | Scratch-program forge | Can an inventor submit source and a test plan, have a separate restricted worker compile/test it, learn from failure, and receive provenance receipts? | running | Compile/fail/repair receipts, sandbox denials, resource hashes, deterministic replay; no arbitrary-code claim. | `docs/research/scratch_program_forge_round_at.md`, `results/scratch_program_forge_round_at.csv`, `sparse_poly_discovery/scratch_program_forge_round_at.zig` |
| AT3 | Luna | Frontier explorer | Can a planner retain competing hypotheses and forks, precommit falsifiers, learn from failed branches, and report finite unresolved frontier honestly? | running | Append-only receipt chain, anti-post-hoc controls, fork/split/dead-end mechanics, replay, unreached-branch report. | `docs/research/frontier_explorer_round_at.md`, `results/frontier_explorer_round_at.csv`, `sparse_poly_discovery/frontier_explorer_round_at.zig` |

## Landing protocol

Each worker may edit only its assigned source, CSV, and report. The coordinator
runs fresh builds/self-tests/replays, records results here and in the TOC/index,
then commits only scoped files. These are workshop components, not intelligence
or invention results. A future integrated evaluation must show an isolated
inventor writing and repairing a useful program over sealed real artifacts,
beating equal-budget baselines, and surviving reduction audit.
