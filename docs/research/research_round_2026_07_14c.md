# Research Round 2026-07-14c (Round P) — experience, not answers: the forge loop

**Status:** LIVE — P1–P3 are coordinator-verified; P4 measurement forge is running and P5/P6 await it.

**Premise:** Round O proves that a supplied active probe, supplied history, and
supplied grammar can beat equal-cost controls on a decoupled synthetic suite.
The next constraint is epistemic: an inventor must retain *causal experience*,
not a lookup table of hidden targets or fresh-test answers. Round P builds a
score-private campaign vault, an answer-free causal notebook, then tests
whether that notebook can forge a diagnostic and a reusable operation from
generic raw primitives.

## Frozen wave contract

- The policy receives no hidden target identity/family/formula/parameter,
  manifest row, per-target fresh-test label, per-target fresh-test score, or
  per-target winning-tool label. The evaluator releases only allowed
  calibration/probe replies during a campaign and aggregate campaign summaries
  after closure.
- Experience memory may contain only canonicalized attempt shape, generic
  primitive composition, permitted observation summary, residual signature,
  charged cost, stated causal hypothesis, and calibration-level effect. It
  must exclude tokens/IDs, formula/family fields, fresh score/label, test
  outcome, target→tool pair, and answer-bearing free text.
- P3 attacks the memory store directly: frozen classifiers must not recover
  target identity, hidden family, per-target fresh result, or winning tool
  above chance. Any leaking field is quarantined/deleted and blocks P4/P5.
- P4 starts with generic computational atoms and may synthesize a diagnostic
  program; it is not offered named diagnostic probes. P5 likewise starts with
  generic atoms/composition/mutation, not a named toolbox, and may retain an
  operation only on fresh score-private evidence.
- Every calibration/probe/forging/test/padding action has one persistent
  ledger row. Fresh-test results are evaluator-private until audit closure;
  released campaign totals cannot be joined back to target records.
- A positive requires a forged diagnostic plus forged/revised reusable
  operation to beat a frozen pre-campaign raw-atom baseline on fresh hidden
  tasks across multiple kinds, and P6 must independently verify both memory
  non-leakage and tool novelty.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| P1 | Terra medium | Score-private campaign vault | Can evaluator-owned campaigns prevent any per-target fresh answer from reaching policy memory while retaining reproducible aggregate audit? | **DONE — VAULT FOUNDATION** | Eight anonymous sessions release only unjoinable aggregate total; schema/recovery/restart/privacy/replay gates pass, with no per-target answer fields. Protocol-level, not OS isolation. | `docs/research/score_private_vault_round_p.md`, `results/score_private_vault_round_p.csv`, `sparse_poly_discovery/score_private_vault_round_p.zig` |
| P2 | Luna medium | Causal experience-memory schema | Can an answer-free canonical lab notebook retain reusable attempt→observation→hypothesis experience? | **DONE — CONTROLLED LIMITED POSITIVE** | Canonical enum-only notebook selects 12/12 permitted calibration choices versus blind 2/12; no IDs/formulas/families/fresh answers/winners/mappings/free text. | `docs/research/causal_memory_round_p.md`, `results/causal_memory_round_p.csv`, `sparse_poly_discovery/causal_memory_round_p.zig` |
| P3 | Terra medium | Memory leakage red team | Can any policy-visible memory field reconstruct hidden target/family/fresh answer/winner? | **DONE — CONFIRMED, NARROWED** | Identity recovery 1/12 and every balanced hidden outcome 6/12 (chance); eight forbidden/injected fields quarantined and no answer join/carryover path. Fixture/protocol audit only. | `docs/research/memory_leak_audit_round_p.md`, `results/memory_leak_audit_round_p.csv`, `sparse_poly_discovery/memory_leak_audit_round_p.zig` |
| P4 | Luna medium | Measurement forger | From causal failure hypotheses and generic atoms, can the system synthesize a cheap diagnostic that separates competing explanations? | **RUNNING** | Forged diagnostic beats frozen generic diagnostic baseline per charged cost without answer leakage. | `docs/research/measurement_forge_round_p.md`, `results/measurement_forge_round_p.csv`, `sparse_poly_discovery/measurement_forge_round_p.zig` |
| P5 | Terra medium | Tool/material forger | Can score-private causal experience plus forged measurement produce a reusable operation that beats the pre-campaign raw baseline? | blocked on P1/P2/P3/P4 | Fresh hidden multi-kind win over raw-atom baseline; operation is nonredundant and no answer reaches memory. | `docs/research/tool_forge_round_p.md`, `results/tool_forge_round_p.csv`, `sparse_poly_discovery/tool_forge_round_p.zig` |
| P6 | Terra medium | Independent forge audit | Do vault, memory, measurement, and tool-forge claims survive answer-recovery, renamed-tool, replay, and accounting attacks? | blocked on P1/P2/P3/P4/P5 | Independent rebuild and claim-by-claim pass; no forge claim without it. | `docs/research/round_p_audit.md`, `results/round_p_audit.csv`, `sparse_poly_discovery/round_p_audit.zig` |

## Landing protocol

No agent prose is a result. On each completion, the coordinator rebuilds with
fresh caches, replays artifacts, checks report/CSV agreement, updates this
table and TOC/index, commits scoped work, and launches only dependencies whose
acceptance gates actually pass. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_14c.md`
for live status.
