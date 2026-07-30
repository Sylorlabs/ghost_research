# Representability expansion — growing the family menu under the sound certifier, and measuring the closure it unlocks
> **Belongs to: Round 2026-07-11 · experiment E1 of 6 (representability expansion)** — [round index](research_round_2026_07_11.md).

**Harness:** `sparse_poly_discovery/repr_expansion.zig` (new file; no existing
file modified). Transcribes the pre-tax ladder replica from
`tier8_reach_gap.zig` (round c) with **CMP + MENUACC already wired in as the
earned baseline**, and appends four new primitive families as toggleable
stages. `equivalence_tax.zig` / `unified_invention.zig` deliberately not
imported (tax dependency); numeric glue duplicated per the established
convention. Imports (none touch the tax): `open_invention_rq1.zig` (zoo train
+ battery B), `open_invention_e2.zig` (battery C labels), `tier8_battery_d.zig`
(battery D), `operator_menu_lib.zig` (Walsh discoverer).
**Date:** 2026-07-11 (round E). **Zig 0.14.1**, `zig build-exe -O ReleaseFast`,
single-threaded, CPU-only.
**Seeds:** the 3 standard — `0xF0235A11CE0FF1CE`, `0xC1B10D20260706`,
`0xC2B10D20260707`.
**Wall clock:** Phase A + A2 in one binary ~10.4 min (Phase A closure lattice
33 s; A2 ladder attribution the bulk); Phase B regression a separate
`--phaseb` invocation 3.9 min. Each run under the 15-min bound.

**Verdict (one line):** Growing the substrate's family menu is a **real,
measurable closure lever, but a narrow one**. Of four earned-by-certification
candidate families, **two unlock a previously-unrepresentable target each**
(mixed-radix `mixr` → MIXMOD1; count-algebra `ratio` → RATIO1), **one unlocks
nothing** (threshold-count `thresh`), and **one exposes a *certifier* boundary
rather than a family boundary** (`run` contains the exact 1.000 member for RUN1
but the R²<0.40 novelty gate rejects it as too reconstructible from the
existing basis). `mixr` additionally re-derives C09 independently of the earned
`cmp` (a genuine family overlap). The **standing unrepresentable core after all
four families** is the GF(2)-XOR wall (C01/C03/C11, Bayes ceilings ≈ 0.50) plus
one fresh **order-statistic variant (ORDER2)** that no family in the menu —
old, earned, or new — reaches (best any family 0.64, existing-basis ceiling
0.646). **Zero regressions** on the full B+D battery and the two solvable C
cells across the BASE→ALL comparison. This is the Closure-Principle escape done
systematically: each family a generator, none admitted without earning it, and
the closure boundary's shape now mapped one family at a time.

---

## 1. The candidate-family menu (each defined precisely)

Beyond the existing ladder families (monomial / pair / walsh / spectral-count /
clifford / world-mod) and the round-c **earned** `cmp` (comparison-pair
aggregates) + `menuacc` (accuracy-scored spectral selection), four new families
were assembled, each a *generator* over a grid statistic the existing menu does
not expose, closed under a shared **standard lens set**
{ident, mod2..mod6, cos(ω··) frequency scan}:

| Family | Statistic(s) | Why it is outside the existing menu |
|--------|--------------|--------------------------------------|
| **thresh** | `count(g[i] ≥ k)` for k ∈ {1,2,4,5} | Existing count/spectral only ever use the fixed k=3 threshold. |
| **mixr** | joint mixed-radix index `(A mod a)·b + (B mod b)` over stat-pairs {(sum,count3),(sum,inv),(count3,inv)}, radii {2×2, 3×3} | `world_sum_mod` / `spectral` condition on **one** statistic mod k; this is a **joint two-statistic** residue — modular arithmetic beyond mod-k. |
| **ratio** | products `hi·lo` and normalized differences `(hi−lo)/(hi+lo+1)` of two threshold counts, pairs {(≥4,≥1),(≥5,≥0),(≥3,≥2)} | **Algebraic** (nonlinear products/ratios of counts) — no existing family multiplies two aggregates. |
| **run** | `maxRunGE(k)` (longest consecutive index-run of cells ≥ k, k∈{2,3,4}), `firstDescentPos`, `numLocalMax` | **Stateful/sequential** over the cell **adjacency order** — every existing family is pointwise/aggregate/pairwise; none reads run structure along the index. |

