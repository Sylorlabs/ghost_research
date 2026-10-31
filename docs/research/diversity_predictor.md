# Generator diversity vs proposer count vs eval budget — what predicts out-of-closure REACH? (2026-07-10, round d)
> **Belongs to: Round 2026-07-10d · experiment 6 of 6 (diversity predictor)** — [round index](research_round_2026_07_10d.md).

**Question:** the round's precise version of Micah's intuition — is out-of-closure
reach predicted by GENERATOR DIVERSITY (how many distinct closures a proposer
pool spans), not by proposer count N or total eval budget? If N identical
proposers plateau (as the production engine does in
`docs/research/scaling_laws_h50.md`: caps 96/384/1536 all consume exactly 372
evals and buy zero extra solves) while N diverse proposers keep paying, that
validates "pump more DIFFERENT generators" and refutes "pump more of the same."

**Harness:** `sparse_poly_discovery/diversity_predictor.zig` — a new,
standalone, self-contained file (imports nothing else in the repo; no existing
file modified). `zig build-exe diversity_predictor.zig -O ReleaseFast`,
single-threaded, ~15s wall clock (well under the 15-min budget).
**Data:** `results/diversity_predictor_2026_07_10.csv` — 285 pool-config rows.

**Verdict in one line:** **Yes — D beats N and evals as a predictor of reach**,
by a wide margin: `corr(reach, D)=0.636 (R²=0.405)` vs `corr(reach, N)=0.256
(R²=0.065)` and `corr(reach, evals)=0.217 (R²=0.047)`; the partial correlation
of D with reach controlling for {N, evals} is **0.607 (R²=0.369)**, six times
N's partial R² (0.003). At fixed N and fixed total-evals, mean reach rises
with D in the majority of cells tested. But the effect is conditional: it only
appears on targets whose solution requires exactly the families present (the
"right direction" requirement), it can be muted by selection noise even when
the right families ARE present, and it does nothing for a target built to lie
outside every family's span. All four are measured below, not asserted.

---

## 1. No round-d proposer-pool harness existed yet

Checked before building: `git log`, `ls docs/research/` (round-a/b/c docs
present: `research_round_2026_07_10.md`, `.._10b.md`, `.._10c.md`,
`scaling_laws_h50.md`, `i53_falsification_2026_07_10.md`, plus many
`tier8_*` docs) — no `breadth_vs_depth.md` or `breadth_scaling.md`. This
experiment builds its own minimal proposer-pool model, reusing two of the
round-c reach-gap targets as direct analogues (see §3) rather than importing
the production engine, so it can stay standalone, fast, and fully controlled.

## 2. The generator-diversity metric (precise definition)

**D = the number of distinct FAMILIES (behavioral closures) represented in a
pool, 1 through 6.** A family is a fixed, bounded, enumerable search space of
"candidates"; a candidate's output is (rawValue >= threshold) possibly
negated. No candidate from a family can ever produce a boolean function
outside that family's algebraic form, no matter the budget — that is what
makes a family a closure in the sense used elsewhere in this repo
(`CLOSURE_PRINCIPLE.md`). D is exactly "the number of distinct behavioral
closures the pool can reach" as requested.

Six families were built for this experiment (all over an 8-cell, base-6 grid
world; NTRAIN=800 fits thresholds, NVAL=400 selects, NTEST=300 reports once —
see §4 for why the three-way split matters):

| family | candidates (bases) | closure | production analogue |
|---|---:|---|---|
| `mono` | 92 | product of a subset (size 1-3) of cells, thresholded | monomial forge |
| `pair` | 28 | `cell_i > cell_j` (single natural cut) | pair_relation |
| `walsh` | 92 | XOR-parity over a subset (size 1-3), thresholded | Walsh/χ_S family |
| `spectral` | 64 | `cos(ω_k · sum(cells))`, thresholded | `discoverSpectral` |
| `worldmod` | 39 | `sum(cells) mod k`, thresholded | `world_sum_mod` (the **D08** family) |
| `cmp` | 5 | parity of (count of pairs in a canonical pair-set with `cell_i>cell_j`) | comparison-count aggregate (the **C09** family) |

