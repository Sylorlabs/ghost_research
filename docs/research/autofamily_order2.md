# Auto-family discovery for ORDER2 — can the machine invent the representability-expanding family itself?
> **Belongs to: Round 2026-07-11b · experiment F2 of 6 (auto-family discovery for ORDER2)** — [round index](research_round_2026_07_11b.md).

**Harness:** `sparse_poly_discovery/autofamily_order2.zig` (new file; no
existing file modified). Transcribes the pre-tax numerics, ladder stages, and
comparison-pair family from `sparse_poly_discovery/repr_expansion.zig` (E1,
round E) verbatim-style (the established convention in this arc: duplicate
numeric glue, reuse read-only, do not import across experiment files beyond
the zoo/battery modules). Reuses E3's *method* (`wcore/src/smart_gen.zig`) —
exhaustive, behaviour-deduped coverage over a small alphabet, steered by a
structural prior — applied to a genuinely different domain (Tier-8 polynomial
discovery, not alien-ISA program synthesis).
**Date:** 2026-07-11 (round F). **Zig 0.14.1**, `zig build-exe -O ReleaseFast`,
single-threaded, CPU-only.
**Seeds:** the 3 standard (`0xF0235A11CE0FF1CE`, `0xC1B10D20260706`,
`0xC2B10D20260707`) for Phase 0/2, plus a genuinely held-out 4th seed
(`0x0FAD5EED20260711`, grepped clean against every prior round doc before
being picked) used only as Phase 1's retro-audit.
**Wall clock:** Phase 0 (`--phase0`) 0.37 s. Phase 1 (`--phase1`, 4 seeds)
30.9 s. Phase 2 (`--phase2`, production seed, Battery B + 4 extra targets,
2 arms) ~9.2 min — the ALL arm's dcmp stage (16,800 candidate probes ×
certify, run on every target that stays unsolved through cmp) is the long
pole; still under the 15-minute bound. All three phases in one process (no
args) total ~9.7 min.

**Verdict (one line):** **Yes — auto-discovered, not handed the answer.** An
exhaustive search over a systematic generalization of CMP's fixed pair-set
menu — "subset of cells S, relation-to-S mode (within/between/touching)"
instead of 5 hand-picked sets — swept 50,490 (mask, mode, lens) candidates per
seed with **no knowledge that "cell 0" or "singleton" mattered**, and
independently converged on the exact same answer at all 4 seeds (3 measurement
+ 1 genuinely held-out): **mask = {cell 0} (singleton), mode = between, lens =
mod2** — i.e. "parity of the count of cells less than cell 0" — which is
*exactly* ORDER2's definition, at val = tst = 1.000, certified (COVER escape,
R² < 0.40) at every seed. This is the "distinguished-cell pair-set" E1
predicted was the missing generator, rediscovered from a 765-pair-set,
50,490-candidate structural search rather than supplied.

---

## 1. The frontier, and the family CMP was missing

E1 (`docs/research/repr_expansion.md`) proved ORDER2 = "parity of rank(cell 0)
among the other 7 cells" unrepresentable by every family in the menu,
including round-c's earned CMP (comparison-pair aggregates over 5 fixed,
untuned pair-sets: `all28`, `low6`, `high6`, `cross16`, `adj7`). E1's own
closing diagnosis: *"the machine would have to propose the 'rank of a
distinguished cell' pair-set, which is one enumerable generalization of cmp's
fixed menu that this hand-built menu did not include."* F2 tests whether that
proposal can be found by search rather than by hand.

