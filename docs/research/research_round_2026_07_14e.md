# Research Round 2026-07-14e (Round R) — the self-governing knowledge expedition

**Status:** GATED — 3/6 foundation experiments replayed; R4–R6 must not run as an architecture-complete claim.

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
| R1 | Terra medium | Hardened evaluator service | Can score-private evaluator/test state run behind a policy-unreadable service boundary with aggregate-only closure? | **DONE — limited foundation** | Protocol attacks denied; persistent budget and deterministic replay pass. **Not hostile same-user isolation**: separate OS account/container/MAC remains required. | `docs/research/hardened_evaluator_service_round_r.md`, `results/hardened_evaluator_service_round_r.csv`, `sparse_poly_discovery/hardened_evaluator_service_round_r.zig` |
| R2 | Terra medium | Self-governing knowledge world | Can a source governor autonomously discover and manage candidate public materials without human source curation? | **DONE — limited foundation** | Dynamic local-public discovery/capture/quarantine/replay pass. **No live network/corpus adapter** (`NOT_AVAILABLE`), so it does not meet real-world transfer admission. | `docs/research/autonomous_knowledge_world_round_r.md`, `results/autonomous_knowledge_world_round_r.csv`, `sparse_poly_discovery/autonomous_knowledge_world_round_r.zig` |
| R3 | Luna medium | Principle refinery | Can acquired source material be distilled into falsifiable, answer-safe mechanisms that improve held-out calibration over raw retrieval? | **DONE — controlled fixture positive** | 12/12 vs raw/prior 4/12 at equal cost; answer/contradiction controls pass. **Uses hashed fixture receipts, not live captures.** | `docs/research/principle_refinery_round_r.md`, `results/principle_refinery_round_r.csv`, `sparse_poly_discovery/principle_refinery_round_r.zig` |
| R4 | Luna medium | Self-expanding atom forge | Can source-derived principles autonomously add a nonredundant raw material/primitive beyond the prior atom alphabet? | **BLOCKED — prerequisite gap** | Requires a real autonomous source adapter and stronger evaluator boundary before an expansion result can support the requested claim. | `docs/research/atom_expansion_round_r.md`, `results/atom_expansion_round_r.csv`, `sparse_poly_discovery/atom_expansion_round_r.zig` |
| R5 | Terra medium | Real-world transfer expedition | Does autonomous request → discovery → refinement → expansion → forge beat baselines on independently selected non-synthetic tasks? | **BLOCKED — prerequisite gap** | Requires R4 plus live independent tasks and a strong score-private evaluator; not authorized from local/fixture foundations. | `docs/research/real_world_expedition_round_r.md`, `results/real_world_expedition_round_r.csv`, `sparse_poly_discovery/real_world_expedition_round_r.zig` |
| R6 | Terra medium | Architecture certification audit | Does source governance, evaluator isolation, principles, atoms, and transfer claim survive provenance/leakage/copy/replay/cost attacks? | **BLOCKED — prerequisite gap** | Cannot certify an architecture-complete claim before R4/R5 have a real-world evidence trail. | `docs/research/round_r_audit.md`, `results/round_r_audit.csv`, `sparse_poly_discovery/round_r_audit.zig` |

## Landing protocol

No agent prose is a result. On each completion, the coordinator rebuilds with
fresh caches, replays artifacts, checks report/CSV agreement, updates this
table and TOC/index, commits scoped work, and launches only dependencies whose
gates pass. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_14e.md`
for live status.

## Coordinator gate decision (2026-07-14)

Fresh-cache rebuilds and selftests passed for R1, R2, and R3.  They are not
failures and their reported effects are reproducible.  They also do **not**
close the requested architecture: R1 is only a same-user local protocol
boundary; R2 has no live external knowledge adapter; and R3 consequently
learns from explicitly labelled fixture receipts.  Therefore R4–R6 remain
blocked by missing architecture prerequisites, not by a negative experimental
result.  The next authorized work is to replace those two foundations with a
real read-only world adapter and an independently protected evaluator service,
then feed genuine captures through the refinery before attempting atom growth
or messy-world transfer.
