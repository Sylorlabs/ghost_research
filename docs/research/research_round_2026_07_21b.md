# Research Round 2026-07-21b (Round AX) — diverse parallel invention grids

**Status:** COMPLETE — real staged-artifact typed scoring now runs; result is
protocol-valid coverage, not invention evidence.

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
| AX1 | Terra | Typed witness evaluator | Can sealed real tasks reject naked scalars and verify precommitted task-specific evidence/witnesses? | **EVALUATOR READY** | Four task kinds; scalar/malformed claims reject; kind/tool/payload hashes bind; relevant mutations change evidence, unrelated bytes do not; deterministic replay. | `docs/research/typed_witness_evaluator_round_ax.md`, `results/typed_witness_evaluator_round_ax.csv`, `sparse_poly_discovery/typed_witness_evaluator_round_ax.zig` |
| AX2 | Luna | Diverse invention grids | Can multiple genuinely different Zag/Zagscript invention flavors be assigned/recorded under equal compute without fake diversity? | **GRID READY** | 27 unique 3×3×3 configurations, 8 corners/19 interiors, 48 actions each/1,296 total; duplicate/unequal/shared-answer/post-hoc/fake-diversity attacks reject; replay identical. | `docs/research/diverse_invention_grids_round_ax.md`, `results/diverse_invention_grids_round_ax.csv`, `sparse_poly_discovery/diverse_invention_grids_round_ax.zig` |
| AX3 | Terra | Grid scaling audit | Does 2D population variety increase actual distinct work/coverage over homogeneous population at equal total budget? | **AUDIT READY** | 1×1/2×2/3×3 equal 54-step populations; canonical unique tool forms 2/4/5, branches 2/4/5, duplicate aliases cannot inflate diversity; no correctness claim. | `docs/research/grid_scaling_audit_round_ax.md`, `results/grid_scaling_audit_round_ax.csv`, `sparse_poly_discovery/grid_scaling_audit_round_ax.zig` |
| AX4 | Coordinator | Real typed-witness integration | Does the grid obtain credit only for task-specific evidence on AW's staged real artifacts? | **COMPLETE — NARROW POSITIVE** | **36/108 accepted, 9/27 per task**; byte-identical replay; relevant staged declaration mutation drops 36→27. These are three supplied tool forms covering compatible tasks, not 27 inventions, an advantage, or isolated security. | `docs/research/ax_real_integration_round_ax.md`, `results/ax_real_integration_round_ax.csv`, `sparse_poly_discovery/ax_real_integration_round_ax.zig`, `scripts/run_round_ax_integration.sh` |

## Landing protocol

Workers may edit only assigned files. Fresh coordinator replay is mandatory.
The coordinator ran that integration. Every grid identity received the same
48-action ledger allocation and candidate mode emitted only typed witnesses.
The independent reducer accepted 36 of 108 compatible task attempts (9 per
task) and rejected all other no-witness attempts. This establishes coverage
and fixes AW's lucky-scalar failure; it does not establish a gain over a fixed
three-tool portfolio or independent grammar discovery.

## Component results

Fresh coordinator checks pass. AX1 binds each claim to task kind, tool and
payload hashes, a canonical structural witness, and counterfactual mutation
behavior; a scalar-only claim is invalid. AX2 produces 27 genuinely distinct
flavors across grammar, allocation, and method-memory trust axes under exactly
48 actions per worker. AX3 verifies that, at equal total population work, the
canonical tool/branch coverage grows 2→4→5 from 1×1 to 3×3 and aliases do not
inflate that count. This is evidence of real variety/coverage—not correctness,
invention, or an advantage over a homogeneous population until typed scoring
executes on the staged corpus. AX4 did execute: each structural task obtains
nine valid, payload-bound witnesses, and mutating a relevant payload invalidates
all 27 claims for that task (36→27 total). The result is intentionally narrow:
three human-supplied tool grammars cover four compatible task families. It is
not a population-invention, tool-selection, security-isolation, or intelligence
claim.
