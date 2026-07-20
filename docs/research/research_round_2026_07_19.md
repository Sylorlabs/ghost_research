# Research Round 2026-07-19 (Round AQ) — open workshop and accumulated experience

**Status:** PARTIALLY LANDED — AQ1 gate-ready; AQ2/AQ3 bounded positives; AQ4 is a narrow no-answer-key process positive but still shares an executable with its evaluator. AQ5–AQ6 remain blocked on process-isolated AQ4 replay.

## Premise

Round AP establishes a bounded local evaluator/candidate process boundary for synthetic causal fixtures. It does not make the candidate an open-ended inventor: its worlds, raw actions, and tested mechanisms remain small and deliberately constructed.

Round AQ changes the capability target. The candidate must accumulate **experience**, not retained answers: inspect approved read-only raw worlds, earn instruments from failed distinctions, preserve provenance-bound claims, and use those records over many virtual steps. No human-preferred answer is revealed while the candidate operates. A virtual-time study may run far more simulated steps than wall-clock time, but every result records wall time, CPU/contact budget, deterministic seed, checkpoint intervals, and controls; speed is not treated as intelligence.

## Non-negotiable boundary

- No LLM, token prediction, embeddings, retrieved answer store, training-answer trace, target label, or evaluator progress score.
- Candidate records may contain only raw observation/action provenance, precommitted prediction, test condition, outcome relation, uncertainty/revision state, and cost.
- Approved worlds are read-only; their provenance/hash and held-out split are evaluator-owned. Candidate cannot write the source world or observe held-out score during learning.
- A result is discovery evidence only when a claim is committed before intervention, survives changed conditions/recoding, and beats simpler/attacker alternatives.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| AQ1 | Terra medium | Approved-world adapter | Can a candidate inspect an evaluator-owned read-only raw world through an opaque observation/action protocol, with provenance, held-out separation, and no answer-key exposure? | **GATE READY** | 1 normal raw trace admits; mutation, answer/score/progress, train/held-out overlap, and provenance mismatch deny. Infrastructure only. | `docs/research/approved_world_adapter_round_aq.md`, `results/approved_world_adapter_round_aq.csv`, `sparse_poly_discovery/approved_world_adapter_round_aq.zig` |
| AQ2 | Terra medium | Earned instrument forge | Can the candidate derive new bounded experiment/instrument compositions from its own failed distinctions and retain only the compositions that improve precommitted prediction under held-out change? | **FOUNDATION POSITIVE (bounded)** | Failure-authorized ordered-pair forge scores **4,080** at 2,016 contacts, above fixed pair 1,360, broad 840, random 880, replay/shuffled 320/400, answer/ablation 640. Small supplied four-action grammar. | `docs/research/earned_instrument_forge_round_aq.md`, `results/earned_instrument_forge_round_aq.csv`, `sparse_poly_discovery/earned_instrument_forge_round_aq.zig` |
| AQ3 | Terra medium | Long-horizon virtual experience ecology | Over a large deterministic virtual horizon, can provenance-bound experience improve proposal quality, intervention efficiency, and transfer without retaining answers? | **FOUNDATION POSITIVE (bounded)** | 1,000,000 virtual ticks + 100,000 held-out changed-world tests: earned experience 1,000,000 material / 100,000 correct vs blank/answer 762,430; four causal record revisions. ~44 ms first ledger. | `docs/research/virtual_experience_ecology_round_aq.md`, `results/virtual_experience_ecology_round_aq.csv`, `sparse_poly_discovery/virtual_experience_ecology_round_aq.zig` |
| AQ4 | Terra medium | No-answer-key discovery pilot | Can the isolated candidate originate a precommitted causal claim, choose a discriminating instrument, intervene, and replicate under changed conditions without matching a human answer? | **FOUNDATION POSITIVE (narrow)** | 1 opaque precommitted raw causal record admits after 12 contacts; 6 post-hoc/answer/correlation/replication/alternative controls reject. Candidate/evaluator share executable, so this is not isolation evidence. | `docs/research/no_answer_discovery_pilot_round_aq.md`, `results/no_answer_discovery_pilot_round_aq.csv`, `sparse_poly_discovery/no_answer_discovery_pilot_round_aq.zig` |
| AQ5 | Terra medium | Cross-world transfer | Do earned instruments and experience transfer to a held-out raw world with different surface encoding and causal family, over fixed broad search and answer/history controls? | blocked on process-isolated AQ4 replay | Strict held-out transfer advantage plus provenance, ablation, and simpler-alternative controls. The current AQ4 shared-executable pilot cannot support this next claim. | `docs/research/cross_world_transfer_round_aq.md`, `results/cross_world_transfer_round_aq.csv`, `sparse_poly_discovery/cross_world_transfer_round_aq.zig` |
| AQ6 | Luna medium | Discovery reduction audit | Can an independent critic reduce each apparent discovery to a fixed rule, leaked answer, retained trace, supplied instrument, post-hoc rewrite, or simpler alternative? | blocked on isolated AQ4/AQ5 | Rebuild validates only the bounded claims that survive reduction; explicitly rejects novelty/autonomy overclaim. | `docs/research/discovery_reduction_audit_round_aq.md`, `results/discovery_reduction_audit_round_aq.csv`, `sparse_poly_discovery/discovery_reduction_audit_round_aq.zig` |

## Long-horizon execution contract

AQ3 uses deterministic virtual ticks, not an attempt to run indefinitely. It must checkpoint at fixed virtual intervals, emit a compact CSV curve, enforce a wall-clock/CPU cap, and resume only from a provenance-hashed checkpoint. The coordinator records whether more virtual experience improves held-out behavior or merely overfits the fixture. "Millions of simulated steps" is a measurement scale, not a success criterion.

## Landing protocol

Workers edit only their named source, CSV, and report. Each landing fresh-builds, selftests, deterministically replays, records exact contacts/virtual ticks/wall time, distinguishes **FOUNDATION POSITIVE**, **GATE READY**, **VALID NEGATIVE**, **INCONCLUSIVE**, or **BLOCKED**, and names residual synthetic-world and local-runtime limits. The coordinator independently verifies, updates indexes, commits, and pushes.

## Landed evidence

Fresh coordinator builds and byte-identical replays pass for AQ1–AQ3. AQ1 gives a narrow evaluator-owned raw-world protocol gate. AQ2 establishes that a failed single-probe distinction can authorise an earned pair-composition test and improve held-out behavior inside a supplied four-action grammar. AQ3 establishes that a small provenance-bound causal record can revise after a hidden law change and improve held-out behavior after one million virtual ticks; its 44 ms wall time is a simulator property, not a capability claim.

AQ4 is the next qualitative step: no hidden answer is compared to a candidate result. It must instead require a claim and raw prediction before intervention, then changed-condition replication, attacker alternative, and simpler alternative. A passing record is bounded discovery-process evidence, never a proof of novelty, general intelligence, or real-world science.

## AQ4 boundary

Fresh coordinator build and byte-identical replay pass. AQ4 admits one opaque precommitted causal process record after primary, recoded, and changed-condition tests (12 contacts), while six bad-process controls reject. It does not score a human answer. However, its evaluator and candidate routines share one executable, so the no-answer protocol is not yet protected by the AP process boundary. Keep this as a narrow synthetic process positive only; the required next repair is a separate-candidate AQ4 replay before cross-world transfer or novelty claims.
