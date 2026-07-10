# Tax gate as promotion gate — A/B/C compounding experiment

**Date:** 2026-07-10
**Harness:** `sparse_poly_discovery/tier8_tax_gate_ab.zig` (new file; no existing file edited)
**Seeds:** grid `0xF0235A11CE0FF1CE`, `0x1CEB00DA20260710`, `0xBADC0FFEE0DDF00D`; battery `0xE1B10D20A11CE01` (fixed)
**Tax basis:** v4 (family-conditioned remix tests, `equivalence_tax.zig`)
**Verdict:** **NEGATIVE for the gate.** Tax-survivors do compound, but the gate is strictly dominated by the current measurement-only behaviour: it loses 2/33 phase-1 solves and costs 5.4× the evals for the same phase-2 solve rate. Keep measurement-only (the shipped v4 reality lane IS the correct hybrid).

## Question

The strict equivalence tax (T8-AG-02/02f) currently only MEASURES which promotions
are remix — the v4 reality lane passes every certified candidate through. Open
question: if tax-survival becomes a PROMOTION CONDITION (remix-blocked candidates
are NOT promoted into the growable library), do tax-survivors COMPOUND — does the
gated library solve later targets as well as or better than an ungated library,
and at what eval cost?

## Design

Three arms, identical ladder, identical targets, identical order, identical seeds:

| Arm | strict tax | v4 reality lane | Library carryover | Semantics |
|-----|-----------|-----------------|-------------------|-----------|
| A `gated` | ON | OFF | across targets | remix-verdict candidates NOT promoted; that ladder rung fails and search continues |
| B `current` | ON | ON | across targets | shipped default: every certified candidate promotes, tax verdict measured only |
| C `no_promotion` | off | — | NONE (library reset to trained monomial forge before every target) | no-compounding control |

Implementation notes (all via existing `pub var` toggles; zero source edits):

- Arm A = `eqtax.strict_enabled=true, eqtax.reality_lane_enabled=false`. In
  `unified_invention.certify()` the gate return makes `cert.ok=false`, so the
  candidate is not promoted AND cannot solve via that rung. The non-promoting
  escalation lanes (`rq1.tryModEscalation`, `rq1.tryPairWalshEscalation`) remain
  available — they never touch the gate and never grow the library.
- Arm B = `strict_enabled=true, reality_lane_enabled=true` — exactly the
  configuration of the shipped `tier8_tax_taxonomy` run (v4 default).
- Arm C = `strict_enabled=false` + library reset to the trained zoo-A forge
  library before each target. Within-target promotion is allowed (the ladder
  needs the feature in the library to certify coverage) and then discarded.

### Two-phase battery (compounding order)

Phase 1 = battery B (B1..B11, fixed order). Phase 2 = 8 designed follow-ups that
run AFTER the library has (or has not) grown:

| Target | Kind | Tests |
|--------|------|-------|
| P1 repeat Walsh χ{0x11} | walsh_subset | needs B5's promotion (remix-verdict in baseline) |
| P2 repeat Walsh χ{0xA4} | walsh_subset | needs B6's promotion (remix-verdict) |
| P3 repeat sum%7 | sum_mod 7 | needs B3's promotion (**tax-survivor**) |
| P5 repeat monomial deg2 | random_monomial (B1 mask) | needs B1's promotion (remix-verdict) |
| P4 compose parity AND sum%7 | composed | linearly separable from the two **tax-survivors** (parity χ{0xFF} + sum%7) |
| P6 fresh Walsh χ{0x51} | walsh_subset | fresh control |
| P7 fresh monomial deg3 | random_monomial | fresh control |
| P8 fresh parity AND sum%3 | composed | fresh composed control |

"Library hit" = target solved instantly from frozen library coverage
(`cov0 ≥ 0.90`, label `frozen/grown monomials`, cost 1 fit eval).

### Budget protocol

