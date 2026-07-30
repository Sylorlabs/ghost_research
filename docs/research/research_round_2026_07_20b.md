# Research Round 2026-07-20b (Round AT) — real inventor workshop bootstrap

**Status:** COMPLETE — 3/3 workshop components landed; none is an invention result.

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
| AT1 | Luna | Knownness/research broker | Can the system decide whether a proposed claim is already known, mismatched, unverified, or unknown from frozen provenance without receiving an answer key? | **GATE READY** | Five precommitted classes, hashed frozen citations, five hostile-query denials, and byte-identical replay. Evidence is not treated as truth. | `docs/research/knownness_broker_round_at.md`, `results/knownness_broker_round_at.csv`, `sparse_poly_discovery/knownness_broker_round_at.zig` |
| AT2 | Luna | Scratch-program forge | Can an inventor submit source and a test plan, have a separate restricted worker compile/test it, learn from failure, and receive provenance receipts? | **GATE READY (tiny DSL only)** | Compile failure → repair → test success, wrong-expectation failure, four unsafe-request denials, deterministic replay. No arbitrary-code or OS-isolation claim. | `docs/research/scratch_program_forge_round_at.md`, `results/scratch_program_forge_round_at.csv`, `sparse_poly_discovery/scratch_program_forge_round_at.zig` |
| AT3 | Luna | Frontier explorer | Can a planner retain competing hypotheses and forks, precommit falsifiers, learn from failed branches, and report finite unresolved frontier honestly? | **MECHANICS READY** | Append-only receipts, split/dead-end/retry controls, deterministic replay, and explicit unreached forks 4/5. Synthetic receipt mechanics only. | `docs/research/frontier_explorer_round_at.md`, `results/frontier_explorer_round_at.csv`, `sparse_poly_discovery/frontier_explorer_round_at.zig` |

## Landing protocol

Each worker may edit only its assigned source, CSV, and report. The coordinator
runs fresh builds/self-tests/replays, records results here and in the TOC/index,
then commits only scoped files. These are workshop components, not intelligence
or invention results. A future integrated evaluation must show an isolated
inventor writing and repairing a useful program over sealed real artifacts,
beating equal-budget baselines, and surviving reduction audit.

## Results

Fresh coordinator builds, self-tests, and deterministic replays pass for all
three components. AT1 is an offline frozen-citation classifier with five
knownness states; it rejects answer, score, hidden-verdict, arbitrary-file, and
web-search requests. AT2 demonstrates a deliberately tiny in-memory language:
a bad program fails to compile, a repaired one passes its precommitted test, and
unsafe requests reject. AT3 demonstrates durable frontier mechanics with opaque
receipts, branch splits, justified retries, and two explicitly unreached forks.

**Round verdict:** the workshop floor is now more concrete, but it still is not
an inventor. There is no arbitrary program synthesis/execution, separate hidden
evaluator, real held-out artifact task, or evidence that the three components
cohere into learning or invention. The next experiment must integrate them
under a genuinely isolated evaluator and equal-budget baselines.
