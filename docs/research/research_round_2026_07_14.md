# Research Round 2026-07-14 (Round N) — break trace-to-tool alignment

**Status:** LIVE — N1–N3 are coordinator-verified; N4 decoupled grammar expansion is running and N5/N6 await it.

**Premise:** Round M established a controlled strict positive for the full
map→split→propose→fresh-test loop, but M6 correctly narrowed it: the supplied
synthetic generator deliberately aligned public trace direction with two fixed
bit predicates. Round N removes that shortcut. It asks whether accumulated
failure memory and public experimental evidence can propose useful tools when
the trace alone is not a near-answer key.

## Frozen wave contract

- N1's evaluator-owned generator must make public trace fields insufficient to
  identify the winning public family: trace-only routing must be at or near
  chance against a frozen family-prior baseline on sealed held-out cells.
- N2 independently quantifies leakage with fixed classifiers, token/order
  permutations, and an explicit information/accuracy upper bound. If the
  trace remains predictive, N4/N5 are blocked—not tuned around it.
- N3's proposer may use only a pre-freeze ledger of past public
  success/failure observations plus policy-safe current diagnostics. It may
  not read formulas, family labels, target IDs as features, test labels, or
  a supplied winning-family mapping.
- All evaluator interactions have persistent session budgets, one raw row per
  charged action, disjoint train/query/test splits, and opaque target tokens.
- A positive needs fresh evaluator-owned test wins over frozen fixed and blind
  controls at equal enforced cost on more than one independent family. A
  single-family gain, trace leakage, tie, incomplete ledger, or reused test
  information is not a positive.
- Every landing includes Zig harness, raw CSV, report, deterministic replay,
  master/TOC/index update, commit, and independent audit before a broad claim.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| N1 | Terra medium | Decoupled sealed benchmark | Can fresh evaluator-owned target cells remove direct trace→winning-family alignment while retaining valid observable diagnostics? | **DONE — BENCHMARK PASS** | Trace-only router 2/4 = family-prior 2/4; all 12 targets valid/nondegenerate; persistent budget/restart/heldout-query/individual-ledger gates pass. | `docs/research/decoupled_benchmark_round_n.md`, `results/decoupled_benchmark_round_n.csv`, `sparse_poly_discovery/decoupled_benchmark_round_n.zig` |
| N2 | Terra medium | Trace-information audit | How much target-family/winning-tool information remains in public trace fields after N1 decoupling? | **DONE — AUDIT PASS** | Exact counterfactual bound and five frozen classifiers are 12/24, family-prior chance, under all field permutations; duplicate/token-ID attacks pass. Artificial audit fixture. | `docs/research/trace_information_audit_round_n.md`, `results/trace_information_audit_round_n.csv`, `sparse_poly_discovery/trace_information_audit_round_n.zig` |
| N3 | Luna medium | Failure-memory proposer | Can a frozen public history of wins/failures rank candidate primitives better than blind choice when trace is non-diagnostic? | **DONE — CONTROLLED LIMITED POSITIVE** | Frozen public outcome-memory ranking is 12/12 held-out versus family prior 6/12 and blind 4/12, with shuffle/ID/duplicate/private-field controls. Separate supplied synthetic outcome fixture. | `docs/research/failure_memory_proposer_round_n.md`, `results/failure_memory_proposer_round_n.csv`, `sparse_poly_discovery/failure_memory_proposer_round_n.zig` |
| N4 | Luna medium | Decoupled grammar expansion | Can memory plus policy-safe experiments form a small nonredundant grammar that transfers across independent decoupled families? | **RUNNING** | Fresh test beats fixed/blind at equal enforced cost on more than one family. | `docs/research/decoupled_grammar_round_n.md`, `results/decoupled_grammar_round_n.csv`, `sparse_poly_discovery/decoupled_grammar_round_n.zig` |
| N5 | Terra medium | Decoupled closed loop | Does map → memory → propose → test beat controls when trace cannot identify the winning family? | blocked on N1/N2/N3/N4 | Strict fresh-test equal-cost win over fixed and blind across independent families; complete persistent ledger. | `docs/research/decoupled_closed_loop_round_n.md`, `results/decoupled_closed_loop_round_n.csv`, `sparse_poly_discovery/decoupled_closed_loop_round_n.zig` |
| N6 | Terra medium | Red-team audit | Do benchmark, leakage audit, memory, grammar, and closed-loop claims survive generation/leakage/memorization/accounting attacks? | blocked on N1/N2/N3/N4/N5 | Independent claim-by-claim replay; no broad autonomy claim without pass. | `docs/research/round_n_audit.md`, `results/round_n_audit.csv`, `sparse_poly_discovery/round_n_audit.zig` |

## Landing protocol

No agent prose is accepted as a result. On each completion, the coordinator
rebuilds with fresh caches, reproduces the ledger, checks report/CSV agreement,
updates this table and the TOC/index, commits scoped artifacts, and launches
only dependencies whose acceptance gates truly passed. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_14.md`
for current status.
