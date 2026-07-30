# Research Round 2026-07-15 (Round S) — the real-world architecture closure

**Status:** LIVE — S1/S2/S3 launched; S4–S6 are dependency-gated.

**Purpose:** Round R proved limited local foundations and explicitly did *not*
complete the requested architecture. Round S closes that gap without replacing
it with a hidden human source list, an answer key, or an unprotected evaluator.
The system receives an invention request and general safety authority; it must
manage its own permitted read-only knowledge world, retain causal experience
rather than answers, and earn any new material/tool on fresh sealed work.

## Non-negotiable contract

- No human-curated per-task source/material/tool list. Source selection must be
  generated from the request and generic policy, with every discovery decision
  and rejected candidate recorded.
- Public read-only acquisition only. Never access credentials, private systems,
  user data, evaluator state, hidden manifests, fresh per-target scores, or
  source permissions the system lacks.
- Each capture records origin, retrieval time, content hash, license/policy
  state, relevance, reputation, contradictions, quarantine/retirement reason,
  and extraction lineage. Source text and provenance must not join to hidden
  answers.
- Principles are falsifiable records: condition, mechanism, prediction,
  failure signature, candidate measurement/material, evidence, contradiction
  status, and total cost. They are not retained target answers.
- Evaluator state is held by an independently protected service and releases
  only authorized aggregate closure. A same-user file-permission boundary is
  insufficient.
- A final positive requires a fresh hidden multi-kind transfer win against
  fixed/raw/blind baselines at equal *total* acquisition, reasoning, forge, and
  test cost, then an independent audit.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Artifacts |
|---|---|---|---|---|---|---|
| S1 | Terra medium | Autonomous live knowledge adapter | Can the system discover, rank, retrieve, hash, govern, and retire genuine public sources under generic policy, with no per-task human source list? | **LIVE** | Live acquisition succeeds from request-derived candidates; provenance/quarantine/replay/answer-boundary attacks pass; no fixture substitution. | `docs/research/live_knowledge_adapter_round_s.md`, `results/live_knowledge_adapter_round_s.csv`, `sparse_poly_discovery/live_knowledge_adapter_round_s.zig` |
| S2 | Terra medium | Strong evaluator isolation | Can policy code be prevented at the OS/process boundary from reading, joining, resetting, or inferring evaluator-private state? | **LIVE** | Separate identity/container or equivalent enforceable boundary; adversarial filesystem/process/RPC/reset tests fail closed; aggregate-only replay passes. | `docs/research/strong_evaluator_isolation_round_s.md`, `results/strong_evaluator_isolation_round_s.csv`, `sparse_poly_discovery/strong_evaluator_isolation_round_s.zig` |
| S3 | Luna medium | Genuine-capture principle loop | Can answer-free structured principles learn from S1 real captures and make better held-out choices than raw capture retrieval/prior? | **LIVE** | Consumes only validated S1-style live captures; no fixture fallback; independent equal-cost calibration win and answer-leak scan pass. | `docs/research/genuine_principle_loop_round_s.md`, `results/genuine_principle_loop_round_s.csv`, `sparse_poly_discovery/genuine_principle_loop_round_s.zig` |
| S4 | Luna medium | Autonomous atom/material expansion | Can real-source principles add a nonredundant primitive/material beyond the raw alphabet and retain it through fresh transfer? | blocked on S1/S2/S3 | Provenance-backed new material beats its ingredients on fresh sealed transfer; no answer leakage. | `docs/research/real_atom_expansion_round_s.md`, `results/real_atom_expansion_round_s.csv`, `sparse_poly_discovery/real_atom_expansion_round_s.zig` |
| S5 | Terra medium | Messy-world transfer expedition | Does request → source discovery → principle → material → forge win on independently selected non-synthetic tasks? | blocked on S1/S2/S3/S4 | Multi-kind fresh equal-total-cost win versus raw/fixed/blind; score-private closure. | `docs/research/messy_world_transfer_round_s.md`, `results/messy_world_transfer_round_s.csv`, `sparse_poly_discovery/messy_world_transfer_round_s.zig` |
| S6 | Terra medium | Architecture closure audit | Does the whole real-world architecture survive provenance, isolation, answer-leak, copy, replay, and cost attacks? | blocked on S1/S2/S3/S4/S5 | Independent claim-by-claim reconstruction and pass. No architecture-complete claim without it. | `docs/research/round_s_architecture_audit.md`, `results/round_s_architecture_audit.csv`, `sparse_poly_discovery/round_s_architecture_audit.zig` |

## Landing protocol

On each landing the coordinator rebuilds from fresh caches, replays the result,
checks report/CSV agreement, updates this master table plus `RESEARCH_TOC.md`
and `INDEX.md`, commits scoped artifacts, and releases only dependencies whose
gates actually pass. A blocked dependency is recorded as **BLOCKED**, never
relabeled as a negative result or a completed architecture.
