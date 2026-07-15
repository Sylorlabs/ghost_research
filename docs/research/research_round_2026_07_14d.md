# Research Round 2026-07-14d (Round Q) — the material expedition

**Status:** LIVE — Q1–Q5 are coordinator-verified; Q5 is a controlled strict material-expedition positive and Q6 is independently auditing the full provenance chain.

**Premise:** Round P proves an answer-free bounded forge can compose supplied
raw atoms into a measurement and reusable operation. The next boundary is
material discovery: the human gives the request and success contract, while
the system chooses which approved material universes to explore, quarantines
what it finds, and forges with only provenance-safe additions. Round Q does
not grant access to hidden evaluators, test manifests, credentials, or
out-of-scope systems; it creates a controlled expedition interface whose
discoveries are auditable rather than answer-key access.

## Frozen wave contract

- The material universe is a typed, content-addressed registry of approved
  local corpora, program/atom spaces, synthetic simulators, and prior public
  forge artifacts. Each item has source, hash, capability descriptor, cost,
  license/policy tag, and lineage. Hidden evaluator state/test manifests are
  not sources and cannot be registered.
- A scout receives only the human request contract, answer-free causal memory,
  policy-safe failure/measurement summaries, and registry descriptors. It may
  request approved material observations but may not inspect hidden test
  targets, evaluator source/state, credentials, or answer-bearing artifacts.
- Quarantine rejects material with answer joins, target/family correlation,
  duplicate/renamed content, missing provenance, or post-test selection. A
  material becomes admitted only after calibration/fresh transfer evidence is
  recorded before it is used on a sealed campaign.
- Every registry search, material observation, quarantine test, forge action,
  baseline, and evaluation action receives an individual persistent ledger row.
  Per-target fresh results remain score-private; only aggregate closure is
  released to policy memory.
- A material/forge positive requires a fresh sealed win over pre-expedition
  raw/fixed/blind baselines on multiple independent request kinds at equal
  total exploration+forging+test cost. Source retrieval alone is not invention.
- Independent audit must reconstruct the entire provenance chain and rule out
  answer leakage, copied evaluator material, material laundering, duplicate
  aliases, and post-hoc selection.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| Q1 | Terra medium | Material universe and provenance registry | Can approved material sources be exposed as typed, content-addressed, answer-safe candidates with complete lineage? | **DONE — REGISTRY FOUNDATION** | Five canonical typed fixture materials; missing provenance, rename duplicate, evaluator/test artifact, hash/traversal, and descriptor privacy gates pass. Fixture only, not literal world access. | `docs/research/material_universe_round_q.md`, `results/material_universe_round_q.csv`, `sparse_poly_discovery/material_universe_round_q.zig` |
| Q2 | Luna medium | Failure-driven material scout | Can causal failure summaries retrieve relevant materials from the registry better than blind/material-prior retrieval? | **DONE — CONTROLLED POSITIVE** | Failure-driven public-passport scout 12/12 held-out calibration retrieval versus prior/blind 4/12 at equal two-action cost; fixture descriptors/residual vocabulary supplied. | `docs/research/material_scout_round_q.md`, `results/material_scout_round_q.csv`, `sparse_poly_discovery/material_scout_round_q.zig` |
| Q3 | Terra medium | Material quarantine and leakage audit | Can unsafe, duplicate, answer-correlated, or unproven materials be rejected before forge admission? | **DONE — SAFETY FOUNDATION** | Admits 2/11 provenance-qualified materials and rejects all nine unsafe/duplicate routes with individual charged inspections and deterministic replay. | `docs/research/material_quarantine_round_q.md`, `results/material_quarantine_round_q.csv`, `sparse_poly_discovery/material_quarantine_round_q.zig` |
| Q4 | Luna medium | Material forger | Can admitted materials be combined or transformed into a nonredundant primitive that beats its component materials? | **DONE — CONTROLLED STRICT POSITIVE** | Provenance-lineaged count+relation material 24/24 aggregate fresh across three variants versus components/fixed 0/24 and blind 8/24, all at four ledgered actions/session. Fixture registry/residual vocabulary supplied. | `docs/research/material_forge_round_q.md`, `results/material_forge_round_q.csv`, `sparse_poly_discovery/material_forge_round_q.zig` |
| Q5 | Terra medium | Autonomous material expedition | Does request → gap → scout → quarantine → forge → measure → tool → fresh test beat pre-expedition baselines? | **DONE — CONTROLLED STRICT POSITIVE** | Post-freeze three-cohort expedition 24/24 versus pre-expedition raw/fixed/no-prior 0/24 and blind 8/24 at equal six persistent calls/session; lineage, alias, privacy, order, closure-only, and ledger gates pass. | `docs/research/material_expedition_round_q.md`, `results/material_expedition_round_q.csv`, `sparse_poly_discovery/material_expedition_round_q.zig` |
| Q6 | Terra medium | Independent expedition audit | Does the full provenance chain and expedition result survive source/leakage/alias/cost/replay attacks? | **RUNNING** | Independent claim-by-claim pass; no open-material claim without it. | `docs/research/round_q_audit.md`, `results/round_q_audit.csv`, `sparse_poly_discovery/round_q_audit.zig` |

## Landing protocol

No agent prose is a result. On each completion, the coordinator rebuilds with
fresh caches, replays outputs, checks report/CSV agreement, updates this table
and TOC/index, commits scoped work, and launches only dependencies whose gates
actually passed. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_14d.md`
for current status.