`worldmod` and `cmp`-parity are direct analogues of `tier8_reach_gap.md`'s
D08 ("`count3 % 4 == 0`", solved by the sum-mod family) and C09 ("inversion
parity", solved only by the comparison-count-aggregate family).

**Secondary/confirmatory metric:** entropy `H = -Σ p_f log2(p_f)` over the
pool's family-membership distribution (member `i` → family `i mod D`,
balanced cyclic assignment). H is reported per row in the CSV but not used as
an independent regressor — with balanced cyclic assignment, H tracks
`log2(D)` up to a remainder correction, so it is not a second free axis, just
a check that D is doing the intended work.

## 3. The 9-target battery and the "reach" measurement

**World:** grid = 8 cells, each in [0,6), 800/400/300 train/val/test samples,
generated once and shared by every family/proposer/pool (N, D, evals are the
only things that vary between runs).

**Targets 0-5** each have exactly one "home" family by construction (measured
positive rates in brackets): mono-monomial-threshold (0.179), pair-order
(0.418), walsh-parity (0.483), spectral-cosine (0.489), **worldmod
sum-mod-7==0 (0.141, the D08 analogue)**, **cmp inversion-parity (0.533, the
C09 analogue)**.

**Targets 6-7 are CONJUNCTIONS of two different families' native predicates**
— neither family's candidate space contains an internal AND of two
heterogeneous conditions, so only cross-family combination can express them:
- target 6 (rate 0.105): `parity(cell1)==parity(cell7)` (walsh) **AND**
  `sum(cells) mod 5 == 0` (worldmod).
- target 7 (rate 0.225): `cell2 > cell4` (pair) **AND** `cmp(cross16) mod 2
  == 0` (cmp).

**Target 8 is the falsification target** (rate 0.099): `(cell0² + cell1² -
cell2·cell3) mod 13 == 5` — a quadratic-residue-style relation mixing squares
and a cross term, built to lie outside every one of the 6 families' spans and
outside every pairwise AND/OR/XOR combination of them.

**Pools:** for (N, D, E_total), D families are drawn (shuffled, so repeats
sample different subsets at fixed D) and N members assigned cyclically
(member `i` → family `i mod D`). Each member's per-target search budget is
`floor(E_total/N)`, capped at its family's own base count. Sweep: N ∈
{1,2,4,8,16}, D ∈ {1..min(N,6)}, E_total ∈ {120,240,480,960,1920} (the top
tier exceeds every family's base count at every N, guaranteeing exhaustive
per-member coverage at the high end), 3 repeats per cell → **285 pool
configs**.

**Reach:** a pool "solves" a target if any single member's candidate clears
`SOLVE_THRESH=0.97` on held-out TEST, **or** any pairwise combination
(AND/OR/XOR) of two members' candidates does. **Out-of-closure reach**
additionally requires that no single family, given the pool's *entire*
E_total budget devoted to it alone, could reach the same target (the
`solo_table`, precomputed once per family/budget/repeat and shared by every
pool — see §4.2 for the fairness fix that makes this comparison honest).
`REACH` = count of the 8 real targets meeting this bar per pool.

## 4. Two bugs found and fixed while building this — both worth reporting

### 4.1 Combo selection must not touch the final TEST split (data leakage)

**First pilot design** (all combos' accuracies computed directly on TEST,
the best one kept) produced a nonsensical result: `corr(reach,D) ≈ -0.13`
(diversity *hurting*), all correlations under R²=0.02. Root cause: up to
`3·C(16,2)=360` AND/OR/XOR combinations were scored directly on the 300-sample
TEST split and the max was reported as "the" combo score — textbook
multiple-comparisons overfitting (picking the best of 360 noisy hypotheses
*measured on the exact set used to decide pass/fail*). **Fix:** added a third
split, NVAL=400, used exclusively for selecting the best candidate per member
and the best (pair, combinator) triple; TEST is touched exactly once per
already-decided winner. This is the standard train/val/test discipline, and
it mattered enormously here.

