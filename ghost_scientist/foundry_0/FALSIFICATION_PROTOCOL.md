# Foundry v6 pre-registration draft

**Status:** Foundry-0 protocol specification; no v6 result exists  
**Decision authority:** evaluator-owned, frozen before held-out selection

## 1. Research claim

The trial tests whether a persistent library of machine-induced, verified,
typed tensor tools has positive causal and total-cost value on a prospective
real-compiler workload stream.

The trial does not test primitive invention or escape from a fixed substrate.

## 2. Experimental arms

Every arm receives the same calibration artifacts, typed substrate, compiler
version, machine allocation, and total research budget unless the arm's
definition explicitly forbids retained state.

| ID | Arm | Retained state | Discovery budget |
|---|---|---|---:|
| A0 | Stock compiler | compiler-native | zero |
| A1 | v5.1 frozen conditional constructor | frozen v5.1 state | zero new discovery |
| A2 | Foundry candidate | induced typed tools and selector | full |
| A3 | No-library rediscovery | none across artifacts | A2 total |
| A4 | Replay | calibration receipts only | zero new discovery |
| A5 | Typed Stitch-style MDL | induced macro library | A2 total |
| A6 | Babble/ISAMORE-style | e-graph anti-unified reusable tools | A2 total |
| A7 | Ruler/Enumo-style | induced rewrite rules, fixed schedule | A2 total |
| A8 | EggMind-style | induced reusable EqSat strategy | A2 total |
| A9 | Compute-matched per-instance | none across artifacts | A2 offline plus online |
| A10 | Exhaustive bounded oracle | none | micro-corpus only |

External-method adaptations must carry an `ADAPTED` label and conformance
receipt. Failure to implement A5, A6, A7, A8, or A9 makes the main trial
invalid.

## 3. Units and chronology

1. Freeze upstream revisions, compiler environment, extraction procedure,
   typed substrate, metrics, all arms, budgets, gates, containment, and
   verifier.
2. Seal calibration-derived candidate state and every learned control state.
3. Obtain a post-freeze seed through the committed seed procedure.
4. Select held-out source graphs and shapes using only the frozen extractor
   and seed.
5. Seal every arm's output for an artifact before mounting that artifact's
   runtime outcomes.
6. Execute repetitions in randomized blocked order with fresh compiler caches
   where specified.
7. Emit raw process, compiler, numerical, provenance, tool-use, and
   intervention ledgers.
8. Run evaluator verdict.
9. Run a stdlib-only independent recomputation that imports no candidate or
   evaluator implementation.

Any outcome-driven code, threshold, corpus, or seed change after step 1 starts
a new version and preserves the prior result.

## 4. Tool schema

Each promoted tool must include:

- canonical tool digest;
- typed parameters and results;
- dtype, shape, layout, alias, and storage conditions;
- complete low-level compile-time construction program;
- complete low-level runtime program;
- proof or differential-validation obligations;
- discovery and verification resource receipts;
- calibration origin set;
- native-compiler deduplication result; and
- all held-out call receipts.

A name, strategy ID, source-text macro without type obligations, or evaluator
callback is not a tool.

## 5. Resource accounting

The ledger charges:

- successful and rejected proposals;
- equivalence and numerical verification;
- compilation, including failed compilations;
- selector inference;
- e-graph or search construction;
- child-process CPU and wall time;
- peak resident memory;
- executed runtime repetitions;
- timeouts and crashes at their full limits; and
- model requests, tokens, price, and latency in optional model arms.

The primary time account uses process CPU time plus measured compiler and
execution time on the frozen host. Wall time and peak memory remain separate
reported axes. The freeze declares how overlapping child CPU is aggregated.

No discovery or verification work is treated as a sunk external cost.

## 6. Behavioral reuse tests

For each held-out selection:

1. The receipt names the exact pre-freeze tool digest.
2. The evaluator expands the tool and independently checks the complete typed
   program.
3. The candidate is rerun with that tool removed and no retraining.
4. The evaluator records whether another tool replaces it, search cost rises,
   solution quality falls, or the solution becomes unreachable within budget.
5. The evaluator checks whether the same digest was used outside its
   calibration-origin family.