All arms attempt the same 19 targets with the same ladder code; evals are counted
by `rq1.EvalCounter` (fit + certify + probe) and reported per arm. Eval spend is
an OUTCOME of the gate policy, reported on the cost side — no arm gets extra
search rungs or extra targets.

## Reproduce

```bash
cd sparse_poly_discovery
zig build-exe tier8_tax_gate_ab.zig -O ReleaseFast
./tier8_tax_gate_ab --seed=0 --csv=/tmp/seed0.csv   # ~2 min per seed
./tier8_tax_gate_ab --seed=1 --csv=/tmp/seed1.csv
./tier8_tax_gate_ab --seed=2 --csv=/tmp/seed2.csv
```

CSV (merged): `results/taxgate_ab_2026_07_10.csv`. 2 threads (main + 1 big-stack
worker for the tax greedy fit). ~2 min per seed run.

## Measured results (2026-07-10)

Per arm, per seed. `checked/blocked` = tax gate calls / remix-blocked promotions;
`novel/remix` = witnessRemix verdicts (measured identically in A and B);
`kept` = library growth beyond the 11 trained forge features.

| Seed | Arm | P1 solve | P2 solve | P2 lib hits | checked | blocked | novel | remix | kept | evals |
|------|-----|---------|---------|------------|---------|---------|-------|-------|------|-------|
| F023…F1CE | A gated | **11/11** | 8/8 | 2 | 30 | 27 | 3 | 27 | 3 | 2004 |
| F023…F1CE | B current | 11/11 | 8/8 | 5 | 11 | 0 | 3 | 8 | 11 | **397** |
| F023…F1CE | C none | 11/11 | 7/8 | 1 | 0 | 0 | — | — | 0 | 749 |
| 1CEB…0710 | A gated | **10/11** | 8/8 | 2 | 31 | 28 | 3 | 28 | 3 | 2354 |
| 1CEB…0710 | B current | 11/11 | 8/8 | 5 | 11 | 0 | 3 | 8 | 11 | **397** |
| 1CEB…0710 | C none | 11/11 | 7/8 | 1 | 0 | 0 | — | — | 0 | 756 |
| BADC…F00D | A gated | **10/11** | 8/8 | 2 | 31 | 28 | 3 | 28 | 3 | 2040 |
| BADC…F00D | B current | 11/11 | 8/8 | 5 | 11 | 0 | 3 | 8 | 11 | **397** |
| BADC…F00D | C none | 11/11 | 7/8 | 1 | 0 | 0 | — | — | 0 | 756 |

**Aggregate (3 seeds):**

| Arm | P1 | P2 | Total | P2 library hits | Kept promotions | Blocked | Evals |
|-----|----|----|-------|-----------------|-----------------|---------|-------|
| A gated | 31/33 | 24/24 | **55/57** | 6 (P3, P4 only) | 9 | 83 | 6398 |
| B current | 33/33 | 24/24 | **57/57** | 15 (P1–P5) | 33 | 0 | **1191** |
| C no promotion | 33/33 | 21/24 | **54/57** | 3 (P4 only) | 0 | 0 | 2261 |

### Per-target detail (what failed, and why)

- **Arm A P1 failures:** seed `1CEB` lost **B10 parity AND sum%5** (saturated
  0.898 — the world `sum%5` promotion was remix-blocked and the mod/pipeline
  escalation did not certify); seed `BADC` lost **B4 sign%mod 11** (saturated
  0.886 — B4 solves in other arms as a borderline ~0.90 library hit that relies
  on the remix-verdict B1–B3 promotions the gate had blocked).
- **Arm A P2 library hits, all 3 seeds:** exactly **P3 (repeat sum%7)** and
  **P4 (compose parity AND sum%7)** — the two targets designed around the tax
  SURVIVORS. The survivors do transfer. The remix-dependent repeats P1/P2/P5 had
  to be re-solved from scratch every time (that is where most of A's 5.4× eval
  cost goes: 83 blocked promotions, many re-certified repeatedly by the forge
  rounds).