**The generalization.** CMP's 5 sets are each a special case of a two-
parameter generator over subsets of the 8 cells: `within(S)` = pairs with
both endpoints in S, `between(S)` = pairs with exactly one endpoint in S,
`touching(S)` = pairs with at least one endpoint in S. `all28 = within(full)`,
`low6 = within({0,1,2,3})`, `high6 = within({4,5,6,7})`, `cross16 =
between({0,1,2,3})`. **None of CMP's 5 sets is a singleton** — no `S = {k}`
for any single cell `k`. `between({0})` (equivalently `touching({0})`, since
`within({0})` is empty) is exactly the star of comparisons touching cell 0:
`#{j != 0 : g[0] > g[j]}` = rank(cell 0). This is the missing family: **DCMP**
— the same count-then-lens shape as CMP, with the pair-set itself, `(mask,
mode)` over 255 nonempty subsets × 3 modes = 765 candidates, turned into a
search variable instead of a fixed choice of 5.

## 2. Phase 0 — the before-proof (reproducing E1's ceiling and CMP's miss)

7 information-basis Bayes ceilings (identical bases/method to E1) plus the
EARNED cmp family's best member over its 5 fixed pair-sets, on ORDER2, all 3
standard seeds:

| seed | max existing-basis ceiling | best basis | EARNED cmp best member | cmp val | cmp tst |
|------|----:|------|------|----:|----:|
| 0xF0235A11CE0FF1CE | 0.638 | signPattern | cmp(all28, cos w=0.204) | 0.603 | 0.586 |
| 0xC1B10D20260706 | 0.654 | signPattern | cmp(all28, cos w=0.990) | 0.612 | 0.569 |
| 0xC2B10D20260707 | **0.646** | signPattern | cmp(cross16, cos w=2.702) | 0.601 | 0.603 |

The production seed's ceiling (0.646) exactly matches E1's reported number.
Every basis ceiling and the earned CMP's best member sit 0.25–0.30 below
COVER = 0.90 — ORDER2 is confirmed unrepresentable by anything in the pre-F2
menu, **before** the search runs. Consistent with E1's structural argument:
none of CMP's 5 fixed sets is a singleton hub, so no lens over any of them
reaches the rank-of-cell-0 statistic.

## 3. Phase 1 — the auto-discovery search

**The prior.** Not "try pair-set X" — the prior is the *shape*: compare pairs
of cells, select which comparisons via a subset-of-cells + relation-mode
generator, aggregate by count, then apply a lens (ident/mod2../mod6/60-point
cos scan). This is a direct transcription of E3's finding that the working
prior is *exhaustive coverage over a small alphabet*, not a hand-supplied
mechanism: here the "small alphabet" is the 8-cell subset lattice (255
non-degenerate subsets × 3 modes = 765 pair-sets, a naturally bounded space —
no coverage-explosion mitigation was needed, unlike E3's program space; see
§6). The search never sees "cell 0" or "singleton" as special; masks 0x01
through 0xFF are swept identically.

**Result — all 4 seeds, including the held-out one:**

| seed | swept | winner | val | tst | SGD cross-check | certify (cov_before→after, R²) |
|------|------:|--------|----:|----:|------|------|
| 0xF0235A11CE0FF1CE | 50,490 | dcmp(mask=0x01,pop=1,between,mod2) | 1.000 | 1.000 | 1.000 (agrees) | 0.582→1.000, R²=−0.020 |
| 0xC1B10D20260706 | 50,490 | dcmp(mask=0x01,pop=1,between,mod2) | 1.000 | 1.000 | 1.000 (agrees) | 0.593→1.000, R²=0.036 |
| 0xC2B10D20260707 | 50,490 | dcmp(mask=0x01,pop=1,between,mod2) | 1.000 | 1.000 | 1.000 (agrees) | 0.586→1.000, R²=0.034 |
| **0x0FAD5EED20260711 (HOLDOUT)** | 50,490 | dcmp(mask=0x01,pop=1,between,mod2) | 1.000 | 1.000 | 1.000 (agrees) | 0.563→1.000, R²=−0.035 |

`mask=0x01` = bit 0 set = the singleton `{cell 0}`. `between({0})` on that
singleton is exactly the 7 comparisons `(0,j)` for `j=1..7`, and
`applyLens(count, mod2)` is exactly `rank(cell 0) mod 2` — ORDER2's own
definition, arrived at by the search, not supplied to it.