## 2. Target list and the BEFORE proof (Bayes ceilings)

Eight targets: four D2/C09-class reused (C01, C03, C11 = XOR wall; C09 =
inversion parity), and four **fresh** targets each designed to sit outside
every existing family and every new family except the one it names:

- **ORDER2** = parity of rank(cell 0) among the other 7 — an order statistic
  that is *neither* the full inversion count (which `cmp(all28)` covers) *nor*
  any of `cmp`'s five fixed pair-sets.
- **RUN1** = "longest run of consecutive cells ≥ 3 is ≥ 3" — a run statistic.
- **RATIO1** = "product `count(≥4)·count(≥1)` ≡ 0 (mod 3)" — count-algebra.
- **MIXMOD1** = "sum(g) mod 3 == count3 mod 3" — a joint two-residue equality.

**Information-basis Bayes ceiling** (per-bin majority vote, train→test — an
upper bound on **every** function of that statistic, hence on every present or
future member of any family defined over it), mean of 3 seeds, over the
**existing** bases:

| target | count3 | gridSum | signPat | v1−v0 | inversion | max_cell | sum01 | **MAX existing** |
|--------|-------:|--------:|--------:|------:|----------:|---------:|------:|-----:|
| C01 XOR 0x0F | .501 | .487 | .512 | .497 | .514 | .499 | .516 | **.516** |
| C03 XOR 0x55 | .514 | .512 | .514 | .510 | .502 | .507 | .510 | **.514** |
| C11 XOR 0x37 | .503 | .503 | .501 | .496 | .499 | .499 | .499 | **.503** |
| C09 inv parity | .506 | .501 | .503 | .495 | **1.000** | .508 | .501 | 1.000 |
| ORDER2 rank0 parity | .600 | .577 | .646 | .597 | .587 | .579 | .580 | **.646** |
| RUN1 run≥3 of ≥3 | .814 | .773 | **1.000** | .578 | .600 | .578 | .628 | 1.000 |
| RATIO1 prod%3==0 | .570 | .582 | .528 | .515 | .517 | .532 | .511 | **.582** |
| MIXMOD1 sum3==count3(mod3) | .672 | .682 | .629 | .672 | .670 | .672 | .672 | **.682** |

**Reading the BEFORE proof.** C01/C03/C11 are at chance on **every** existing
basis (≤ .516) → provably unrepresentable (the GF(2)-XOR wall, re-confirmed).
ORDER2 tops out at .646, RATIO1 at .582, MIXMOD1 at .682 — all far below the
COVER = 0.90 certify bar on every existing basis → unrepresentable before. Two
ceilings equal 1.000 and matter: **C09**'s `inversion` basis is 1.000 (already
covered by the earned `cmp`), and **RUN1**'s `signPattern` basis is 1.000
because `maxRunGE3` is a deterministic function of the sign bits — but no
*member* of the existing families over signPattern (Walsh is GF(2)-linear;
`sign_mod` is residue-only) captures run length, so the family gap is real
even where the basis ceiling is not (see §4 RUN1).

## 3. The closure-expansion lattice (AFTER — per family, certified 3/3 seeds)

Each family's best member swept at generous budget, then put through the
**standard pre-tax certifier** (escape COVER 0.90 from below **and** R² < 0.40
vs the fresh trained library). `X` = certified at all 3 seeds; `·` = never.

