# Research Round 2026-07-19 (Round AQ) — open workshop and accumulated experience

**Status:** LIVE — AQ1/AQ2/AQ3 launched in parallel. AQ4–AQ6 are gated on their evidence.

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
| AQ1 | Terra medium | Approved-world adapter | Can a candidate inspect an evaluator-owned read-only raw world through an opaque observation/action protocol, with provenance, held-out separation, and no answer-key exposure? | running | Runtime adapter admits normal observations/actions, denies world mutation/answer/progress channels, and records read-only provenance plus held-out separation. | `docs/research/approved_world_adapter_round_aq.md`, `results/approved_world_adapter_round_aq.csv`, `sparse_poly_discovery/approved_world_adapter_round_aq.zig` |
| AQ2 | Terra medium | Earned instrument forge | Can the candidate derive new bounded experiment/instrument compositions from its own failed distinctions and retain only the compositions that improve precommitted prediction under held-out change? | running | Earned compositions beat fixed raw probes and random composition at equal cost; ablation removes benefit; no supplied instrument menu, target, or score during learning. | `docs/research/earned_instrument_forge_round_aq.md`, `results/earned_instrument_forge_round_aq.csv`, `sparse_poly_discovery/earned_instrument_forge_round_aq.zig` |
| AQ3 | Terra medium | Long-horizon virtual experience ecology | Over a large deterministic virtual horizon, can provenance-bound experience improve proposal quality, intervention efficiency, and transfer without retaining answers? | running | Checkpoint curve improves over blank/replay/answer-scrub/fixed/random controls on held-out changed worlds; reports virtual steps, actual wall/CPU cost, and deterministic replay. | `docs/research/virtual_experience_ecology_round_aq.md`, `results/virtual_experience_ecology_round_aq.csv`, `sparse_poly_discovery/virtual_experience_ecology_round_aq.zig` |
| AQ4 | Terra medium | No-answer-key discovery pilot | Can the isolated candidate originate a precommitted causal claim, choose a discriminating instrument, intervene, and replicate under changed conditions without matching a human answer? | blocked on AQ1/AQ2/AQ3 | Claim/prediction precede result; intervention/replication/alternative gates pass; no answer-match field exists. | `docs/research/no_answer_discovery_pilot_round_aq.md`, `results/no_answer_discovery_pilot_round_aq.csv`, `sparse_poly_discovery/no_answer_discovery_pilot_round_aq.zig` |
| AQ5 | Terra medium | Cross-world transfer | Do earned instruments and experience transfer to a held-out raw world with different surface encoding and causal family, over fixed broad search and answer/history controls? | blocked on AQ1/AQ2/AQ4 | Strict held-out transfer advantage plus provenance, ablation, and simpler-alternative controls. | `docs/research/cross_world_transfer_round_aq.md`, `results/cross_world_transfer_round_aq.csv`, `sparse_poly_discovery/cross_world_transfer_round_aq.zig` |
| AQ6 | Luna medium | Discovery reduction audit | Can an independent critic reduce each apparent discovery to a fixed rule, leaked answer, retained trace, supplied instrument, post-hoc rewrite, or simpler alternative? | blocked on AQ1/AQ2/AQ3/AQ4/AQ5 | Rebuild validates only the bounded claims that survive reduction; explicitly rejects novelty/autonomy overclaim. | `docs/research/discovery_reduction_audit_round_aq.md`, `results/discovery_reduction_audit_round_aq.csv`, `sparse_poly_discovery/discovery_reduction_audit_round_aq.zig` |

## Long-horizon execution contract

AQ3 uses deterministic virtual ticks, not an attempt to run indefinitely. It must checkpoint at fixed virtual intervals, emit a compact CSV curve, enforce a wall-clock/CPU cap, and resume only from a provenance-hashed checkpoint. The coordinator records whether more virtual experience improves held-out behavior or merely overfits the fixture. "Millions of simulated steps" is a measurement scale, not a success criterion.

## Landing protocol

Workers edit only their named source, CSV, and report. Each landing fresh-builds, selftests, deterministically replays, records exact contacts/virtual ticks/wall time, distinguishes **FOUNDATION POSITIVE**, **GATE READY**, **VALID NEGATIVE**, **INCONCLUSIVE**, or **BLOCKED**, and names residual synthetic-world and local-runtime limits. The coordinator independently verifies, updates indexes, commits, and pushes.

