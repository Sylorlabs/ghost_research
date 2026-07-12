# Research Round 2026-07-12c (Round J) — corrected trajectory evidence before allocation

**Status:** **SETTLED — five executed experiments landed; J6 was validly blocked by J4's negative.**

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
| J2 | Terra medium | Trajectory/near-miss representation | Do corrected cheap prefix-search trajectories separate global, singleton, multi-cell, and no-grammar holdouts better than I1, without near-solving? | **DONE — CONDITIONAL SIGNATURE** | I5 retains 4/4 only as fixed-order, labelled-evaluator separation on four supplied route families. The 120-prefix response changes across valid orders, and `none` is an adjacency grammar—not arbitrary no-grammar. It remains non-autonomous and not an allocator result. | `docs/research/trajectory_repr_round_j.md`, `results/trajectory_repr_round_j.csv`, `sparse_poly_discovery/trajectory_repr_round_j.zig` |
| J3 | Luna medium | Response-cost lower bound | What is the minimum correctly-enumerated prefix budget that separates target types, and does it remain cheaper than near-solve coverage? | **DONE — TERMINAL NEGATIVE** | Target-blind prefix best-score response never separates directed types below full 2,540 calls (16–512: 0/9 directed; 1,270: singleton 0/9, multi-cell 6/9). J2's labelled trajectories—not blind prefix coverage—are the only current cheap lead. | `docs/research/trajectory_cost_round_j.md`, `results/trajectory_cost_round_j.csv`, `sparse_poly_discovery/trajectory_cost_round_j.zig` |
| J4 | Luna medium | Corrected trajectory allocator | Does an accepted J1/J2 representation beat fixed/random/target-blind allocation under equal total cost? | **DONE — VALID NEGATIVE** | With every arm charged 216 response + 384 selection = 600 calls, guided allocation is 10/12 held-out vs fixed 12/12 (iid random 0/12; blind directed coverage 6/12). Correct representation does not yet imply better allocation. | `docs/research/trajectory_allocator_round_j.md`, `results/trajectory_allocator_round_j.csv`, `sparse_poly_discovery/trajectory_allocator_round_j.zig` |
| J5 | Terra medium | Adversarial trajectory audit | Does J2/J4 survive permutation, label-availability, answer-shaped-prefix, unrelated-control, and equal-cost attacks? | **DONE — MIXED AUDIT** | Sampler keys pass; J2 is narrowed to fixed-order labelled-evaluator signature (order-sensitive prefix; supplied adjacency `none` class); J4's equal 600-call guided 10/12 vs fixed 12/12 valid negative is confirmed. | `docs/research/trajectory_audit_round_j.md`, `results/trajectory_audit_round_j.csv`, `sparse_poly_discovery/trajectory_audit_round_j.zig` |
| J6 | Luna medium + Terra review | Conditional autonomous assembly | Does audited trajectory-guided allocation plus live v6 produce a general-prior advance end-to-end? | **BLOCKED BY VALID NEGATIVE** | J4 loses to fixed coverage under equal total cost; an assembly would not support general autonomous prior choice. | — |

## Landing protocol

Native completion events wake the coordinator. On every landing: reproduce the
fast gate, inspect raw/report agreement, commit only scoped artifacts, update
the master table/TOC/index, then launch only dependencies whose stated gates
actually pass. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_12c.md`
after each landing; no result is accepted from agent prose alone.

## Round verdict

**Round J repairs the sampler but does not produce an allocator advance.** J1
removes I1's duplicate-candidate defect with exact unique enumeration. J2's
216-call response is a real fixed-order labelled-evaluator signature on its
supplied corpus, but I5 rules out calling it order-invariant, arbitrary
no-grammar detection, or a general prior representation. J3 further shows
target-blind cheap prefixes cannot replace labelled trajectories.

Most importantly, J4 directly tests the hoped-for bridge and fails honestly:
at equal 600-call cost, guided trajectory allocation is 10/12 while fixed
human-designed coverage is 12/12. I5 independently confirms this negative.
J6 is therefore correctly not run. The remaining unknown is not merely a
better classifier: the system needs a representation and policy that can beat
strong fixed coverage without embedding a useful fixed grammar/order in its
probe bank.
