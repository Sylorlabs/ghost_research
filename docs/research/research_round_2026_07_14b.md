# Research Round 2026-07-14b (Round O) — active probes before tool commitment

**Status:** LIVE — O1–O5 are coordinator-verified; O5 is a controlled strict positive and O6 is independently auditing the full active loop.

**Premise:** Round N removed the trace-to-tool shortcut and thereby removed
the Round M closed-loop gain: frozen failure memory retained promising
compositions but could not choose which applied to a genuinely fresh target.
Round O tests the missing capability: **active information acquisition**. A
policy may spend a declared probe budget on evaluator-owned, policy-safe
diagnostics before committing a grammar; it must prove that the probes—not a
hidden trace/ID shortcut—improve fresh equal-cost discovery.

## Frozen wave contract

- Target formulas, family labels, target IDs as policy features, masks,
  parameters, audit fields, and test labels remain evaluator-private. Public
  trace is intentionally family-nondiagnostic as in Round N.
- O1 probes are predeclared public experiments with individually charged costs
  and aggregate-only replies. They must have measured conditional family
  information while the base trace remains at family-prior chance.
- Every arm receives the same total evaluator budget. Probe, query, baseline,
  padding, selection, and fresh-test actions each occupy one raw ledger row;
  persistent state prevents restart resets.
- Probe policy may use only frozen failure history plus previous policy-safe
  replies from the current session. It cannot inspect test outcomes before its
  grammar/family commitment.
- A positive requires fresh evaluator-owned test wins over both fixed and
  blind controls at equal cost across more than one independent decoupled
  family, plus proof that probe choices—not token/order/family leakage—supply
  the information advantage.
- Every landing supplies Zig harness, CSV, report, deterministic replay,
  central documentation, scoped commit, and independent audit before any broad
  autonomy claim.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| O1 | Terra medium | Probe catalog and information curve | Can safe evaluator probes reveal conditional family information when base trace is exactly non-diagnostic? | **DONE — CONTROLLED PROTOCOL POSITIVE** | Passive trace/prior 4/8; either one-cost declared aggregate probe 8/8 (1 bit); redundant two-probe sequence remains 8/8 at half information/cost. | `docs/research/probe_catalog_round_o.md`, `results/probe_catalog_round_o.csv`, `sparse_poly_discovery/probe_catalog_round_o.zig` |
| O2 | Luna medium | Probe-policy learner | Can frozen history learn which probe to buy from an uninformative base trace and earlier replies? | **DONE — CONTROLLED POSITIVE** | Learned probe policy 12/12, fixed/blind probes 9/12, family-prior/no-probe 6/12 at equal three-call budget; reversal/privacy/restart controls pass. | `docs/research/probe_policy_round_o.md`, `results/probe_policy_round_o.csv`, `sparse_poly_discovery/probe_policy_round_o.zig` |
| O3 | Terra medium | Probe leakage/equal-cost audit | Do O1/O2 preserve decoupling, avoid target-ID/order leakage, and charge every information action fairly? | **DONE — PROTOCOL AUDIT PASS** | Base trace 2/4 = prior; tokens never policy inputs; heldout probe denied; 96 individually logged cost-matched train calls, restart and private-field controls pass. | `docs/research/probe_audit_round_o.md`, `results/probe_audit_round_o.csv`, `sparse_poly_discovery/probe_audit_round_o.zig` |
| O4 | Luna medium | Probe-guided grammar commitment | Do active probe replies choose a memory-supported grammar better than blind/fixed commitment on fresh targets? | **DONE — CONTROLLED STRICT POSITIVE** | Guided grammar 16/16 fresh versus fixed/blind/prior/no-probe 8/16 at equal four-call budgets; 8/8 in each two evaluator-owned cohorts, commitment precedes scoring. | `docs/research/probe_guided_grammar_round_o.md`, `results/probe_guided_grammar_round_o.csv`, `sparse_poly_discovery/probe_guided_grammar_round_o.zig` |
| O5 | Terra medium | Active closed loop | Does map → memory → probe → propose → fresh-test beat controls on a post-policy-freeze decoupled suite? | **DONE — CONTROLLED STRICT POSITIVE** | New 24-token three-cohort suite: active 24/24 versus fixed/blind/no-probe 12/24 at equal four persistent calls/arm/target; commitment, reversal, privacy, and ledger controls pass. | `docs/research/active_closed_loop_round_o.md`, `results/active_closed_loop_round_o.csv`, `sparse_poly_discovery/active_closed_loop_round_o.zig` |
| O6 | Terra medium | Red-team active-probe audit | Do probe catalog, policy, grammar, and closed-loop claims survive adaptive leakage and accounting attacks? | **RUNNING** | Independent replay; no broad claim without pass. | `docs/research/round_o_audit.md`, `results/round_o_audit.csv`, `sparse_poly_discovery/round_o_audit.zig` |

## Landing protocol

No agent prose is a result. On each completion, the coordinator rebuilds with
fresh caches, replays the ledger, checks report/CSV agreement, updates this
table and TOC/index, commits scoped artifacts, and launches only dependencies
whose acceptance gates truly passed. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_14b.md`
for current status.
