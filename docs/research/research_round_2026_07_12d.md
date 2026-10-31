# Research Round 2026-07-12d (Round K) — adaptive allocation versus fixed coverage

**Status:** SETTLED — 5/6 experiments resolved: K3's valid negative is independently audited; K6 remains correctly blocked.

**Premise:** Round J repaired the sampler and found a cheap but conditional
trajectory signature, yet the equal-cost trajectory allocator lost to fixed
human-designed coverage (10/12 vs 12/12 at 600 calls). Round K tests the
remaining possibility: whether an adaptive policy can use early, correctly
enumerated search outcomes to allocate remaining budget better than that strong
fixed baseline on genuinely fresh hidden structures.

## Frozen wave contract

- Every directed grammar enumeration is exact 1,270 unique semantic keys with
  duplicate assertions and mask/residue/order permutation controls.
- K1 must decompose the fixed 12/12 policy before K3 is designed; K3 may not
  tune against held-out targets after seeing that decomposition.
- K2 features must be permutation-invariant distributions/trajectories, never
  a fixed useful candidate order. K4 generates fresh held-out structures after
  policy freeze: randomized masks, partition sizes, moduli, residues, and
  unrelated controls.
- All K3 arms charge exploration, routing, selection, and certification calls
  against the same total budget and receive the same labelled evaluator access.
- A positive requires adaptive > fixed > random/blind on K4 untouched cells;
  ties or a fixed loss are valid negatives. K5 independently audits every
  positive path before K6 can run.
- Native agent completion wakes the coordinator. Each landing is reproduced,
  committed with scoped harness/CSV/report, and updates this table, the TOC,
  index, and `research_round_status.sh`.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| K1 | Terra medium | Fixed-policy forensic | Why does fixed coverage reach 12/12, and what minimal bank/call allocation actually causes each solve? | **DONE — RUNTIME VERIFIED** | Full fixed is 12/12; global/adjacency/directed ablations each fall to 9/12, but singleton is redundant (directed index 35 covers it). Directed 200 reaches 12/12; post-hoc frozen-suite minimum is 127 calls (global 5 + adjacency 1 + directed 121). | `docs/research/fixed_policy_forensic_round_k.md`, `results/fixed_policy_forensic_round_k.csv`, `sparse_poly_discovery/fixed_policy_forensic_round_k.zig` |
| K2 | Luna medium | Permutation-invariant trajectory features | Can distributional score-improvement/near-miss/residual trajectories separate routes without fixed useful ordering? | **DONE — LIMITED POSITIVE** | 24 permutation-invariant distribution/trajectory features separate 4/4 frozen held-out routes at 254 calls, below full scan; unique enum/order/mask/residue guards pass. Requires labelled evaluator examples and has not beaten fixed allocation. | `docs/research/invariant_trajectory_round_k.md`, `results/invariant_trajectory_round_k.csv`, `sparse_poly_discovery/invariant_trajectory_round_k.zig` |
| K3 | Terra medium | Adaptive elimination allocator | Does cheap exploration then adaptive bank elimination beat fixed coverage at equal total cost? | **DONE — VALID NEGATIVE** | At 600 charged calls per hidden target, adaptive is 10/24, K1-informed fixed is 10/24, blind directed is 10/24, and IID is 9/24. The required strict adaptive win fails. | `docs/research/adaptive_allocator_round_k.md`, `results/adaptive_allocator_round_k.csv`, `sparse_poly_discovery/adaptive_allocator_round_k.zig` |
| K4 | Luna medium | Hidden-structure holdout generator | Can a post-policy-freeze randomized test suite prevent canned route-family wins? | **DONE — VALID EVALUATION INFRASTRUCTURE** | Deterministic committed-seed 24-target suite spans directed sizes 1–4 plus threshold/adjacency/XOR/parity controls; all targets nondegenerate/unique with policy-safe and audit fields separated. | `docs/research/hidden_holdout_round_k.md`, `results/hidden_holdout_round_k.csv`, `sparse_poly_discovery/hidden_holdout_round_k.zig` |
| K5 | Terra medium | Adversarial policy audit | Do K2/K3 survive leakage, order, label-availability, baseline, and hidden-suite attacks? | **DONE — K3 NEGATIVE CONFIRMED** | K2 feature claim and K4 integrity survive; K3's 96 rows all charge 600 calls and recount 10/10/10/9. Caveat: the holdout boundary is procedural, not process-isolated. | `docs/research/adaptive_policy_audit_round_k.md`, `results/adaptive_policy_audit_round_k.csv`, `sparse_poly_discovery/adaptive_policy_audit_round_k.zig` |
| K6 | Luna medium + Terra review | Conditional autonomous assembly | Does audited adaptive allocation plus live v6 improve end-to-end discovery/promotion? | **BLOCKED BY VALID NEGATIVE** | K3 did not strictly beat fixed/random/blind, so no autonomous-assembly claim is authorized in this wave. | `docs/research/genofgen_round_k.md`, `results/genofgen_round_k.csv`, `sparse_poly_discovery/genofgen_round_k.zig` |

## Landing protocol

No agent prose is accepted as a result. On each native completion event, the
coordinator reruns the fast gate, inspects CSV/report agreement, commits scoped
artifacts, updates documentation, and launches only dependencies whose stated
acceptance gates passed. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_12d.md`
for per-agent and all-settled status.
