# Research Round 2026-07-12b (Round I) — search response to general prior admission

**Status:** **SETTLED — five executed experiments landed; I6 was validly blocked. I5 invalidated I1 as a downstream input.**

**Premise:** Round H produced a constrained direct proposer: it can reliably
aim inside a human-supplied singleton-directed grammar and certify promotions
live, but richer static descriptors fail to route priors and the singleton
admission misses a representable two-cell partition. Round I tests whether
small, predeclared **search responses**—rather than static target probes—can
form a broad enough failure representation to admit and allocate grammar search
for both singleton and multi-cell directed structure.

## Frozen wave contract

- Every artifact is new and scoped: standalone Zig harness, raw CSV, report,
  fixed seeds/budgets, validity-gate table, reproduction commands, and central
  landing commit.
- Search-response descriptors may contain only outcomes of predeclared,
  target-agnostic micro-searches. Target name/formula/family/anchor/mask/residue
  and audit labels are forbidden inference inputs.
- Every guided arm must match fixed/random arms in candidate-evaluation budget;
  candidate generation, scoring, and routing cost are recorded separately.
- Multi-cell and singleton variants, negative no-grammar controls, and held-out
  structural variants are required. A failed leakage, split, or fairness gate
  makes the result inconclusive.
- The coordinator waits on native agent-completion events, verifies raw/report
  agreement, commits each scoped landing, updates this table + TOC + index, and
  runs `./scripts/research_round_status.sh docs/research/research_round_2026_07_12b.md`.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| I1 | Luna medium | Search-response descriptor atlas | Do fixed, low-budget micro-search outcomes distinguish threshold, singleton-directed, multi-cell-directed, and no-grammar targets without leakage? | **INVALIDATED BY I5** | I5 finds the claimed 1,524-candidate uniform partition probe duplicates 254 members of the actual 1,270 grammar. The 2/4 diagnostic is retained, but this is not a valid frozen descriptor source or leakage-clean atlas. | `docs/research/search_response_atlas_round_i.md`, `results/search_response_atlas_round_i.csv`, `sparse_poly_discovery/search_response_atlas_round_i.zig` |
| I2 | Terra medium | Symmetric multi-cell admission | Can a predeclared partition-response rule admit singleton and two-cell directed targets while rejecting irrelevant grammars? | **DONE — NARROW COVERAGE** | I5 independently confirms singleton/two-/three-/fresh four-cell coverage and negative rejection, but operationally it is a 2,540-call train+validation grammar scan—near-solve coverage, not lightweight admission, routing, or efficiency. | `docs/research/multicell_admission_round_i.md`, `results/multicell_admission_round_i.csv`, `sparse_poly_discovery/multicell_admission_round_i.zig` |
| I3 | Luna medium | Response-guided grammar allocator | Can I1's frozen response vector allocate fixed budget across grammars better than fixed/random on holdout? | **DONE — VALID NEGATIVE** | Response allocation is 9/15 held-out, exactly fixed allocation's 9/15 (random mean 6/15; directed-only coverage 3/15). It fails the predeclared strict-improvement bar despite equal 420-call budgets and clean isolation. | `docs/research/response_allocator_round_i.md`, `results/response_allocator_round_i.csv`, `sparse_poly_discovery/response_allocator_round_i.zig` |
| I4 | Luna medium | Equal-budget scaling curve | Does guidance retain an efficiency/reliability advantage as grammar size and budget grow? | **DONE — NEGATIVE FOR EARLY EFFICIENCY** | Target-blind scan gains deterministic coverage only once it reaches target members (full 1,270 sweep for singleton; 635/1,270 for multi-cell); blind random is already competitive, while fixed threshold solves only its own control. Any allocator must beat this target-blind coverage baseline. | `docs/research/grammar_scaling_round_i.md`, `results/grammar_scaling_round_i.csv`, `sparse_poly_discovery/grammar_scaling_round_i.zig` |
| I5 | Terra medium | Adversarial leakage/fairness audit | Can the I1–I3 claim survive unseen partitions, unrelated targets, answer-shaped-probe checks, and budget audit? | **DONE — MIXED AUDIT** | I1's uniform probe claim is refuted by a duplicate-candidate defect; I2's narrow coverage survives a fresh four-cell replay but is a 2,540-call near-solve; I3's equal-budget valid negative is independently confirmed. | `docs/research/search_response_audit_round_i.md`, `results/search_response_audit_round_i.csv`, `sparse_poly_discovery/search_response_audit_round_i.zig` |
| I6 | Luna medium + Terra review | Conditional autonomous assembly | Do accepted admission/allocator components plus live v6 remove per-target human prior choice end-to-end? | **BLOCKED BY VALID NEGATIVE** | I3 does not beat fixed allocation, so assembling it cannot support autonomous general prior choice. I6 will not be run as a known-non-improving stack. | — |

## Landing protocol

An agent landing is not a result until the coordinator reproduces its fast gate,
checks the raw CSV against the report, commits only its scoped artifacts, and
updates the verdict table and `RESEARCH_TOC.md`. `ROUND_SETTLED` signals no
live workers; `ROUND_COMPLETE` signals no unresolved dependency. The round only
claims autonomous general prior admission if I6 passes its held-out,
equal-budget, live-certification gates.

## Round verdict

**Round I does not produce autonomous general prior admission.** I2 repairs
the singleton defect in representational coverage: a symmetric full grammar
scan recovers singleton through four-cell partitions and rejects unrelated
controls. But I5 establishes that this is a 2,540-call train+validation
near-solve, not a lightweight learned admission feature. I4 independently
shows blind random is competitive once the finite grammar is supplied.

The intended bridge from search response to allocation fails twice: I1's
purported uniform probe bank is invalidated by a duplicate-candidate defect,
and I3 remains a valid negative even under its own equal-budget protocol
(guided 9/15 = fixed 9/15). I6 is therefore correctly not run. The next
experiment must first construct and audit a **correctly enumerated**, cheap
trajectory/near-miss representation before it can test allocation again.