Aggregate gains without these receipts do not count as tool reuse.

## 7. Primary endpoint

At the externally justified stream horizon `N*`:

`Delta(N*) = 1 - TotalCost_A2(N*) / min(TotalCost_A3..A9(N*))`

The primary endpoint passes only when:

- the point estimate is at least 5%;
- the lower 95% paired bootstrap confidence bound is greater than zero;
- every hard validity gate passes; and
- A2 is correct on every artifact included in the paired analysis.

If no independent trace supports `N*`, the trial reports a break-even curve
and the primary endpoint automatically fails.

## 8. Hard validity gates

| ID | Gate |
|---|---|
| V01 | Freeze record authenticates every executable, state artifact, threshold, budget, source revision, and extraction rule. |
| V02 | Held-out source identities and shapes are selected after freeze by the committed seed procedure. |
| V03 | Candidate-visible inputs contain no family, control, provenance, outcome, or gate leakage. |
| V04 | Every arm is sealed before its artifact outcomes become visible. |
| V05 | Every selected output passes type, shape, dtype, layout, alias, storage, eager, and compiled numerical checks. |
| V06 | Maximum absolute error is at most `1e-5`; tighter source contracts remain tighter. |
| V07 | Every claimed tool is a complete evaluator-independent typed construction. |
| V08 | All accepted tools pass native-compiler deduplication or disclose a measured search-cost distinction. |
| V09 | Resource ledgers include all successful, failed, rejected, and timed-out work. |
| V10 | A5, A6, A7, and A8 pass frozen external-method conformance fixtures, and A9 passes budget equivalence. |
| V11 | Default-deny containment and hostile probes pass. |
| V12 | Independent recomputation matches every gate and aggregate from raw ledgers. |

A failed validity gate produces `FOUNDRY_V6_INVALID`, never a scientific
negative.

## 9. Scientific PASS gates

| ID | Gate |
|---|---|
| R01 | At least four non-equivalent tools survive verification and native deduplication. |
| R02 | At least three surviving tools receive direct held-out reuse receipts. |
| R03 | At least two exact tool digests transfer across evaluator-audited workload families. |
| R04 | The corpus contains at least four non-transformer families; attention is at most 20%. |
| R05 | Tool-removal intervention causes at least two lost within-budget solutions or at least a 10% paired total-cost increase with positive lower 95% confidence bound. |
| R06 | A2 passes the primary endpoint against the strongest A3–A9 control. |
| R07 | A2 beats stock compiler total cost at `N*`. |
| R08 | A2 has no more than 3% quality regret against A10 on the bounded oracle micro-corpus. |
| R09 | No selected tool is used only on exact calibration-shape replay. |
| R10 | At least one useful tool was not predeclared as a high-level template or family-specific strategy. |
| R11 | The complete trial has zero compiler, verifier, containment, or evaluator failures. |
| R12 | The result remains PASS under leave-one-family-out aggregation. |

All R gates must pass. Thresholds may be strengthened before freeze but never
weakened after any held-out outcome.

## 10. Required negative controls

- Mutate a tool body without changing its digest field: reject.
- Mutate type, layout, or alias preconditions: reject.
- Substitute a strategy label for a tool: reject.
- Hide one failed discovery receipt: ledger mismatch and reject.
- Duplicate a compiler-native primitive under a new name: deduplication
  reject.
- Expose a held-out family label: leakage reject.
- Reuse an exact calibration artifact: prospective audit reject.
- Give A9 less total compute than A2: budget audit reject.
- Recompute `N*` from outcomes: chronology reject.

## 11. Verdicts

- `FOUNDRY_V6_PASS`: all V and R gates pass.
- `FOUNDRY_V6_FAIL`: all V gates pass and at least one R gate fails.
- `FOUNDRY_V6_INVALID`: any V gate fails.
- `FOUNDRY_V6_NOT_RUN`: freeze or prospective execution never completed.

FAIL is preserved evidence. It may calibrate a future version but can never be
reclassified.

## 12. Claim after PASS

The only default claim is the bounded claim in
`FOUNDRY_0_DOSSIER.md`. Any stronger claim requires a separate protocol.
