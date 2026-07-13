# Research Round 2026-07-12e (Round L) — map-making: discover the missing tool family

**Status:** SETTLED — L1–L3 are limited infrastructure positives, L4 is a valid negative, and L5 independently confirms the scope and its remaining evaluator/accounting limits.

**Premise:** Rounds I–K establish that choosing among human-designed finite
coverage banks does not yet outperform broad fixed coverage. The next question
is one level higher: can the system build an evidence-backed *map* of its
failure space, identify a target that lies outside the mapped families, and
propose a reusable grammar extension without being handed that family label?

## Frozen wave contract

- A map is an explicit, machine-readable partition over observable search
  traces and candidate outcomes, not prose labels or target IDs.
- A blank-region claim must survive target/mask/order permutation, duplicate,
  and label-leakage controls; it cannot be defined from evaluator-private
  formula or audit fields.
- The family proposer may consume only the frozen map and policy-safe failure
  trace. It cannot inspect sealed target formulas or a human-supplied missing
  family name.
- The evaluator process owns post-freeze target formulas and audit manifests;
  proposal/policy processes receive only declared labelled examples and scores.
- A positive requires a proposed extension to solve at least two sealed members
  of one previously unmapped region and beat the frozen existing-menu baseline
  at equal charged cost. A one-target hit, a map label based on private target
  data, or a tie is a valid negative.
- Every landing supplies a Zig harness, raw CSV, standalone report, deterministic
  selftest where feasible, central-table update, TOC/index update, and commit
  when Git access permits. Independent audit gates the closed-loop assembly.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| L1 | Terra medium | Failure-space atlas | Can prior and fresh policy-safe failure traces be clustered into stable, useful regions without target/family labels? | **DONE — LIMITED POSITIVE** | Trace-only four-bin score histograms predict 12/12 held-out solve-by-254 outcomes versus 8/12 majority; reverse-order and duplicate guards pass. Controlled corpus only, not semantic map-making. | `docs/research/failure_atlas_round_l.md`, `results/failure_atlas_round_l.csv`, `sparse_poly_discovery/failure_atlas_round_l.zig` |
| L2 | Luna medium | Blank-region detector | Can an observable trace-only detector identify targets outside the existing map without seeing their formulas or audit fields? | **DONE — LIMITED POSITIVE** | Trace-only detector flags 4/4 unmapped and retains 8/8 represented held-out cells; precision/recall 1.000 with order/mask/residue/permutation/duplicate guards. Synthetic cells only. | `docs/research/blank_region_round_l.md`, `results/blank_region_round_l.csv`, `sparse_poly_discovery/blank_region_round_l.zig` |
| L3 | Terra medium | Sealed evaluator substrate | Can target formulas and audit manifest be isolated from proposer/policy inputs while preserving deterministic reproduction? | **DONE — PROTOCOL BOUNDARY + PUBLIC EXPERIMENT API** | Opaque transcript, audit-column rejection, byte-identical replay, plus policy-safe current-menu diagnostics and charged candidate queries pass. Process-mode only; no OS isolation or persistent budget authority. | `docs/research/sealed_evaluator_round_l.md`, `results/sealed_evaluator_round_l.csv`, `results/sealed_evaluator_api_round_l.csv`, `sparse_poly_discovery/sealed_evaluator_round_l.zig` |
| L4 | Luna medium + Terra review | Family invention expedition | From L1/L2 map plus L3 transcript only, can it propose a new reusable grammar extension for a detected blank region? | **DONE — VALID NEGATIVE** | Public API makes the trial defined. Threshold extension exact-wins one blank token (12/12 vs 10/12) at equal 412 calls, but misses the other (10/12 vs 11/12); two-target transfer criterion fails. | `docs/research/family_expedition_round_l.md`, `results/family_expedition_round_l.csv`, `sparse_poly_discovery/family_expedition_round_l.zig` |
| L5 | Terra medium | Cartography audit | Do the map, blank claim, sealed boundary, and any L4 result survive leakage, duplication, cost, and baseline attacks? | **DONE — L4 NEGATIVE CONFIRMED** | API has no formula/mask/audit fields and L4's one-of-two win recount survives; however transcript labels are reused for query scoring and 332 padding calls are summarized rather than individually ledgered. | `docs/research/cartography_audit_round_l.md`, `results/cartography_audit_round_l.csv`, `sparse_poly_discovery/cartography_audit_round_l.zig` |

## Landing protocol

No agent prose is accepted as a result. On each native completion event, the
coordinator reruns the declared gate, checks harness/CSV/report agreement,
updates this table and the TOC/index, and launches only dependencies whose
acceptance gates passed. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_12e.md`
for per-agent and all-settled status.