| target | mono | pair | walsh | spec | clif | wsum | wsign | **cmp**(earned) | **thresh** | **mixr** | **ratio** | **run** |
|--------|:----:|:----:|:-----:|:----:|:----:|:----:|:-----:|:----:|:----:|:----:|:----:|:----:|
| C01 XOR 0x0F | · | · | · | · | · | · | · | · | · | · | · | · |
| C03 XOR 0x55 | · | · | · | · | · | · | · | · | · | · | · | · |
| C11 XOR 0x37 | · | · | · | · | · | · | · | · | · | · | · | · |
| ORDER2 rank0 parity | · | · | · | · | · | · | · | · | · | · | · | · |
| RUN1 run≥3 of ≥3 | · | · | · | · | · | · | · | · | · | · | · | ·¹ |
| **C09 inv parity** | · | · | · | · | · | · | · | **X** | · | **X** | · | · |
| **RATIO1 prod%3==0** | · | · | · | · | · | · | · | · | · | · | **X** | · |
| **MIXMOD1 sum3==count3** | · | · | · | · | · | · | · | · | · | **X** | · | · |

¹ RUN1: the `run` family contains the **exact** member `run(maxRunGE3, ident)`
with val = 1.000, cov_after = 1.000 at all 3 seeds — but **certify = no**
because R² = 0.51–0.53 > 0.40. Representable, not certifiable. See §4.

**Exact certified members (all 3 seeds, byte-consistent):**

| target | family | member | val | cov_after | R² |
|--------|--------|--------|----:|----------:|---:|
| C09 | cmp (earned) | `cmp(all28, mod2)` | 1.000 | 1.000 | −0.04…−0.07 |
| C09 | **mixr** (new) | `mixr(sum,inv, 2×2, mod2)` | 1.000 | 1.000 | −0.04…−0.07 |
| MIXMOD1 | **mixr** (new) | `mixr(sum,count3, 3×3, mod4)` | 1.000 | 1.000 | −0.04…−0.11 |
| RATIO1 | **ratio** (new) | `ratio(prod, ≥4·≥1, mod3)` | 1.000 | 1.000 | −0.01…−0.09 |

### Per-family targets-unlocked (the closure-expansion curve)

| family added | genuinely-new targets certified | also re-derives | net new closure |
|--------------|--------------------------------|-----------------|-----------------|
| **thresh** | none | — | **0** |
| **mixr** | **MIXMOD1** | C09 (overlaps earned `cmp`) | **+1** |
| **ratio** | **RATIO1** | — | **+1** |
| **run** | none *(RUN1 representable but R²-blocked)* | — | **0** certified |
| **cumulative (all 4)** | **MIXMOD1, RATIO1** | C09 (twice-covered) | **+2 of 4 fresh targets** |

**Overlap:** C09 is now reachable by **two** families — the earned `cmp(all28,
mod2)` and the new `mixr(sum,inv, 2×2, mod2)` — because inversion parity is
expressible both as the mod-2 lens of the all-pairs comparison aggregate and as
the mod-2 lens of a (sum, inversion) mixed-radix index. Genuine redundancy in
the enlarged menu, not double-counting: each is an independently certified
generator.

## 4. RUN1 — a certifier boundary, not a family boundary (the honest nuance)

RUN1 is the round's most instructive negative. Its exact solver
`run(maxRunGE3)` exists **inside the run family** and gives 1.000 coverage, yet
it is never certified — at all 3 seeds the recon-R² of the run feature against
the trained library is 0.51–0.53, over the R² < 0.40 novelty gate. Longest-run-
of-3 is ~52% linearly reconstructible from the existing count/monomial basis,
so the certifier judges it **insufficiently novel** and refuses to admit it,
even though it is the exact answer. Consequences, all measured:

- Under the real `solveLadder` (Phase A2), the ALL arm leaves RUN1 at
  cov ≈ 0.79 (the run stage finds the 1.000 member, the certifier rejects it,
  the library is left unchanged). BASE and ALL are identical on RUN1.
- Approximate members from *existing* families climb high but never clear
  COVER: spectral 0.82, ratio(prod) 0.80, thresh(k=4) 0.72 — RUN1 is
  "correlationally near" but exactly reachable only by the run generator.

