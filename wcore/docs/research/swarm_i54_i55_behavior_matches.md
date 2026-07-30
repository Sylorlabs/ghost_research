# I54/I55: `behaviorMatches` stress-test — false positives, false negatives, budget sensitivity

**Status:** built, measured — adversarial near-miss pairs + sample-budget sweep on
historical deep solvers. Reproduce:

```bash
cd wcore && zig build -Doptimize=ReleaseFast
./zig-out/bin/wcore-invent matchstress <seed>
```

New in `src/inv_coevo.zig`: `behaviorAgreement`, `reducibleWithBudget`.
New phase `matchstress` in `src/inv_main.zig` (extends prior `auditscan` work in
`instrument_audit.md`).

## What we were testing

Prior negative results ("it can't invent", 0 survivors at DMAX=8) all rest on
`behaviorMatches` with `MATCH_THRESHOLD = 0.95` over 12×32 = **384** random symbols.
Two ways the instrument could lie:

1. **False positive (I55):** declare two *non-equal* behaviours equal because a
   near-miss scores ≥95% on a small sample.
2. **False negative (I54):** miss a true composition because 384 symbols are too few,
   flagging a reducible solver as irreducible — a phantom "new atom."

We also asked whether **reducible/irreducible verdicts flip** as sample count rises
32 → 256 → 4096 on every historical deep solver from the budget-scan seeds.

## A. Adversarial near-miss pairs (4096 symbols)

| Pair class | Pairs tested | Max wrong-pair agreement | False positives (loose=Y, exact=N) |
|------------|-------------|--------------------------|-------------------------------------|
| refSolver × single wrong stage | 16 | **0.512** (g_xor vs wrong stage) | **0** |
| refSolver × depth-2 wrong genome | 96 | **0.640** | **0** |
| distinct-count × any single stage | 5 | (all < 0.95) | **0** |

True-positive controls (refSolver vs own stage): **4/4** at agree=1.000, loose=Y,
exact=Y.

The nearest adversarial near-miss (depth-2 wrong genome) peaks at **64.0%** — a full
**31 points below** the 0.95 bar. No pair crosses the threshold on 4096 symbols while
failing exact equality.

## B. False-negative hunt (exact-equal pairs, shrinking budget)

Reference solvers (g_xor, g_add, pk_xor, pk_add) vs their single-stage genome:

| Total symbols | False negatives |
|---------------|-----------------|
| 32 (1×32) | 0 |
| 256 (8×32) | 0 |
| 4096 (64×64) | 0 |

Exact-equal programs are never missed, even at the smallest budget.

## C. Verdict sweep 32→256→4096 on historical deep solvers

Seeds from budget-scan history: `0xD00D`, `0xBEEF`, `0x1111`, `0xFACE` (+ duplicate
`0xD00D` as CLI seed).

| Seed | Deep solvers | Verdict flips (32 vs 256 vs 4096) |
|------|-------------|-------------------------------------|
| 0xD00D | 9 | 0 |
| 0xBEEF | 8 | 0 |
| 0x1111 | 7 | 0 |
| 0xFACE | 5 | 0 |
| **TOTAL** | **38** (incl. duplicate seed) | **0** |

Every deep solver stays **reducible** at all three budgets (consistent with
`budget_scan.md`: 0 survivors at DMAX=8). No solver flips from REDUCIBLE→IRREDUCIBLE
or the reverse as samples grow 128×.

Default production budget (12×32 = 384) sits between 32 and 256; the sweep brackets
it and finds no sensitivity.

## D. Masked hunt (I54: loose-reducible but exact-irreducible)

Replicates `auditscan` on seed `0xD00D`:

```
masked count: 0
```

No solver is a 95%-approximation of a composition that fails 100% exact matching.
If a "survivor" ever appears, `behaviorMatches` loose threshold is **not** the
explanation — it would have to be a genuine irreducibility (or insufficient DMAX).

## Corroboration with prior instrument audit

`instrument_audit.md` (exact vs loose, 4096 samples, 3 seeds): **0 masked / 24
solvers**. This experiment generalizes that result:

- Adds adversarial wrong-pair agreement curves (shows headroom below 0.95)
- Adds false-negative checks at minimal budget
- Adds explicit 32/256/4096 verdict sweep (addresses RESEARCH Q47 directly)

Results are consistent across all checks.

## Answers

| Question | Answer |
|----------|--------|
| **Any verdict flips?** | **No.** 0/38 deep solvers flip across 32→256→4096. |
| **Test-count sensitivity?** | **None observed.** Reducibility stable over 128× sample range; nearest near-miss peaks at 64% ≪ 95%. |
| **False positives?** | **0** on 117 adversarial pairs (single-stage + depth-2 + distinct-count). |
| **False negatives?** | **0** on 4 reference solvers at budgets as low as 32 symbols. |
| **I54: phantom irreducible from instrument?** | **No.** 0 masked; no evidence `behaviorMatches` invents fake atoms. |
| **Instrument trust** | **PASS** |

## Verdict

`behaviorMatches` at `MATCH_THRESHOLD=0.95` is **trustworthy on this fixed-opcode
substrate.** The 0.95 bar has ample margin above the worst adversarial near-miss (64%),
and verdicts do not depend on sample count over the tested range. "It can't invent" is
not a measurement artifact from loose matching or thin sampling — it is real, and this
stress-test makes that conclusion **more robust**, not weaker.

The honest reflex (distrust the instrument before trusting the negative result) was
the right move; it found no leak.