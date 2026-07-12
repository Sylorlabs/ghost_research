# Research Round 2026-07-12c (Round J) — corrected trajectory evidence before allocation

**Status:** LIVE — 0/6 experiments complete.

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
| J1 | Luna medium | Enumeration and sampler repair | Can a unique, permutation-invariant 1,270-member directed sampler provide valid low-budget prefix probes? | running | Exact uniqueness; residue/mask permutation invariance; no duplicate keys; raw prefix ledgers. | `docs/research/directed_sampler_round_j.md`, `results/directed_sampler_round_j.csv`, `sparse_poly_discovery/directed_sampler_round_j.zig` |
| J2 | Terra medium | Trajectory/near-miss representation | Do corrected cheap prefix-search trajectories separate global, singleton, multi-cell, and no-grammar holdouts better than I1, without near-solving? | running | Cost below full scan; frozen split; no forbidden fields; held-out separation > I1 2/4; leakage/permutation guards pass. | `docs/research/trajectory_repr_round_j.md`, `results/trajectory_repr_round_j.csv`, `sparse_poly_discovery/trajectory_repr_round_j.zig` |
| J3 | Luna medium | Response-cost lower bound | What is the minimum correctly-enumerated prefix budget that separates target types, and does it remain cheaper than near-solve coverage? | running | Sweep costs/seeds; compare full-scan 2,540-call reference; raw accuracy/cost frontier. | `docs/research/trajectory_cost_round_j.md`, `results/trajectory_cost_round_j.csv`, `sparse_poly_discovery/trajectory_cost_round_j.zig` |
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
