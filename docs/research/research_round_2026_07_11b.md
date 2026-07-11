# Research Round 2026-07-11b (Round F) — the generator-of-generators

**Status:** LIVE — updated as each experiment lands. 0/6 complete.
**Premise (the five-round arc, closed in Round E):** machine invention is gated
by **representability** and steered by **aim** (`research_round_2026_07_11.md`,
law: reach ≈ representable ? aim-decides : 0). Round E proved both levers are
real and mapped: aim automates (E2 router), representability grows by hand (E1),
and — the crux — the machine *can* auto-discover a missing mechanism (E3) but
only with a structural prior *smaller than* a hand curriculum. The arc named
exactly one next lever: **machine-driven representability expansion via learned
structural priors** — a generator-of-generators. Round F builds and tests it.

Constraints unchanged: new files only, standalone `zig build-exe`, ≤2 threads /
≤15 min runs, independent verification per claim, negatives are findings,
equal-budget comparisons, leakage guards, main session commits centrally, doc +
commit + TOC + "Belongs to" banner per landing.

---

## Verdict table

| # | Experiment | Question | Status | Headline | Doc |
|---|-----------|----------|--------|----------|-----|
| F1 | Learned structural priors (headline) | Can the machine INFER which structural prior a target needs from its failure signature (E2-router, one level up), instead of being handed it? | pending | — | `wcore/docs/research/prior_selector.md` |
| F2 | Auto-family discovery for ORDER2 | Can E3's smart-gen + a comparison prior auto-discover the FAMILY that unlocks E1's standing unreachable target ORDER2? | pending | — | `docs/research/autofamily_order2.md` |
| F3 | RUN1 certifier-boundary audit | Is the novelty gate's rejection of the exact `run(maxRunGE3)` member correct (real redundancy) or a false rejection the program is missing? | pending | — | `docs/research/run1_gate_audit.md` |
| F4 | Prior transfer / compounding | Once a mechanism+prior is discovered, do OTHER family targets become auto-discoverable without re-supplying the prior? Does it amortize? | pending | — | `wcore/docs/research/prior_transfer.md` |
| F5 | Assembled generator-of-generators | Do prior-guided smart-gen + representability growth + learned aim cohere in one autonomous pass, vs the hand-guided stack at equal budget? | pending | — | `docs/research/genofgen_assembled.md` |
| F6 | Residual human-insight bit | Put a NUMBER on how much insight is machine-supplied vs human-supplied per method (D5→E3→F1), and whether it's shrinking. | pending | — | `docs/research/insight_ledger.md` |

---

## The shape of the round

- **F1** is the headline: the generator-of-generators core — inferring the prior,
  not just the lens (E2) or the mechanism-given-a-prior (E3).
- **F2** points it at a *concrete* standing target: ORDER2, the cleanest thing E1
  proved unreachable. A positive = the machine invented a representability-
  expanding family for a real target it couldn't reach before.
- **F3** audits the new boundary type E1 found — is the novelty gate itself
  costing the program genuine capabilities? (the instrument-trust discipline,
  applied to the novelty certifier.)
- **F4** asks whether auto-discovery *amortizes* — the difference between a
  per-target trick and a compounding capability.
- **F5** is the coherence test: the whole autonomous loop in one pass.
- **F6** is the honest accounting: the shrinking (or not) human-insight residual,
  tied directly to the "greatest invention machine" question.

*(Verdicts and synthesis added as agents land.)*
