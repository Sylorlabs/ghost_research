# Research Round 2026-07-10b — aiming the escapes

**Status:** LIVE — updated as each experiment lands. 0/6 complete.
**Predecessor:** `research_round_2026_07_10.md` (8/8 complete). Its converged
finding: *the loop's binding resource is aimed out-of-closure generators — not
compute, not more promotion rounds, not stricter gates.* Escapes are cheap when
aimed (A10: one algebra change, 0.508→0.976), worthless when unaimed (A1–A6:
ten rounds bought one behaviour), compute past closure exhaustion is
unspendable (H50: 372-eval hard ceiling), and framework revision is the proven
escape-admission mechanism (Tier 8 ablation, 3/3 seeds) whose gate is currently
vacuous post-revision.

**This round builds and tests the aiming mechanism**, re-audits the one
foundation with a known depth-artifact risk, and sharpens both external
campaigns' weak spots. Same constraints as round 1: new files only, standalone
`zig build-exe`, ≤2 threads / ≤15 min runs, independent verification per claim,
negatives documented as findings, main session commits centrally.

---

## Verdict table

| # | Experiment | Question | Status | Headline | Doc |
|---|-----------|----------|--------|----------|-----|
| 1 | Aimed forge (wcore) | Does residual pressure toward a named frontier beat pure novelty at equal budget? Baseline: unaimed = 3/18→4/18, structured family never flips. | pending | — | `wcore/docs/research/aimed_forge.md` |
| 2 | Aimed proposer (battery-C wall) | Do near-miss witnesses + residual-guided feature proposal move the 10/11 battery-C wall? Baselines: 0/33 frozen, 3/33 revision. | pending | — | `docs/research/tier8_aimed_proposer.md` |
| 3 | Gate v5 discrimination | Is there a gate that admits certified escapes (C08 must still pass) AND blocks planted remix (v4 passes 100%)? | pending | — | `docs/research/tier8_gate_v5.md` |
| 4 | Claim-C depth attack (wcore) | Do wcore's "irreducible" verdicts survive +1/+2/+3 certifier depth, or are they resource artifacts (the I53 attack, applied to wcore)? | pending | — | `wcore/docs/research/claimc_depth_attack.md` |
| 5 | LABS even-N | Can memetic / pair-flip / structural moves close the 12 even-N + {61,63,64} gaps skew-symmetry can't touch? | pending | — | `boundary_crossing/docs/research/labs_even_n.md` |
| 6 | Decisive battery-D | Build ~10 targets in the ladder-reachable-but-v3-blockable band; turn the 1-target Tier 8 existence proof into an effect size. | pending | — | `docs/research/tier8_battery_d.md` |

---

## Design notes

- Experiments 1–3 are the round's spine: the aiming mechanism at three layers
  (forge fitness, feature proposal, promotion gate). Experiment 6 supplies the
  instrument (a battery that can measure aimed escapes at all). Experiment 4 is
  defensive: the open-atom program rests on the Claim-C certifier, which
  carries exactly the resource-bound risk I53 exposed. Experiment 5 chases the
  itemized record gap from round 1.
- Held-out contamination guard (exp 1): aiming targets (F) and transfer-eval
  targets (E) are disjoint by design; aiming at a target removes it from any
  generalisation claim.
- The `greedyFit` stack fix (commit 67fdd13) means round-2 harnesses need no
  giant-stack workarounds.

*(Verdicts and synthesis added as agents land.)*