**Top-10 landscape (identical shape at every seed):** all 10 top slots are
`mask=0x01` under `between`/`touching` (equivalent for a singleton, since
`within({0})` is empty) crossed with `mod2` and 5 cos-frequencies near
`ω≈π` (`cos(π·r)` also separates parity exactly, since `r` is an integer 0–7)
— i.e. the landscape has a single genuine structural winner (the singleton-0
hub) surrounded by numerically-equivalent lens restatements of the same
feature, not a plateau of unrelated near-misses. Every one of the other 254
masks and 2 other modes never appears in any top-10 at any seed.

**Genuineness checks (all pass):**
1. **Independent held-out seed.** The winner was rediscovered from scratch at
   a 4th seed never used to tune the search, the lens set, or the mask range
   — ruling out a 3-seed coincidence.
2. **Selection/certification agreement.** The exhaustive-sweep statistic
   (`bestThresholdAcc`, exact threshold) and the production statistic
   (`valAccSingle`, SGD logit — what the real ladder's certifier actually
   uses) agree exactly (both 1.000) at every seed. This is the D08/MENUACC
   lesson in reverse: E1's tier8_reach_gap found a case where selection and
   certification statistics *disagreed* (the ladder's power-argmax missed the
   accuracy-argmax winner); here they agree, so the discovered family would
   actually get promoted by a real ladder run (confirmed directly in Phase 2).
3. **Certification.** COVER escape (cov_before 0.56–0.59 → cov_after 1.000)
   and R² novelty gate at every seed: −0.035, −0.020, 0.034, 0.036 — all
   comfortably under R2_MAX = 0.40 (two mildly positive, unlike E1's usual
   strongly-negative R²s, but still a clean pass; noted honestly, not
   rounded away).
4. **Not handed the answer.** The search space (765 pair-sets, none flagged
   as "the" answer) treats all 8 possible hub cells and all subsets
   symmetrically; the winner (`{0}`) emerges purely from its val/tst score
   against ORDER2's labels, exactly the same evaluation every other candidate
   receives.

## 4. Adapting "retro-audit at depth 4" to this domain

The round prompt's step 3 language ("retro-audit at depth 4") originates in
the wcore program-synthesis lineage (`matcher_attack.zig`, `inv_wall.zig`,
`auto_curriculum.zig` — a depth-4 prefix-reduction gate over program
composition). This experiment is in the Tier-8 **polynomial**-discovery
domain (`sparse_poly_discovery/`), which has no program-depth notion — there
is nothing to take a "prefix" of. The honest domain-equivalent audit
performed here, stated explicitly rather than silently reinterpreted: **(a)**
the held-out 4th-seed rediscovery bar (§3.1) — the analogue of checking the
discovery is not an artifact of a specific measurement point — and **(b)**
the R² novelty gate (§3.3) — confirming the winning feature is not a
reconstruction of the existing (zoo-trained) library, i.e. genuinely a new
generator and not a disguised composition of already-known features. Both
pass at every seed. No claim of "depth-4" in the wcore sense is made.

## 5. Phase 2 — regression check (does a real ladder run solve it, and does anything break?)

