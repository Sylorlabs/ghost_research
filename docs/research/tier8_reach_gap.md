# Tier 8 reach gap — where the ladder's families end (D08 / C09), and the cheapest extension that closes it

**Harness:** `sparse_poly_discovery/tier8_reach_gap.zig` (new file; no existing
file modified; `equivalence_tax.zig` deliberately **not imported** — it is
mid-edit by another agent this round, and this question is pre-tax by
construction: battery-D's own data shows `blocked=0` for D08 in both arms, so
the tax never fires on these targets anyway).
**Date:** 2026-07-10 (round c)
**Seeds:** the 3 standard — `0xF0235A11CE0FF1CE`, `0xC1B10D20260706`,
`0xC2B10D20260707`.
**Wall clock:** 13.0 min single binary, single-threaded (Phase A 5.4 s; the
bulk is 2 full-battery arms × 3 seeds × 33 targets).
**Verdict:** The "reachability gap" is **two different gaps**. C09 is a true
**family-level** gap (proven by information-basis Bayes ceilings ≈ 0.50 for
every ladder family), closed by the minimal comparison-aggregate family
(`cmp(all28, mod2)`, exact, 3/3 seeds). D08 is **not** family-level — the
ladder's own spectral family contains an exact member; it is a
**member-selection** gap (power-argmax picks the wrong frequency), closed by
accuracy-scored selection over the *same* 200-frequency grid (3/3 seeds).
Both fixes together: **zero regressions across 99 target-seed cells**, +11
flips (D08×3, C09×3, B11×3, D09×2 — the last a previously unknown held-out-seed
fragility of the same selection bug). The 9 XOR-wall battery-C targets remain
unsolved, as expected — that is a different, already-measured wall.

---

## Question

`docs/research/tier8_battery_d.md` classified D08 (`count3 % 4 == 0`) as
TOO_HARD: no escalation stage ever certifies an escape — not tax-blocked,
simply unreachable. `docs/research/tier8_aimed_proposer.md` found C09
(inversion-count parity) resists both aimed and brute mask×lens composition —
"the wrong feature family entirely." These two mark the boundary where the
ladder's families end. This experiment (1) diagnoses each gap precisely —
family-level or budget/selection-level, (2) derives the minimal family that
expresses each target, (3) implements the cheapest extension as ladder stages
and re-runs everything, (4) measures the closure-escape cost signature.

## Design

**Pre-tax ladder replica.** `ui.solveOneTarget`'s ladder (base → monomial
forge ≤6 rounds → pair router → conditional Walsh → operator menu →
world pool) was transcribed into the new harness with identical numerics
(same NSAMP/NTR/NVA splits, same probe/certify epochs and learning rates,
same COVER=0.90 / R²<0.40 thresholds), minus the `eqtax.gatePromoteEx` call.
Replica fidelity was verified against the documented record before drawing
conclusions (see "Replica fidelity" below).

**Phase A — per-family exhaustive diagnosis** (production seed), three probes
per family, on D08, C09, and D07 (a known-solvable control):

1. *Ladder pick*: what the production selection statistic would choose.
2. *Exhaustive member sweep at generous budget*: every member scored by the
   exact best-threshold accuracy on the val split, evaluated on test
   (monomials swept to deg 8 vs the ladder's 4; spectral swept on an 800-freq
   grid vs 200; clifford θ swept 64 values vs 1; world k=2..20 vs 6 primes),
   plus a pre-tax certify attempt on the best member.
3. *Information-basis Bayes ceiling*: per-bin majority vote on the family's
   input statistic — an upper bound on **every** function of that statistic,
   hence on every present and future member of any family defined over it.
   Ceiling ≈ chance is a family-level impossibility proof, not a budget claim.

**Phase B — extension arms.** Two minimal, independently toggleable additions:

- **MENUACC** (selection fix, zero new families): spectral member selection
  by held-out accuracy over the *same* 200-freq `cos(ω·count3)` grid the menu
  already owns, instead of `discoverSpectral`'s power argmax. Runs after menu.
- **CMP** (the minimal new family): comparison-pair aggregates
  `A_P(g) = #{(i,j) ∈ P : g[i] > g[j]}` over 5 canonical, untuned pair-sets
  (all28 / low6 / high6 / cross16 / adj7) with the standard lens set
  {identity, mod2..mod6, cos(ωA) 200-freq scan} — 1030 members total, scored
  by the standard single-feature probe, certified through the standard
  escape+R² bar. Runs after MENUACC, before world.

Arms: **L0** (replica baseline) and **L3** (both additions) run the FULL
battery B (shared growable library, production protocol) + battery C (fresh
library per target) + battery D (fresh library per target) at all 3 seeds;
**L1** (+CMP only) and **L2** (+MENUACC only) run D08+C09 at the production
seed for attribution.

### Reproduce

```bash
cd sparse_poly_discovery
zig build-exe tier8_reach_gap.zig -O ReleaseFast   # zig 0.14.1
./tier8_reach_gap --diag   # Phase A only, ~5 s
./tier8_reach_gap          # full, ~13 min, single-threaded
# CSV -> results/reach_gap_2026_07_10.csv  (253 data rows)
```

---

## 1. Diagnosis: the per-family best-score table (Phase A, production seed)

Exhaustive best member (generous budget) per family; `cert` = the best member
passes the pre-tax escape+R² bar against the fresh trained library.

### D08 `count3 % 4 == 0` (base rate 0.281)

| Family | members swept | best member | best val | ladder pick | cert |
|--------|--------------|-------------|----------|-------------|------|
| monomial (deg≤4, ladder budget) | 162 | φ(0x2B) | 0.712 | — | no |
| monomial (deg≤8, generous) | 255 | φ(0xFF) | 0.797 | — | no |
| pair_relation | 28 | pair(0,1) | 0.710 | — | no |
| walsh χ_S (sign bits) | 255 | χ(0xFF) | 0.791 | — | no |
| **spectral cos(ω·count3)** | 800 | **ω=1.453 (≈π/2)** | **1.000** | **0.791 (power pick ω=π)** | **YES (cov 1.000, R²=−0.03)** |
| clifford sin(θ(v1−v0)) | 64 | θ=0.049 | 0.710 | 0.710 | no |
| world_sum_mod (k=2..20) | 19 | sum%20 | 0.718 | — | no |
| world_sign_mod (k=2..20) | 19 | sign%15 | 0.781 | — | no |
| mod-synth slice (count programs) | 13 | mod(count,4) | 1.000 | — | (battery-B-only stage) |
| NEW cmp aggregates | 1030 | cmp(all28, cos ω=0.24) | 0.711 | — | no |

Basis ceilings: **count3 = 1.000**, signPattern = 1.000 (count3 is a function
of it; the single-χ walsh *family* still caps at 0.791 measured), gridSum
0.729, v1−v0 0.718, inversion 0.718, max_cell 0.721, sum01 0.718.

**D08 verdict: NOT family-level.** The ladder's own spectral family contains
an exact, certifiable member. The gap is member selection: `discoverSpectral`
maximizes count-weighted DFT power, and the Binomial(8,½) mass concentrates
the power objective on the parity harmonic ω=π (whose best threshold accuracy
is only 0.79), while the mod-4 separator at ω≈π/2 — cos(ω·c) ≥ θ isolates
c∈{0,4,8} exactly — has lower spectral power. The selection statistic is not
the certification statistic; the argmax certifies one member and the ladder
moves on. A budget increase changes nothing (the 200-grid already contains
π/2 at gridpoint 100); a family addition is unnecessary.

### C09 inversion parity (base rate 0.503)