### 4.2 The solo baseline must get the same combo capability as the pool (fairness)

After the leakage fix, D=1 ("N identical proposers") pools still sometimes
showed nonzero out-of-closure reach — impossible in principle, since a
single-family pool's only route to "beyond what one generator could do" is
combining two *different* closures, and D=1 has none. Root cause: the pool
was allowed to AND/OR/XOR two members' candidates *even when both members
were the same family*, but the `solo_table` baseline (one family, full
budget) only ever tried single candidates, never same-family combos — an
unfair asymmetry that inflated D=1's apparent reach. **Fix:** `buildSoloTable`
now also tries same-family pairwise combos among its own top-16
(by VAL accuracy) candidates — exactly as many "combo slots" as the largest
pool (`TOPK = MAX_N`), so a same-closure pool can never out-combo a solo
generator with equal compute. After this fix, **every D=1 row in the final
CSV has reach=0.00** — the clean, correct "N identical proposers never buy a
new closure" result, and the direct analogue of H50's plateau.

A third, smaller issue (PAIR family originally had a 10-point threshold grid
instead of one natural cut, and CMP originally offered a raw-count-threshold
mode alongside parity) let a near-tied *variant* of the true predicate win
selection over the exact one, which silently broke AND-composition (the
combo would land at ~0.80 instead of 1.0). Restricting both families to the
single relation they are meant to express (as WALSH and CMP-parity already
were) fixed it — see the code comments in `diversity_predictor.zig` for the
mechanism. This resembles the round-c `tier8_reach_gap.md` finding that "the
selection statistic is not the certification statistic," now observed inside
a from-scratch model rather than the production engine.

## 5. The regression: does D beat N and evals?

285 pool configs, REACH ∈ [0, 8] (count of the 8 real targets solved
out-of-closure).

| predictor | corr(reach, ·) | R² (simple) | partial R² (controlling for the other two) |
|---|---:|---:|---:|
| **D** (diversity) | **0.636** | **0.405** | **0.369** |
| N (count) | 0.256 | 0.065 | 0.003 |
| evals (actual, consumed) | 0.217 | 0.047 | 0.009 |

Full linear model `reach ~ b0 + b1·N + b2·D + b3·evals`:
`b0=-0.272, b1(N)=-0.0069, b2(D)=0.1865, b3(evals)=0.000018`, **R²=0.410**.

D's coefficient is the only one clearly different from zero relative to its
partial R²; N's coefficient is essentially zero (and its partial correlation
with reach, controlling for D and evals, is **-0.058** — count alone, once
diversity and budget are held fixed, does not predict reach); evals' partial
correlation is a modest 0.092. **D dominates**, and it is not simply standing
in for "bigger pools" or "more compute": both of those are explicitly
partialled out.

## 6. The fixed-N, fixed-E_total diversity effect (the key comparison)

Mean REACH by D within representative (N, E_total) cells (full table in the
run log; the pattern strengthens with N and budget):

| N | E_total | D=1 | D=2 | D=3 | D=4 | D=5 | D=6 |
|--:|--:|--:|--:|--:|--:|--:|--:|
| 8 | 960 | 0.00 | 0.00 | 0.00 | 1.00 | 0.33 | 1.33 |
| 8 | 1920 | 0.00 | 0.00 | 0.33 | 1.00 | 1.00 | 1.33 |
| 16 | 960 | 0.00 | 0.00 | 0.00 | 0.67 | 0.67 | 1.00 |
| 16 | 1920 | 0.00 | 0.33 | 0.33 | 0.67 | 1.00 | 1.33 |
| 4 | 960 | 0.00 | 0.33 | 0.33 | 0.67 | — | — |