RUN1 therefore occupies a **third category** distinct from the two the arc
knew: not "in-closure needle" and not "family-level impossible," but
**representable-yet-certifier-blocked**. It documents that the closure boundary
under a *sound* certifier is `representability ∧ novelty`, and the novelty
predicate can veto a true generator that correlates with the incumbent basis.
(Whether to relax the R² gate for exact-coverage members is a certifier-design
question flagged for E-series follow-up, not changed here.)

## 5. Regression check (adding families must not break existing solves)

Pre-tax ladder, production seed, **BASE** (earned menuacc+cmp) vs **ALL**
(+thresh+mixr+ratio+run appended after cmp, before world):

| arm | Battery B | Battery C | Battery D |
|-----|-----------|-----------|-----------|
| BASE (earned) | 11/11 | 2/11 (C08, C09) | 11/11 |
| **ALL (+4 new)** | **11/11** | **2/11** (C08, C09) | **11/11** |

- **Regressions: 0.** No target solved by BASE is unsolved by ALL.
- **New battery flips: 0.** The four new families unlock nothing on B/C/D —
  expected: those batteries are already covered by monomial/walsh/menu/cmp/
  world, and their unsolved remainder is the GF(2)-XOR wall (battery C
  C01–C07, C10, C11), which no order/count/run family touches.
- **Battery-C budget note (honest scope):** the 9 XOR-wall C targets are
  BASE-unsolved **and** ALL-unsolved (chance ≈ 0.50, proven family-level by §2
  and by `tier8_reach_gap`/`breadth_scaling`), so they cannot participate in a
  regression (which requires a BASE solve). Running each through the full
  ladder (monomial forge + 200-freq cmp scan + 4 new stages + 12 world
  certifies) twice costs ≈ 4 min and unlocks nothing, so they are recorded
  unsolved without the redundant run; C08 and C09 (the only BASE-solvable C
  cells) are run in full. This is why "C 2/11" rather than a full-battery-C
  sweep — it is a scope decision under the 15-min bound, not a hidden failure.

## 6. The standing unrepresentable core (after the whole menu)

After the earned `cmp`/`menuacc` **and** all four new families, the targets no
family in the menu certifies (3/3 seeds):

| standing target | why it stands | best any family (val) | max existing-basis ceiling |
|-----------------|---------------|----------------------:|---------------------------:|
| **C01 / C03 / C11** (GF(2) XOR) | pure parity of a cell subset; family-level impossible — every basis at chance | ≈ 0.53–0.57 | ≈ 0.50–0.52 |
| **ORDER2** (rank-of-cell-0 parity) | an order statistic that is neither the full inversion count nor any of cmp's 5 fixed pair-sets; no family exposes "rank of one distinguished cell" | 0.64 (ratio) | 0.646 (signPattern) |
| **RUN1** (run≥3 of ≥3) | *representable* by the run family (exact 1.000 member) but **R²-blocked** by the novelty certifier — a certifier boundary, catalogued separately | 1.000 (run, uncertified) | 1.000 (signPattern basis; no existing member) |

**Two shapes of "unrepresentable."** C01/C03/C11 and ORDER2 are genuine
**family-level** gaps (no generator in the menu, old or new, spans them — the
Bayes ceilings prove it for the XOR trio and bound ORDER2 at 0.646). RUN1 is a
**certifier-level** gap (the generator exists and is exact; the soundness-
preserving novelty gate declines it). ORDER2 is the cleanest open frontier: it
directly motivates E3 (auto-*family* discovery) — the machine would have to
propose the "rank of a distinguished cell" pair-set, which is one enumerable
generalization of cmp's fixed menu that this hand-built menu did not include.

## 7. What this says about the lever (Closure Principle)

- **Representability is a real, dial-able lever, and each turn is cheap and
  certified.** Two hand-designed generators (`mixr`, `ratio`) each converted a
  provably-unrepresentable target (existing-basis ceiling ≤ .68) into an
  exactly-certified solve (1.000, strongly-negative R²) at a few-hundred-eval
  cost — the same closure-escape signature as round-c's cmp fix and round-1's
  322-eval out-of-closure point.