| Family | members swept | best member | best val | cert |
|--------|--------------|-------------|----------|------|
| monomial (deg≤4 and deg≤8) | 162 / 255 | φ(0x9A) | 0.534 | no |
| pair_relation | 28 | pair(1,4) | 0.529 | no |
| walsh χ_S | 255 | χ(0x9A) | 0.531 | no |
| spectral cos(ω·count3) | 800 | ω=1.261 | 0.517 | no |
| clifford | 64 | θ=0.049 | 0.523 | no |
| world_sum_mod | 19 | sum%15 | 0.510 | no |
| world_sign_mod | 19 | sign%19 | 0.515 | no |
| mod-synth slice (count) | 13 | mod(count,4) | 0.517 | no |
| **NEW cmp aggregates** | 1030 | **cmp(all28, mod2)** | **1.000** | **YES (cov 1.000, R²=−0.07)** |

Basis ceilings: count3 0.510, gridSum 0.494, signPattern 0.516, v1−v0 0.505,
max_cell 0.517, sum01 0.503 — **every ladder information basis is at chance**
— versus **inversion basis = 1.000**.

**C09 verdict: FAMILY-LEVEL, proven.** Not one member of any existing ladder
family clears 0.534 even at generous budget, and the Bayes ceilings show no
function over any ladder basis ever could. This is an impossibility result
for the family set, not a search shortfall.

### D07 control (count3 % 3, known solvable)

Power pick ω=2.074 (≈2π/3) acc 1.000; acc pick ω=1.936 acc 1.000; menu-style
certify passes. The instrument reproduces the known-solvable case — power and
accuracy selection agree here, which is exactly why D07 was never stuck.

## 2. What D08/C09 actually need (functional forms)

- **D08** = `1[count3(g) ≡ 0 (mod 4)]`. Minimal expression already in-family:
  a single thresholded cosine of count3 at ω≈π/2 (three-level feature
  {1, 0, −1} over the 9-point count domain; threshold isolates residue 0).
  The needed change is *which member gets certified*, i.e. score candidates by
  the same statistic the certifier uses (held-out accuracy).
- **C09** = `parity(Σ_{i<j} [g_i > g_j])` — an order-statistic over all 28
  pairwise comparisons. The minimal primitive family is the
  **comparison-pair aggregate with a mod-2 lens**. Auxiliary measurement
  (fresh RNG, n=7000): parity over any canonical *proper* subset of
  comparators sits at 0.505–0.519 and the best single comparator bit is
  0.515 — the landscape is flat everywhere except the exact full-set
  aggregate, structurally the same flat-except-one-point shape as the XOR
  wall. The saving grace: unlike XOR-over-cells, no mask search is needed —
  the full pair-set is *the* canonical order statistic, so a fixed small
  family (5 untuned pair-sets × standard lenses) contains the exact member
  as a named, enumerable candidate.

Note on the production engine: both targets are already expressible by
rq1-escalation families (`mod(count,4)` in the count-program bank;
`inversion→half_p` in the pipeline stage) — but those stages are reachable
**only for battery B**, and only because `needsMod(tgt.kind)` reads the
target's own declared kind (target-metadata gating). Batteries C/D go through
`ui.solveOneTarget`, which owns neither family. The extended ladder achieves
the same solves blind, with no metadata.

## 3. Extension results (Phase B)

### Attribution (production seed, fresh library, D08 + C09)

| Arm | D08 | C09 |
|-----|-----|-----|
| L0 replica | stuck 0.699 | stuck 0.477 |
| L1 (+CMP only) | stuck 0.699 | **SOLVED 1.000 via cmp(all28,mod2)** |
| L2 (+MENUACC only) | **SOLVED 1.000 via cos(ω=1.477·count)** | stuck 0.477 |
| L3 (both) | SOLVED (menuacc) | SOLVED (cmp) |

A clean double dissociation: each fix closes exactly the gap its diagnosis
predicted, and neither touches the other.

### Full batteries, 3 seeds (L0 vs L3)

