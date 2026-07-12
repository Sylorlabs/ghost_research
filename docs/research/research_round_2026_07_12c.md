# Research Round 2026-07-12c (Round J) — corrected trajectory evidence before allocation

**Status:** LIVE — 3/6 experiments complete; J2 supplies trajectory evidence and J3 rejects target-blind cheap prefixes.

**Premise:** Round I settled the response-allocation question negatively. I1's
apparent response atlas is invalidated by a duplicate-candidate enumeration
defect; I2's symmetric partition result is a 2,540-call near-solve; I3 matches
fixed allocation; I4 finds blind search competitive. The next justified target
is narrower: a **correctly enumerated, cheap trajectory/near-miss response**
that earns the right to be tested as an allocator input.

## Frozen wave contract

- All directed grammars must use the exact 1,270-member enumeration
  `254 * (2 mod-2 residues + 3 mod-3 residues)`. Harnesses must assert unique
  candidate keys and run mask/residue permutation controls before reporting a
  result.
- A response feature may use only predeclared prefix-search observables:
  validation-gain trajectory, near-miss margin, residual structure, candidate
  diversity, and cost. It must state whether labeled examples are available at
  deployment time; target name/formula/family/anchor/mask/residue remain
  forbidden inputs.
- Cheap means materially below a full 1,270 train + 1,270 validation scan.
  Every result reports candidate calls separately for response generation,
  routing, selection, and certification.
- Fixed/random/target-blind controls must match selected-candidate budgets.
  No allocator or assembly runs until a trajectory representation passes
  enumeration integrity, leakage, held-out separation, and cost gates.
- Each completion is independently reproduced, committed with scoped
  harness/CSV/report, and reflected in this table, `RESEARCH_TOC.md`,
  `INDEX.md`, and `research_round_status.sh`.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| J1 | Luna medium | Enumeration and sampler repair | Can a unique, permutation-invariant 1,270-member directed sampler provide valid low-budget prefix probes? | **DONE — POSITIVE SUBSTRATE REPAIR** | Exact 1,270 unique candidates; every prefix duplicate-free; mask/residue permutation checks pass across three samplers/seeds and all raw integrity rows. This repairs fairness substrate only—no routing/efficiency claim. | `docs/research/directed_sampler_round_j.md`, `results/directed_sampler_round_j.csv`, `sparse_poly_discovery/directed_sampler_round_j.zig` |
| J2 | Terra medium | Trajectory/near-miss representation | Do corrected cheap prefix-search trajectories separate global, singleton, multi-cell, and no-grammar holdouts better than I1, without near-solving? | **DONE — NARROW POSITIVE** | Correctly enumerated 216-call trajectory features separate 4/4 held-out routes (> I1 2/4), cost 8.5% of full 2,540 scan, and pass distance/permutation guards. Requires labeled evaluator examples before routing; not allocator/autonomy evidence. | `docs/research/trajectory_repr_round_j.md`, `results/trajectory_repr_round_j.csv`, `sparse_poly_discovery/trajectory_repr_round_j.zig` |
| J3 | Luna medium | Response-cost lower bound | What is the minimum correctly-enumerated prefix budget that separates target types, and does it remain cheaper than near-solve coverage? | **DONE — TERMINAL NEGATIVE** | Target-blind prefix best-score response never separates directed types below full 2,540 calls (16–512: 0/9 directed; 1,270: singleton 0/9, multi-cell 6/9). J2's labelled trajectories—not blind prefix coverage—are the only current cheap lead. | `docs/research/trajectory_cost_round_j.md`, `results/trajectory_cost_round_j.csv`, `sparse_poly_discovery/trajectory_cost_round_j.zig` |
| J4 | Luna medium | Corrected trajectory allocator | Does an accepted J1/J2 representation beat fixed/random/target-blind allocation under equal total cost? | blocked on J1/J2/J3 | Strict held-out improvement over fixed and all baselines; integrity/cost gates retained. | `docs/research/trajectory_allocator_round_j.md`, `results/trajectory_allocator_round_j.csv`, `sparse_poly_discovery/trajectory_allocator_round_j.zig` |
| J5 | Terra medium | Adversarial trajectory audit | Does J2/J4 survive permutation, label-availability, answer-shaped-prefix, unrelated-control, and equal-cost attacks? | blocked on J1/J2/J4 | Independent sampler/replay; all positive paths challenged; explicit audit verdict. | `docs/research/trajectory_audit_round_j.md`, `results/trajectory_audit_round_j.csv`, `sparse_poly_discovery/trajectory_audit_round_j.zig` |
| J6 | Luna medium + Terra review | Conditional autonomous assembly | Does audited trajectory-guided allocation plus live v6 produce a general-prior advance end-to-end? | blocked on J4/J5 | Held-out structures; equal total cost; live v6; all promotion sources tracked; Terra accepts scope. | `docs/research/genofgen_round_j.md`, `results/genofgen_round_j.csv`, `sparse_poly_discovery/genofgen_round_j.zig` |

## Landing protocol

Native completion events wake the coordinator. On every landing: reproduce the
fast gate, inspect raw/report agreement, commit only scoped artifacts, update
the master table/TOC/index, then launch only dependencies whose stated gates
actually pass. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_12c.md`
after each landing; no result is accepted from agent prose alone.