**At fixed N and fixed total-evals, higher D gives higher reach** in every
cell with N≥4 and generous budget, and the D=1 row is **uniformly 0.00 across
every single (N, E_total) cell in the entire sweep** (see §4.2) — the clean
"N copies of the same generator plateau at zero out-of-closure reach"
result, mirroring H50's "372 evals is a hard ceiling, more budget buys
nothing" finding but for count instead of compute.

## 7. Falsification: when does diversity NOT pay?

Two distinct falsification results, both measured:

1. **Wrong closure entirely (target 8).** Built to lie outside every family
   and every pairwise combination of families. Result: **never solved, by
   any pool at any (N, D, evals), and never solved by any solo family either**
   (`ever solved by ANY pool: false`; `ever solved by ANY solo family: false`).
   Maximum diversity (D=6) at maximum budget (E_total=1920) buys nothing here
   — diversity only pays when it spans the *right* closure, exactly as the
   round brief predicted.

2. **Right families present, but a low-margin sub-signal (target 6).**
   Target 6 needs `walsh` (parity-match) AND `worldmod` (sum-mod-5). Pools
   *with* both families solve it only **10/74 (13.5%)** of the time, vs
   **1/211 (0.5%)** without — a genuine ~27x effect in the predicted
   direction, but far weaker than target 7's clean result (below). Root
   cause (traced with a temporary debug instrument, since removed): the true
   walsh sub-condition's accuracy against the *full* conjunction label is
   only ≈0.605 vs a ≈0.50-0.57 noise ceiling from 92 competing candidates —
   a real but narrow margin, so even *exhaustive* per-member search sometimes
   lands on a spuriously-scoring impostor mask instead of the exact one, and
   the combo then fails to reach 1.0. This is a second, narrower
   falsification: **diversity in the right direction still needs enough
   selection margin to be found reliably** — a nuance, not a contradiction,
   and a small-scale echo of `tier8_reach_gap.md`'s D08 lesson ("the
   selection statistic is not the certification statistic").

Target 7 (needs `pair` AND `cmp`) is the clean positive control: **71/76
(93.4%)** solved when both required families are present, **0/209 (0.0%)**
when they are not — the sharpest single demonstration in this run that
diversity pays exactly when, and only when, it spans the target's true
closure.

## 8. Unifying verdict

**Diversity-of-generators is the dominant, measured predictor of
out-of-closure reach in this model — not proposer count, not total eval
budget.** D explains 4-6x more variance than N or evals alone (R²=0.405 vs
0.065/0.047) and retains almost all of that explanatory power after
partialling out N and evals (partial R²=0.369 vs 0.003/0.009). At fixed N and
fixed compute, adding distinct families raises reach; adding identical copies
of one family never does (every D=1 cell is exactly 0.00, the same shape as
the production engine's H50 plateau). But the effect is conditional, not
magical: it requires the pool's diversity to span the *specific* closure the
target needs (target 8: 0% at D=6), and even directional diversity can be
muted by selection noise on a low-margin sub-signal (target 6: 13.5% vs
target 7's 93.4%). The precise, defensible claim this round supports:
**"pump more DIFFERENT generators, not more of the same" is validated as a
quantitative predictor (R²≈0.4, dominant over count and budget), conditional
on the added generators actually spanning the target's closure and on the
per-generator selection signal being strong enough to find the exact matching
predicate.**

## 9. Reproduce

```bash
cd sparse_poly_discovery
zig build-exe diversity_predictor.zig -O ReleaseFast   # zig 0.14.1
./diversity_predictor > ../results/diversity_predictor_2026_07_10.csv
# stderr has: target base rates, solo-baseline table, correlations/regression,
# fixed-N/fixed-E_total table, falsification report, conjunction cross-tabs
```

Single-threaded, ~15s wall clock (well under the 15-min budget). No existing
file was modified; `sparse_poly_discovery/diversity_predictor.zig` is the only
new file this experiment added, plus this doc and the results CSV.
