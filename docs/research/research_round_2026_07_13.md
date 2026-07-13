# Research Round 2026-07-13 (Round M) — split the blank, then prove transfer

**Status:** SETTLED — M1–M4 are controlled infrastructure/representation positives; M5's full loop survives M6 as a narrowed controlled strict positive.

**Premise:** Round L repaired the evaluator interface and produced one
equal-cost sealed discovery, but it did not transfer across two apparent blank
targets. L5 further found that scoring reused exposed labels and summarized
padding calls. Round M asks whether the system can distinguish distinct blank
territories, propose within a split territory, and prove any gain on fresh
evaluator-owned data under an enforced complete cost ledger.

## Frozen wave contract

- The evaluator owns deterministic post-freeze train/query/test splits and a
  session budget. Policies receive opaque tokens, permitted examples, aggregate
  diagnostics, and query replies only—never formulas, target IDs, family names,
  masks, parameters, audit fields, or test labels.
- Every diagnostic, candidate query, baseline call, and padding call is an
  individual ledger row. Restarting a policy cannot reset its evaluator session
  budget.
- A blank-region split uses only policy-safe trace observations. It must be
  invariant to target-token renaming and candidate ordering, and it may not
  define a region by target ID or private formula.
- A family-transfer claim needs fresh evaluator-owned test targets in one
  split region. A one-target win, reused training labels, baseline tie, or
  incomplete ledger is a valid negative—not a positive.
- M4–M6 launch only if their dependencies pass their stated gates. Every
  landing includes a Zig harness, raw CSV, report, deterministic replay, and
  central documentation update; commits occur when Git access permits.

## Verdict table

| # | Tier/role | Experiment | Question | Status | Acceptance gate | Planned artifacts |
|---|---|---|---|---|---|---|
| M1 | Terra medium | Hardened evaluator and ledger | Can an evaluator enforce opaque train/query/test splits, persistent session budget, and one row per charged call? | **DONE — EVALUATION INFRASTRUCTURE** | Persistent 12-call state survives restart; 12 individual rows plus 13th-call rejection, opaque train/fresh-test separation, schema attack rejection, and byte replay pass. Protocol-level only, not OS isolation. | `docs/research/hardened_evaluator_round_m.md`, `results/hardened_evaluator_round_m.csv`, `sparse_poly_discovery/hardened_evaluator_round_m.zig` |
| M2 | Luna medium | Blank-region splitting | Can policy-safe traces split apparent blanks into stable subregions before a family is proposed? | **DONE — CONTROLLED LIMITED POSITIVE** | Four aggregate maxima split 12/12 held-out controlled traces versus unsplit 6/12; token/order/permutation/duplicate/ID controls pass. Synthetic construction only. | `docs/research/blank_split_round_m.md`, `results/blank_split_round_m.csv`, `sparse_poly_discovery/blank_split_round_m.zig` |
| M3 | Terra medium | Fresh transfer matrix | On fresh evaluator-owned test cells, which public candidate families transfer within/between trace-split regions? | **DONE — LIMITED POSITIVE** | Pre-existing family reaches 48/48 fresh within-region tests, 24/48 cross-region and 24/48 equal-cost existing-menu control; all calls individually ledgered, train/test disjoint. | `docs/research/family_transfer_matrix_round_m.md`, `results/family_transfer_matrix_round_m.csv`, `sparse_poly_discovery/family_transfer_matrix_round_m.zig` |
| M4 | Luna medium | Trace-derived proposal grammar | Can split-region traces generate a small nonredundant candidate language without a supplied missing-family name? | **DONE — CONTROLLED LIMITED POSITIVE** | Trace-derived two-production public grammar is 48/48 fresh tests versus frozen equal-cost menu 24/48 at 29 individual calls/arm/target; token/candidate order, nonredundancy, and privacy checks pass. Synthetic bounded alphabet. | `docs/research/proposal_grammar_round_m.md`, `results/proposal_grammar_round_m.csv`, `sparse_poly_discovery/proposal_grammar_round_m.zig` |
| M5 | Terra medium | Enforced closed-loop expedition | Does map → split → propose → query → fresh test beat fixed coverage at equal enforced cost? | **DONE — CONTROLLED STRICT POSITIVE** | Six post-M4 cells: closed loop 72/72 fresh versus fixed 36/72 and blind 54/72 at exactly 29 individually ledgered calls/arm/target; restart budget and order/privacy controls pass. Bounded supplied alphabet/trace. | `docs/research/closed_loop_round_m.md`, `results/closed_loop_round_m.csv`, `sparse_poly_discovery/closed_loop_round_m.zig` |
| M6 | Terra medium | Independent audit | Do evaluator, split, transfer, proposal, and closed-loop claims survive leakage/accounting/baseline attacks? | **DONE — M5 NARROWED/CONFIRMED** | Fresh-cache replay confirms 72/72 vs 36/72/54/72 and 522 action rows (6×3×29); corrected 11-field schema and generic selftest pass. Claim remains bounded because the supplied generator aligns public trace with two fixed bit predicates and isolation is protocol-level. | `docs/research/round_m_audit.md`, `results/round_m_audit.csv`, `sparse_poly_discovery/round_m_audit.zig` |

## Landing protocol

No agent prose is a result. On every completion, the coordinator rebuilds the
harness with fresh caches, replays its deterministic ledger, checks report/CSV
agreement, updates this table, TOC, and index, and launches only a dependency
whose acceptance gate has actually passed. Run
`./scripts/research_round_status.sh docs/research/research_round_2026_07_13.md`
for live per-experiment and all-settled status.