- **But the menu is not a free lunch.** `thresh` (a natural generalization —
  vary the count threshold) unlocked **nothing**: k≠3 counts are strongly
  correlated with the k=3 basis and buy no new closure at the certify bar. A
  family that unlocks nothing is a valid finding — it shows the closure
  boundary is not moved by "more of the same statistic," only by genuinely new
  ones (joint residues, count products, sequence structure).
- **The boundary has two textures.** Adding families moves the *family-level*
  boundary (mixr/ratio) but reveals a *certifier-level* boundary underneath
  (RUN1). Escaping the standing core needs either (a) a generator for the
  order-statistic-variant class (ORDER2 → E3), or (b) a novelty predicate that
  admits exact-coverage members the incumbent basis merely correlates with
  (RUN1 → certifier redesign). Neither is bought by budget on any existing axis.

## 8. Honest scope / limitations

1. **Uniform-iid grid, 8 cells, values 0..5** — as every Tier-8 measurement.
   The ceilings and solves are grid-distribution-specific.
2. **Pre-tax.** The equivalence tax gate is not consulted (mid-edit by another
   agent; and none of the fresh solves produce a tax-relevant remix collision
   under the count/inversion bank). When the tax lands, mixr/ratio become new
   engine-expressible families for its remix basis — flagged, not measured.
3. **Phase A2 reduced to BASE+ALL (2 arms)** for the 15-min bound; per-family
   attribution is delivered rigorously by Phase A's isolated certify sweep (all
   3 seeds), and A2 confirms the aggregate BASE→ALL lift under the real
   `solveLadder` (MIXMOD1→mixr, RATIO1→ratio, RUN1 stays unsolved, ORDER2 stays
   unsolved — all 3 seeds).
4. **New-family ladder-stage cos-scan trimmed to 16 freqs** (from 60) for
   budget; verified harmless — **every** certified new-family solve uses a
   **mod** lens (mixr mod2/mod4, ratio mod3), never a cos lens, across all 3
   seeds, so the trim changes no solve. Phase A diagnosis keeps the full grid.
5. **9 XOR-wall battery-C cells excluded from the timed regression** (§5) —
   proven unsolved in both arms, cannot regress; a scope decision, stated.
6. **Fresh targets are a design choice.** ORDER2/RUN1/RATIO1/MIXMOD1 were
   built to probe specific family gaps; they are witnesses, not a task
   distribution. ORDER2 standing-open is the load-bearing negative.

## Files

- Harness: `sparse_poly_discovery/repr_expansion.zig` (Phase A closure lattice
  + Bayes ceilings, Phase A2 ladder attribution, Phase B regression; `--diag`
  = Phase A only, `--phaseb` = Phase B only appended to the CSV).
- Data: `results/repr_expansion_2026_07_11.csv` (595 rows: 24 base_rate + 168
  basis_ceiling [7 bases × 8 targets × 3 seeds] + 288 family_diag [12 families ×
  8 targets × 3 seeds] + 48 ladder_attr [8 targets × 2 arms × 3 seeds] + 66
  ladder [Phase B] + 1 regression_summary).
- Reproduce (from `sparse_poly_discovery/`, zig 0.14.1):
  ```
  zig build-exe repr_expansion.zig -O ReleaseFast
  ./repr_expansion            # Phase A + A2 (~10 min), truncates CSV
  ./repr_expansion --phaseb   # Phase B regression (~4 min), appends to CSV
  ./repr_expansion --diag     # Phase A closure lattice only (~33 s)
  ```
- Read-only references (not imported): `unified_invention.zig` (ladder source),
  `tier8_reach_gap.zig` (round-c cmp/menuacc earned baseline, transcribed).
- Related docs: `docs/research/tier8_reach_gap.md` (round c: C09/D08 closed,
  Bayes-ceiling method reused here), `docs/research/breadth_scaling.md` (D2:
  the 4/15-representable finding this experiment attacks),
  `docs/research/research_round_2026_07_11_PLAN.md` (E1 lever = representability).
