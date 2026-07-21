# Research Round 2026-07-21b (Round AX) — diverse parallel invention grids

**Status:** LIVE — 0/3 complete.

## Premise

One inventor policy can get trapped in one representation, one repair rule, or
one style of search. AX tests a deliberately diverse population: grid corners
are genuinely distinct invention flavors and interior cells are explicit mixes.
Several grids run under equal total compute, but no correct scalar counts until
the AW replacement evaluator validates a task-typed structural witness.

## Grid axes

1. **Tool grammar / representation:** source structure, CSV integrity, and
   control-flow/behavior analysis.
2. **Search style:** broad coverage, depth-first diagnosis, repair-aggressive,
   and explicit interior mixtures.
3. **Method-memory trust:** conservative established lessons, balanced, and
   experimental/test-first hypotheses.

Grid scaling compares 1×1 homogeneous, 2×2 distinct corners, and 3×3 explicit
interiors. Total worker actions/builds/resources remain identical across
population sizes; renamed copies do not count as diversity.

## Boundary

- No LLM, network, Python, hidden answers, score/progress channel, source
  overlap, or post-hoc flavor changes reaches a worker.
- Each candidate uses native Zag or Zagscript tools only.
- AX measures variety/coverage and prepares scoring. It does **not** call a
  diverse population intelligent or better merely because it has more workers.
- AW's bare-number failure is binding: a score requires typed claims, hashes,
  task-specific structural witnesses, and counterfactual mutation checks.

## Verdict table

| # | Role | Experiment | Question | Status | Required evidence | Planned artifacts |
|---|---|---|---|---|---|---|
| AX1 | Terra | Typed witness evaluator | Can sealed real tasks reject naked scalars and verify precommitted task-specific evidence/witnesses? | running | Kind/hash/witness validation, counterfactual mutations, replay, no answer channel. | `docs/research/typed_witness_evaluator_round_ax.md`, `results/typed_witness_evaluator_round_ax.csv`, `sparse_poly_discovery/typed_witness_evaluator_round_ax.zig` |
| AX2 | Luna | Diverse invention grids | Can multiple genuinely different Zag/Zagscript invention flavors be assigned/recorded under equal compute without fake diversity? | running | Config/tool hashes, axes/interiors, budgets, duplicate/post-hoc/shared-answer attacks, replay. | `docs/research/diverse_invention_grids_round_ax.md`, `results/diverse_invention_grids_round_ax.csv`, `sparse_poly_discovery/diverse_invention_grids_round_ax.zig` |
| AX3 | Terra | Grid scaling audit | Does 2D population variety increase actual distinct work/coverage over homogeneous population at equal total budget? | running | 1×1/2×2/3×3 coverage/duplication/resource ledger; no correctness claim before AX1 integration. | `docs/research/grid_scaling_audit_round_ax.md`, `results/grid_scaling_audit_round_ax.csv`, `sparse_poly_discovery/grid_scaling_audit_round_ax.zig` |

## Landing protocol

Workers may edit only assigned files. Fresh coordinator replay is mandatory.
After components land, the coordinator runs one sealed AX integration over the
AW real artifacts: every grid gets the same total budget and must emit typed
witnesses. An independent reduction audit decides whether an apparent gain is
coverage, genuine tool expansion, a duplicated policy, a hidden answer channel,
or a lucky scalar.
