# Research Round 2026-07-14e (Round R) — the self-governing knowledge expedition

**Status:** LIVE — 0/6 experiments complete.

**Premise:** Rounds P/Q build an answer-free bounded forge and an approved
fixture-material expedition. Round R removes human per-material curation. The
system receives the human invention request and high-level safety authority,
then autonomously discovers, ranks, captures, quarantines, refines, and retires
knowledge materials from available read-only worlds. It must not receive a
human-maintained material list or hidden evaluator/test data.

## Autonomous knowledge-governance contract

- The system, not a human, chooses candidate sources and materials. A source
  governor applies general rules rather than hand-curated source lists:
  read-only acquisition; content-addressed capture; provenance/time/license
  metadata; task relevance; duplication/alias detection; corruption and answer
  overlap checks; source reputation/contradiction scoring; and quarantine or
  retirement when evidence fails.
- Its exploration authority is broad but logical: it may inspect accessible
  public documents, code, datasets, and simulators through adapters; it may not
  access credentials, private systems, evaluator process/state, hidden test
  manifests, per-target fresh answers, or circumvent source permissions.
- The human supplies only the invention request, success contract, and general
  authority/safety constraints—not a tool menu, material list, diagnostic,
  source-by-source approval, or target-specific knowledge.
- Every acquired source/material/principle has an immutable provenance record
  (origin, retrieval time, content hash, policy decision, extraction lineage,
  contradiction status, cost) and must pass answer-leak, duplication, and
  post-test-selection quarantine before forge admission.
- Principles are structured falsifiable claims: conditions, mechanism,
  prediction, expected failure signature, candidate measurement, candidate
  material/primitive, and source support. They must earn retention through
  independent evidence, not citation count or free-text resemblance.
- Evaluator state and score-private test closure reside outside policy-readable
  source/material storage. Per-target fresh outcomes never enter memory; only
  aggregate closure and answer-free causal observations may influence future
  exploration.
- A positive requires autonomous source selection → principle refinement →
  material/atom expansion → fresh hidden multi-kind gain over raw/fixed/blind
  at equal total acquisition+reasoning+forge+test cost, with independent audit.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| R1 | Terra medium | Hardened evaluator service | Can score-private evaluator/test state run behind a policy-unreadable service boundary with aggregate-only closure? | **RUNNING** | Separate process/storage boundary; policy read/score attacks denied; persistent budget and deterministic audit replay pass. | `docs/research/hardened_evaluator_service_round_r.md`, `results/hardened_evaluator_service_round_r.csv`, `sparse_poly_discovery/hardened_evaluator_service_round_r.zig` |
| R2 | Terra medium | Self-governing knowledge world | Can a source governor autonomously discover and manage candidate public materials without human source curation? | **RUNNING** | Dynamic candidate discovery and content capture; policy-based admit/quarantine/retire; no evaluator/test/credential access; deterministic provenance replay. | `docs/research/autonomous_knowledge_world_round_r.md`, `results/autonomous_knowledge_world_round_r.csv`, `sparse_poly_discovery/autonomous_knowledge_world_round_r.zig` |
| R3 | Luna medium | Principle refinery | Can acquired source material be distilled into falsifiable, answer-safe mechanisms that improve held-out calibration over raw retrieval? | **RUNNING** | Structured principles beat raw retrieval/prior on independent calibration and pass contradiction/answer-leak checks. | `docs/research/principle_refinery_round_r.md`, `results/principle_refinery_round_r.csv`, `sparse_poly_discovery/principle_refinery_round_r.zig` |
| R4 | Luna medium | Self-expanding atom forge | Can source-derived principles autonomously add a nonredundant raw material/primitive beyond the prior atom alphabet? | blocked on R1/R2/R3 | New admitted primitive has provenance, survives quarantine, and beats source atoms on fresh hidden transfer. | `docs/research/atom_expansion_round_r.md`, `results/atom_expansion_round_r.csv`, `sparse_poly_discovery/atom_expansion_round_r.zig` |
| R5 | Terra medium | Real-world transfer expedition | Does autonomous request → discovery → refinement → expansion → forge beat baselines on independently selected non-synthetic tasks? | blocked on R1/R2/R3/R4 | Fresh multi-kind equal-total-cost win; no human material/source/tool selection; score-private closure. | `docs/research/real_world_expedition_round_r.md`, `results/real_world_expedition_round_r.csv`, `sparse_poly_discovery/real_world_expedition_round_r.zig` |
| R6 | Terra medium | Architecture certification audit | Does source governance, evaluator isolation, principles, atoms, and transfer claim survive provenance/leakage/copy/replay/cost attacks? | blocked on R1/R2/R3/R4/R5 | Independent reconstruction and claim-by-claim pass; no architecture-complete claim without it. | `docs/research/round_r_audit.md`, `results/round_r_audit.csv`, `sparse_poly_discovery/round_r_audit.zig` |

## Landing protocol

No agent prose is a result. On each completion, the coordinator rebuilds with
fresh caches, replays artifacts, checks report/CSV agreement, updates this
table and TOC/index, commits scoped work, and launches only dependencies whose
gates pass. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_14e.md`
for live status.