| Arm | Battery B | Battery C | Battery D | probes | certs |
|-----|-----------|-----------|-----------|--------|-------|
| L0 replica | 30/33 | 3/33 | 28/33 | 24,485 | 906 |
| **L3 extended** | **33/33** | **6/33** | **33/33** | 86,985 | 884 |

- **Regressions: 0/99 target-seed cells** (checked per-target, per-seed: no
  target solved in L0 is unsolved in L3).
- **Flips: +11**, all with 100% per-seed replication of mechanism:
  - **D08 → menuacc**, 3/3 seeds (cov 1.000).
  - **C09 → cmp(all28,mod2)**, 3/3 seeds (cov 1.000).
  - **B11 (inversion parity) → cmp**, 3/3 seeds — the ladder replica now
    solves blind the one battery-B target production only solves through the
    metadata-gated pipeline stage.
  - **D09 (count3%5) → menuacc**, 2/2 affected seeds. *New finding:* the L0
    replica shows D09 stuck at 0.705–0.732 on both held-out seeds (battery-D
    classified it TOO_EASY at the production seed only, where menu's power
    pick happens to land right). The D08 selection bug is not an isolated
    quirk — it is seed-fragile across the count3%k family, and MENUACC fixes
    it wherever it appears.
- The 9 XOR-family battery-C targets (C01–C07, C10, C11) remain unsolved in
  both arms at ≈0.50 — the separate, information-theoretically characterized
  wall from the aimed-proposer round. Neither new stage claims it, as
  expected (cmp basis is order-relational, not value-parity).

### Replica fidelity (why L0 is a valid baseline)

L0 reproduces the documented record: battery C 3/33 with exactly C08 solved
per seed (the pre-tax equivalent of the revision arm's 3/33); D08 stuck at
0.698–0.723 (documented: 0.713–0.715); battery D 10/11 at the production seed
with D08 the only miss, matching the battery-D classification; battery B
30/33 with the only per-seed miss being B11 — precisely the target whose
production solve depends on the battery-B-only, metadata-gated escalation,
which the C/D ladder never had. The two held-out-seed D09 misses are a real
property of the production selection statistic (same code path, same
argmax), not a replica artifact — the power pick is the same function
transcribed verbatim.

## 4. Cost signature (Closure-Principle framing)

Eval unit: probes + 3×certifies (a certify = 2 coverage fits + 1 recon fit).
Per-target spend, from ladder start to certify (or to saturation):

| Target | L0 (missing generator) | L3 (generator present) |
|--------|------------------------|------------------------|
| D08 | 230 evals → stuck 0.70 (**∞ per solve**) | **397 evals → 1.000** |
| D09 (held-out seeds) | 230 evals → stuck 0.71–0.73 (∞) | **397 evals → 1.000** |
| C09 | 489 evals → stuck 0.48–0.52 (∞) | **1,689 evals → 1.000** |
| B11 | 329 evals → stuck 0.49–0.52 (∞) | **1,535 evals → 1.000** |

This is a controlled instance of "the target is outside the family closure;
add the generator": without the right generator no finite budget helps (the
Phase-A ceilings make that a theorem for C09, and for D08 the certified-member
selection never surfaces the in-family solution), and with it the solve costs
a few hundred to ~1.7k evals — the same shape as round 1's 322-eval
out-of-closure scaling-law point. The overhead on already-solvable targets is
bounded and pre-certification only: arm-wide probes rise 3.6× (mostly the 200
menuacc + 1030 cmp probes paid by the 27 permanently-stuck XOR cells), while
certifies *drop* slightly (884 vs 906 — fewer futile world-pool certifies
after an earlier stage solves), and zero solved outcomes change.

## 5. Do comparison-aggregates (and accuracy-scored spectral) belong in the production ladder?

**Yes, both — with placements settled by this data:**