Pre-tax ladder, production seed (`0xF0235A11CE0FF1CE`), **BASE** (earned
menuacc+cmp) vs **ALL** (+ the new `dcmp` stage, placed after cmp, before
world — same slot convention as E1's new families):

| arm | Battery B | D07 count3%3 | D08 count3%4 | C09-analog inv parity | ORDER2 rank0 parity |
|-----|-----------|--------------|--------------|-----------------------|---------------------|
| BASE (earned menuacc+cmp) | 11/11 | solved (menu) | solved (menuacc) | solved (cmp) | **UNSOLVED, cov=0.582** |
| **ALL (+dcmp)** | **11/11** | solved (menu) | solved (menuacc) | solved (cmp) | **SOLVED via dcmp, cov=1.000** |

- **Regressions: 0.** No target solved in BASE is unsolved in ALL — Battery B
  stays 11/11 (byte-identical sources: monomial forge, walsh, menu, menuacc,
  cmp), D07/D08/C09-analog all keep their existing solve routes.
- **Flips: 1 — ORDER2, via `dcmp`, cov 0.582→1.000.** This is the whole
  point: the auto-discovered family, wired as a production ladder stage,
  actually promotes the ORDER2 solve under the real `solveLadder` escalation
  (not just the Phase-1 diagnostic sweep). The dcmp stage is reached only
  after cmp fails to clear COVER, so it never perturbs an already-solved
  target — confirmed empirically here (zero source changes on the 14
  BASE-solved cells). The one honest cost: the ALL arm's probe count on
  targets that reach the dcmp stage jumps (e.g. ORDER2 1,415→18,245 probes)
  because the 16,800-candidate dcmp sweep runs before the target is solved —
  a bounded, pre-certification cost paid only by targets cmp cannot solve,
  the same cost signature E1 documented for its own new stages.
- The ladder's `tryDcmpStage` uses `valAccSingle` (the production SGD
  statistic, matching cmp/thresh/mixr/etc.'s own convention) with a trimmed
  16-point cos-scan (E1's established trim, re-verified in Phase 1 that no
  certified solve ever needs a cos lens over a mod lens) — not the generous
  `bestThresholdAcc` sweep Phase 1 used to prove discoverability. This is the
  "would a real pipeline actually promote it" check, separate from "can an
  exhaustive diagnostic sweep find it."

## 6. What this says about auto-discovery of representability-expanding families

- **The machine invented the family, not just the member.** Unlike E1 (which
  handed the search 5 fixed CMP pair-sets and 4 more hand-designed
  generators), F2 handed the search a *shape* (subset + relation-mode) and let
  it choose the pair-set itself from 765 candidates. The winner is exactly
  the "distinguished-cell" generalization E1's authors could name but had not
  built.
- **This crossing was cheap, unlike E3's.** E3's alien-ISA program space
  needed a mechanism-shaped structural prior applied as a *coverage inclusion*
  specifically because the sufficient-stone level (length-3 programs) had
  >10^5 distinct behaviours — full enumeration was intractable, and blind
  sampling, gradient climbing, and even signature-biased sampling all failed
  (F 0/9). Here, the natural alphabet (8 cells, subsets of a fixed small set)
  is small enough (765 pair-sets) that **no coverage-explosion mitigation was
  needed at all** — full exhaustive search sufficed on the first attempt, no
  gradient or prior-sampling ablation required. This is itself a finding: the
  space of "which comparisons to aggregate" for an 8-cell grid is cheaply
  exhaustible, unlike the space of "which program computes the mechanism" for
  an alien ISA. The bound this places on auto-discovery: **when the natural
  parametrization of a family is low-dimensional (here: one subset of 8
  elements + a 3-way mode choice), exhaustive search finds it directly; E3's
  harder lesson (structural priors are needed to tame combinatorial
  explosion) applies to families whose natural parametrization is
  high-dimensional (program space, sequence space), not to this one.**
- **The two experiments are not in tension.** E3 showed a *floor*: without
  ANY structural prior, blind generation fails even at 54,432 draws. F2 shows
  a *ceiling is reachable cheaply* when the prior (comparison-shape) already
  bounds the space to hundreds of candidates. Both are honest data points on
  the same question — "can structural priors let a machine invent
  representability" — at different points on the search-space-size axis.

## 7. Honest scope / limitations

1. **Uniform-iid 8-cell grid, values 0..5** — identical distribution to every
   Tier-8 measurement in this arc; the discovery and ceilings are
   distribution-specific.
2. **Pre-tax**, matching E1/round-c convention; `equivalence_tax.zig` not
   consulted (mid-arc convention, not a hidden gap — see E1 §8.2 for the
   precedent).
3. **The DCMP search space (765 pair-sets) is itself a design choice** — a
   subset-of-cells + 3-mode generator. It is a genuine generalization of
   CMP's 5 fixed sets (each is a named special case, verified in §1) and was
   not tuned to include a singleton-hub option deliberately for cell 0 in
   particular: the search treats all 8 possible hubs (and all other 247
   non-singleton, non-full subsets) identically, and the winner is chosen
   purely by score. But the *shape itself* (compare-pairs, subset-conditioned)
   was chosen by the experiment design, matching the round's own framing ("the
   prior is the comparison-shape... the SEARCH must find WHICH comparisons/
   aggregation").
4. **"Retro-audit at depth 4" has no literal analogue in this domain** — see
   §4 for the explicit, stated substitution (held-out seed + R² gate) rather
   than a silent reinterpretation.
5. **Only ORDER2 was targeted.** This experiment does not claim DCMP
   generalizes to auto-discovering families for RUN1/RATIO1/MIXMOD1 or the
   GF(2)-XOR wall (C01/C03/C11) — those need different structural shapes
   (sequential/adjacency, algebraic products, joint residues, linear-GF(2)
   respectively), not subset-conditioned comparison-pairs. Untested here,
   flagged as future work.
6. **Two of the four seeds show mildly positive R²** (0.034, 0.036) rather
   than the strongly-negative R² typical of E1's solves. Still well under the
   R2_MAX = 0.40 novelty bar (a clean pass), but reported exactly rather than
   rounded into the more common negative-R² pattern.

## Files

- Harness: `sparse_poly_discovery/autofamily_order2.zig` (`--phase0` =
  before-proof, ~0.4 s; `--phase1` = auto-discovery, 4 seeds, ~31 s;
  `--phase2` = ladder regression, production seed, ~9.2 min; no args =
  all three).
- Data: `results/autofamily_order2_2026_07_11.csv` (base rates, 7×3 basis
  ceilings, CMP-insufficiency rows, per-seed DCMP sweep sizes/winners/top-10
  landscape/SGD cross-check/certify rows for 4 seeds, genuineness summary,
  Battery B + 4 extra-target ladder rows for 2 arms, regression summary).
- Reproduce (from `sparse_poly_discovery/`, zig 0.14.1):
  ```
  zig build-exe autofamily_order2.zig -O ReleaseFast
  ./autofamily_order2 --phase0   # before-proof, ~0.4 s
  ./autofamily_order2 --phase1   # auto-discovery, 4 seeds, ~31 s
  ./autofamily_order2 --phase2   # ladder regression, production seed, ~9.2 min
  ./autofamily_order2            # all three, one process
  ```
- Read-only references (not imported): `sparse_poly_discovery/repr_expansion.zig`
  (E1 — ORDER2's definition, the 7-basis Bayes-ceiling method, CMP's 5 fixed
  pair-sets, the pre-tax ladder and certifier, transcribed here), `wcore/
  src/smart_gen.zig` (E3 — the "exhaustive, behaviour-deduped coverage steered
  by a structural prior" method, applied here to a different domain).
- Imported (none touch the tax): `open_invention_rq1.zig` (zoo training,
  Battery B spec/labels), `tier8_battery_d.zig` (Battery D D07/D08 labels),
  `operator_menu_lib.zig` (the production Walsh discoverer used by the
  conditional-Walsh stage).
- Related docs: `docs/research/repr_expansion.md` (E1 — ORDER2's frontier
  status, the .646 ceiling, CMP's 5-set menu), `wcore/docs/research/
  smart_gen.md` (E3 — the smart-generation method reused here), `docs/
  research/tier8_reach_gap.md` (round c — CMP's origin, the D08/MENUACC
  selection-vs-certification lesson reused in §3.2).