- **Arm B P2 library hits:** all five repeat/composition targets (P1, P2, P3,
  P4, P5), cov = 1.000 instantly.
- **Arm C failures:** **P8 fresh parity AND sum%3** saturated (0.843–0.847) on
  all 3 seeds — the only arm to fail it. A and B both solve P8 (A even promotes
  a survivor for it). Without library carryover the composed fresh target is out
  of reach for the ladder + escalation lanes.
- **Caveat on P4:** the trained monomial forge alone reaches ~0.925–0.940 on P4
  (arm C "hit"), so P4 is only a partial survivor-probe; in arm A it hits at
  cov = 1.000 via the survivors, in C at ~0.93 via raw monomials.

## Compounding verdict

**Tax-survivors DO compound** — arm A's library (3 kept features per seed:
`sum%7`, parity-Walsh `χ{0xFF}`, plus one P8-phase survivor) instantly solves the
survivor-dependent later targets (P3, P4) on every seed, and arm A matches B at
24/24 on the phase-2 battery.

**But gating does NOT beat the ungated library.** Arm B compounds strictly more:
its remix-verdict promotions are exactly what makes P1/P2/P5 free and what
carries the borderline B4/B10 solves. "Remix under the greedy basis" does not
mean "useless downstream" — a remix-verdict feature is still the cheapest stored
form of the solution, and re-deriving it later costs real evals (and sometimes
fails, B4/B10).

Ranking at equal protocol: **B (57/57, 1191 evals) > A (55/57, 6398 evals) >
C (54/57, 2261 evals)**.

## Trade-off analysis (the honest headline)

The gate starves the library, exactly as feared:

- Kept promotions collapse 33 → 9 (3 per seed vs 11 per seed).
- 2/33 phase-1 targets are LOST outright (B4, B10 on 2 of 3 seeds) because
  remix-blocked features had real immediate + downstream value.
- Eval cost **inflates 5.4×** (6398 vs 1191): the blocked rung keeps
  re-proposing and re-certifying candidates (83 blocked promotions vs 0), and
  each blocked check pays the expensive greedy tax fit; phase-2 repeats must be
  re-derived instead of hitting the library.
- The only thing the gate buys — knowing which library features are non-remix —
  is already available for free in arm B as the tax VERDICT LOG (3 novel /
  8 remix per seed on the same promotions; arm A finds the same 3 novel but pays
  27–28 blocked re-checks to refuse the rest).

Against the no-promotion control, compounding per se is clearly positive
(C loses P8 everywhere and pays 1.9× evals), so the library is doing real work;
the question was only ever which promotions to keep. Answer: keep them all,
label the remixes.

## Recommendation

**Keep measurement-only.** Do not adopt tax-survival as a promotion condition.

- The shipped v4 configuration (strict tax + reality lane) is already the right
  hybrid: certified escapes promote (cheap, compounding), the remix verdict is
  recorded per promotion (ledger + tax log), and the novel-rate feeds the
  Phase-5 remix-rate monitor (T8-AG-21) as an alert, not a blocker.
- If a gate is ever wanted, it must be cheaper and softer than block-on-remix:
  e.g. deprioritize (search remix-verdict features last) rather than reject, or
  gate only LIBRARY EXPORT (what gets lifted to wcore / downstream engines, cf.
  T8-AG-28f minimal-lift) rather than within-battery promotion. Blocking inside
  the solve loop is the wrong layer — it converts a free measurement into a
  5.4× eval tax and a solve-rate regression.

## Files

- Harness: `sparse_poly_discovery/tier8_tax_gate_ab.zig`
- Data: `results/taxgate_ab_2026_07_10.csv` (171 per-target rows + per-arm
  summary comment rows, 3 seeds × 3 arms × 19 targets)
- Related: `docs/research/tier8_ag_02_tax_v3.md`, `tier8_ag_02f_taxonomy.md`,
  `tier8_ag_22f_v4_basis.md` (reality lane), `tier8_mega_plan.md` Phase 1/5