1. **MENUACC is a bug-fix, not a feature**: the menu's spectral selection
   statistic (DFT power) disagrees with the certification statistic (held-out
   accuracy) on residue-class targets; certifying the accuracy-argmax of the
   same 200-freq grid costs 200 probes + 1 certify at stuck targets only and
   repaired 5 target-seed cells (D08×3, D09×2) with zero regressions.
   Recommended for `unified_invention.zig`'s menu (either as a follow-on
   stage, as here, or by certifying the accuracy-ranked top-K of the grid).
2. **CMP earns a ladder seat**: it is the minimal family for the
   order-statistic class (C09 proven out-of-closure for everything else),
   fully generic (5 canonical pair-sets, standard lenses, no
   target-specific tuning, no metadata), certifies through the standard bar
   with strongly negative R² (novel by construction relative to the value
   bases), and additionally removes battery B's only metadata-dependent
   solve (B11). Cost is ~1030 probes paid only when earlier stages saturate.
3. Position: after menu, before world (as implemented) — world remains the
   last resort; no ordering effect was observed (sources of all previously
   solved targets are unchanged).

## Honest scope

- Everything here is **pre-tax** ladder reach. The tax gate was not consulted
  (deliberately: mid-edit by another agent; and D08/C09 never produce a
  certified escape for it to gate — `blocked=0` in the battery-D data). When
  the tax lands its v5-ladder verdict layer, cmp features become a new
  engine-expressible family for its remix basis to consider; that interaction
  is future work, flagged, not measured here.
- The Phase-A "mod-synth slice" row sweeps the core count-program members
  (count, sin(count), count mod k) rather than the full depth-4 add/mul bank;
  the count-basis Bayes ceiling row is the rigorous bound covering the whole
  bank (count-programs are functions of count).
- D08's diagnosis contradicts the battery-D round's a-priori guess
  ("ladder-reachability gap") in a precise way: the target is reachable by
  the family, unreachable by the *selection rule*. The battery-D doc's
  TOO_HARD classification stands (the ladder as wired never certifies);
  the mechanism is now identified and is cheaper to fix than a new family.
- C09's family-level proof is grid-distribution-specific (uniform iid cells,
  the standard generator) — as is every other Tier 8 measurement.
- L1/L2 attribution arms ran at the production seed only; the L3 full-battery
  results replicate the attribution 3/3 seeds via per-target source labels.
- The 5 canonical CMP pair-sets are a design choice; only all28 was needed by
  the flips observed. Subset aggregates were kept because they are the
  natural family axis and cost little; no measured target needs them yet.
- Auxiliary comparator-flatness numbers (§2) use a fresh RNG (not the
  production grid PRNG) — illustration of a seed-independent statistic, and
  labeled as such.

## Files

- Harness: `sparse_poly_discovery/tier8_reach_gap.zig` (Phase A + Phase B,
  one binary; `--diag` runs Phase A only)
- Data: `results/reach_gap_2026_07_10.csv` (253 data rows: 30 family_diag
  [10 families × 3 targets] + 21 basis_ceiling [7 bases × 3 targets] + 202
  ladder rows [2 arms × 3 seeds × 33 targets + 4 attribution])
- Read-only reference (not imported): `unified_invention.zig` (ladder
  transcription source), `equivalence_tax.zig` (avoided), `tier8_ablation_d.zig`
- Imported (none touch the tax): `open_invention_rq1.zig` (zoo training,
  battery B spec/labels), `open_invention_e2.zig` (battery C labels),
  `tier8_battery_d.zig` (battery D spec/labels), `operator_menu_lib.zig`
  (the production Walsh discoverer used by the conditional-Walsh stage)
- Related docs: `docs/research/tier8_battery_d.md` (D08's TOO_HARD
  classification, reproduced then explained), `docs/research/
  tier8_aimed_proposer.md` (C09's family miss, now proven and closed),
  `docs/research/research_round_2026_07_10b.md` (named successor problem
  "D08's reachability gap" — answered)
