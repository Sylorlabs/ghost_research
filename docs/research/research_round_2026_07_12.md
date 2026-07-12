# Research Round 2026-07-12 (Round H) — failure evidence to autonomous prior choice

**Status:** LIVE — 3/6 experiments complete; H2 is blocked by H1's valid negative and H6 is ready.

**Premise:** Round G repaired the novelty gate (G1), built a valid
production-derived corpus (G2), and showed both a valid negative for the
current six-descriptor 1-NN selector (G3) and a constrained grammar-invention
positive (G4). The remaining question is no longer whether a useful grammar
can be formed, but whether failure evidence can autonomously route or propose
one on held-out targets under fair budgets and live certification.

## Frozen wave contract

- Every result gets a standalone Zig harness, raw CSV, report, fixed seeds and
  budgets, explicit validity gates, central commit, master-table update, and
  TOC entry when it lands.
- G2's split remains frozen; no target name, formula, family label, or audit
  field may enter a selector/proposer inference input.
- H4 must equalize the candidate-evaluation treatment that G4 intentionally
  did not equalize. H5 must run G1's decision rule live, not reuse its fixture.
- The coordinator waits on native completion events and runs
  `./scripts/research_round_status.sh docs/research/research_round_2026_07_12.md`
  after each landing. `ROUND_SETTLED` and `ROUND_COMPLETE` are the durable
  status signals; agents are never treated as complete from chat prose alone.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| H1 | Luna medium | Failure-representation audit | Do richer residual/probe descriptors separate the G2 prior needs without leakage? | **DONE — VALID NEGATIVE** | **No accepted descriptor contract.** Validation-selected `full16` reaches 4/4 validation but only 1/4 untouched holdout, equal to fixed routing; split, forbidden-field, and leakage gates pass (distance 1.448328 > 0.05). | `docs/research/failure_repr_round_h.md`, `results/failure_repr_round_h.csv`, `sparse_poly_discovery/failure_repr_round_h.zig` |
| H2 | Luna medium | Learned-router rematch | Does an H1-derived frozen representation beat fixed/random routing on G2 holdout? | **BLOCKED BY VALID NEGATIVE** | H1 supplies no improved frozen descriptor contract; launching H2 would post-hoc repeat a known non-improvement. | — |
| H3 | Terra medium | Direct grammar proposer | Can failure evidence choose a grammar search space directly, bypassing fixed-family classification? | **DONE — CONSTRAINED POSITIVE** | Failure-guided admission deterministically finds an exact directed grammar on 3 seeds plus held-out pivot/modulus variant; threshold menu is 0.611–0.649. Equal-budget blind directed search remains competitive (exact-hit 0.484–0.734), so the gain is reliable aim inside a finite human-supplied grammar, not escape from random search/primitives. | `docs/research/direct_proposer_round_h.md`, `results/direct_proposer_round_h.csv`, `sparse_poly_discovery/direct_proposer_round_h.zig` |
| H4 | Terra medium | G4 fairness and robustness audit | Does G4 survive equal candidate budgets, varied anchors/residues, and unseen structural variants? | queued | Equal-budget controls plus held-out structural variants; distinguish grammar prior from target leakage. | `docs/research/prior_invention_audit_round_h.md`, `results/prior_invention_audit_round_h.csv`, `sparse_poly_discovery/prior_invention_audit_round_h.zig` |
| H5 | Terra medium | Live gate-v6 integration | Does G1's gate behave correctly and economically inside a real promotion loop, including G4/RUN cases? | **DONE — POSITIVE LIVE EVIDENCE** | Fresh live loops give v6 4/4 correct vs legacy 2/4: both RUN false rejections become admissions, exact count remix remains rejected, and promotions rise 1→3. Small synthetic four-control battery/reference library means this is not production adoption. | `docs/research/gate_v6_live_round_h.md`, `results/gate_v6_live_round_h.csv`, `sparse_poly_discovery/gate_v6_live_round_h.zig` |
| H6 | Luna medium + Terra review | Conditional autonomous assembly | Does an accepted H2 or H3 plus H5 remove per-target human prior choice end-to-end? | ready for H3/H5 inputs | Frozen components; held-out family test; equal-budget hand/fixed/random/cold controls; Terra acceptance review. | `docs/research/genofgen_round_h.md`, `results/genofgen_round_h.csv`, `sparse_poly_discovery/genofgen_round_h.zig` |

## Completion protocol

Each agent returns scoped artifacts only. On a native completion event, the
coordinator reproduces a fast gate, inspects report/data agreement, commits the
scoped artifacts, updates this table and `RESEARCH_TOC.md`, then launches the
next dependency or queued audit. The wave closes only when its status harness
reports `ROUND_COMPLETE=YES` and Terra has accepted the cross-experiment claim.
