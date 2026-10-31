# Research Round 2026-07-11b (Round F) — the generator-of-generators

**Status:** **COMPLETE — 6/6 experiments landed.**
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
| F1 | Learned structural priors (headline) | Can the machine INFER which structural prior a target needs from its failure signature (E2-router, one level up), instead of being handed it? | **INCONCLUSIVE** | **Instrument failure; no learned-prior result.** The proxy battery fails its validity gates: own-prior recall 14/20, no-prior recall 12/20, non-binary/degenerate targets, complement collisions, and train/test descriptor distance 0.000. Router/fixed/random tie 3/4 and the router predicts `rmw` for every test. F6's 85–90% remains projected only; a valid battery must be rebuilt before this headline can be answered. | `wcore/docs/research/prior_selector.md` |
| F2 | Auto-family discovery for ORDER2 | Can E3's smart-gen + a comparison prior auto-discover the FAMILY that unlocks E1's standing unreachable target ORDER2? | **DONE** | **Yes — auto-discovered, not handed the answer.** An exhaustive 50,490-candidate search over subset-conditioned comparison families converged at all 4 seeds (including a held-out seed) on `between({cell 0}) mod 2`, exactly ORDER2, at val=tst=1.000. A real ladder gains ORDER2 (0.582→1.000) with 0 regressions across Battery B + controls; the remaining human input is the comparison-shape prior. | `docs/research/autofamily_order2.md` |
| F3 | RUN1 certifier-boundary audit | Is the novelty gate's rejection of the exact `run(maxRunGE3)` member correct (real redundancy) or a false rejection the program is missing? | **DONE** | **The gate is OVER-REJECTING — a real bug.** run(maxRunGE3) is genuinely NOT reconstructible (0.887 acc / R²=0.80 ceiling vs the run family's instant 1.000); the gate's single-column linear-R² statistic is non-monotonic in true reconstructibility (AUC 0.889), false-rejection **33%** among novel targets — an *axis* problem no threshold fixes. Corrected measure proposed (multi-feature COVER reconstruction, mirrors gate-v5). | `docs/research/run1_gate_audit.md` |
| F4 | Prior transfer / compounding | Once a mechanism+prior is discovered, do OTHER family targets become auto-discoverable without re-supplying the prior? Does it amortize? | **DONE** | **Transfer is real but layered.** The promoted mechanism solves 5/10 downstream targets by 0–4 ms composition and cuts total target-evaluation time 157.7→66.4 s (57.9%); new siblings still require generation. The structural prior transfers more broadly: 9/10 solved versus 2/10 cold. One depth/representation target misses in every arm. | `wcore/docs/research/prior_transfer.md` |
| F5 | Assembled generator-of-generators | Do prior-guided smart-gen + representability growth + learned aim cohere in one autonomous pass, vs the hand-guided stack at equal budget? | **DONE** | **Coheres, but not fully hand-equivalent.** Autonomous reaches 58/73 vs hand 59/73; removing smart generation collapses to 36–37/73, while removing the router preserves 58/73 but costs 48.3% more evaluations (router saves 32.2%). Frontier reach rises 3/10→8/10. RUN1 reproduces F3's gate bug, and blind controls also solve WALL_HARD, so this is an integration/ablation win rather than a full autonomy ceiling win. | `docs/research/genofgen_assembled.md` |
| F6 | Residual human-insight bit | Put a NUMBER on how much insight is machine-supplied vs human-supplied per method (D5→E3→F1), and whether it's shrinking. | **DONE** | **Machine-supplied insight 0% → 66.7% across the arc** (hand-curriculum 0%, E3 smart-gen 66.7%, cross-check 70.7%; F1 projected ~85–90%, unmeasured). Trend: 100%→33% human-supplied (~3× drop), shrinking not vanishing (D5 anchor: skip the insight bit = 0/9). Irreducible floor: alphabet, certifier, target, protocol. COVER-fair vs -uniform (same bits eliminated, only one solves) → the prior's value is *aim*, not quantity. | `docs/research/insight_ledger.md` |

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

## Round verdict

**Round F advances machine-driven representability, but does not complete the
generator-of-generators.** The strongest positive is concrete: F2 lets search
invent the missing ORDER2 family and promotes an exact solve with no measured
regressions. F4 shows that a promoted mechanism compounds cheaply through
composition and that its structural prior transfers across siblings. F5 shows
the pieces cohere: smart generation supplies reach and learned routing supplies
efficiency, leaving the autonomous stack only one target behind the hand oracle.

The ceiling claim remains open for three reasons. First, F1's headline learned-
prior selector is invalidated by its own substrate and leakage guards, so prior
inference is still unmeasured. Second, F5 does not reach full hand equivalence
and its blind control also crosses the chosen wall. Third, F3 proves the current
novelty gate rejects genuinely new capabilities, so the integrated loop is still
running behind a known-bad instrument. F6's measured statement therefore stays
at **66.7% machine-supplied insight**; its 85–90% successor estimate is a
projection, not a Round F result.

The next round should be narrower: freeze F3's corrected multi-feature gate,
rebuild F1 on binary non-degenerate production-derived targets with leakage-
clean labels, then rerun F5 with that selector. Until those gates pass, the
honest label is **a compounding, partially autonomous representability engine —
not yet a generator-of-generators.**
