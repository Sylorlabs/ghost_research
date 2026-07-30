# Tier 8 gate v5 — can a revised gate admit certified escapes AND discriminate remix?
> **Belongs to: Round 2026-07-10b · experiment 3 of 6 (gate v5)** — [round index](research_round_2026_07_10b.md).

**Harness:** `sparse_poly_discovery/tier8_gate_v5.zig` (new file; no existing file modified)
**Date:** 2026-07-10 (round 2026-07-10b, experiment 3)
**Seeds:** `0xF0235A11CE0FF1CE`, `0xC1B10D20260706`, `0xC2B10D20260707` (yesterday's ablation seeds); battery `0xE1B10D20A11CE01` fixed
**Verdict:** **SPLIT, with a winner at the verdict layer.** For reconstructibility-at-full-basis
gates (leave-one-out, tightened-ε, marginal-coverage) the trade-off is
**irreducible and measured**: they block 57/57 planted candidates but kill the
C08 admission (0/3) because C08's full-basis reconstruction statistic is
*exactly 1.0000* — identical to true remix; no threshold separates them. The
**engine-expressible basis test (v5-ladder)** breaks the trade-off: admits C08
3/3 at cov = 1.000 AND blocks 51/51 true remixes (its 6 planted
"misses" are precisely the 6 certified escapes v3 wrongly blocked). As a
**binding** in-loop gate it is still not no-harm-proven (13/22 real
post-revision promotions would flip to block), so the recommendation is to
adopt v5-ladder as the **verdict/measurement + export filter** and keep
promotion measurement-only, retiring the vacuous v4 lane.

---

## Question

The ablation (`tier8_ablation.md`) proved the v3→v4 basis revision is
load-bearing for solves (C08, 3/3 seeds), but left the gate vacuous: v4's
escape-authentic lane condition (`cov_before < COVER ≤ cov_after`) is
*identical* to the certifier's escape condition, so every certified candidate
survives the tax by construction — 0 post-revision blocks, "novel rate" pinned
at 100%. Does a v5 gate exist that (a) still admits the genuine C08 escape
(the mechanism the revision exists for) and (b) still blocks remix?

## Gate definitions (exact)

All variants are pure functions of the same tuple `(grid, lib, cand, Y)` the
live gate sees, built only from `equivalence_tax.zig`'s existing public API.
`COVER = 0.90` throughout. `test_acc(L)` denotes
`witnessRemixAtLevel(grid, lib, cand, Y, level=L).test_acc` — held-out
accuracy of a greedy budget-8 logit fit to the TARGET labels using basis
columns at level L, candidate excluded (`skipCand`), current growable library
included. Because the library already contains every previously promoted
escape, "current basis + all previously promoted escapes except the candidate"
(the leave-one-out set of design (a)) is exactly what the fit sees.

| Variant | Survivor condition | Design lineage |
|---------|--------------------|----------------|
| v4 (shipped) | remix verdict measured, then lane override: certified ⇒ survive | T8-AG-22f (the vacuous lane) |
| v5-full(ε) | `test_acc(3) < COVER − ε`, ε ∈ {0, 0.02, 0.05, 0.08} | designs (a) leave-one-out + (c) tightened-ε — one mechanism, one statistic |
| v5-margin | `cov_after − test_acc(3) ≥ 0.03` | design (b) marginal-coverage |
| v5-ladder | `test_acc(1) < COVER` | engine-expressible remix test (added mid-experiment; provenance below) |

Level 3 = full audit basis: library + static pool (monomial/pair/walsh/world/
clifford) + xor + pipeline + mod-synth. Level 1 = library + static pool only —
exactly the families a ladder rung can PROMOTE. Levels 2–3 add columns that
exist only inside the auditor; no engine rung can put an xor/pipeline/
mod-synth column into the library.

**Provenance note (v5-ladder).** Designed after seed-1 interim data showed
every full-basis variant blocks the C08 escape — the mod-synth bank
reconstructs parity-count at 1.0, which is *precisely why* v3 blocked it and
why ARM-OFF saturates at 0.50 (nothing can promote a mod-synth column). It was
then evaluated on all 3 seeds and all three test parts identically to the
pre-registered variants. The principle is not fitted to the data: *remix
should mean "reconstructible by what the engine already has," not "by what the
auditor can imagine."*

## Test battery (three parts, all 3 seeds)

Per seed the harness runs a live ARM-OFF pass (basis frozen v3, strict) and a
live ARM-ON pass (T8-AG-21 trigger → witnessed T8-AG-22/25 revision → v4 +
lane), byte-identical to `tier8_ablation.zig`, capturing every gate decision
tuple via `eqtax.replay_captures`/`replay_pool`. Each captured tuple is then
re-audited through every variant as a **shadow gate** (same inputs, same
deterministic functions the live gate uses; live v4 decisions recomputed via
the real `gatePromoteEx`, coverages via `ui.certifyPublic`).

1. **ADMISSION** — the C08 promotion event from ARM-ON (1 certified walsh
   escape/seed) is re-gated per variant; the C08 library is rebuilt from only
   the admitted candidates and `measureCoverage` re-run. PASS iff cov ≥ 0.90.
2. **DISCRIMINATION** — every ARM-OFF remix-blocked capture (19/seed) is
   injected post-revision. The pool partitions exactly (verified against the
   ablation CSV): **17/seed B-battery remixes** (the taxonomy work's
   remix-blocked set) + **2/seed C08 certified escapes that v3 wrongly
   blocked** (cov_before 0.5103/0.4874/0.5017 — matching yesterday's C08
   ARM-OFF coverages digit-for-digit).
3. **NO-HARM** — every real ARM-ON promotion event (43 total) is re-gated.
   Decisions are pure functions of the captured tuple, so 0 disagreements on
   a slice proves the substituted gate reproduces the identical live
   trajectory on that slice; any disagreement is a bounded risk, not a proven
   regression. Split at the revision boundary: 21 pre-revision events (live
   gate = v3-strict) + 22 post-revision events (live gate = v4 lane, all
   admitted).

Live-pass regression check (internal control): the harness's own arms
reproduce the ablation — ARM-OFF B 32/33, ARM-ON B **33/33**, C-ladder 0/33
vs **3/33**, ARM-ON battery-B evals 692/699/692 (ablation: 693/693/686),
revision fires after target 1 on every seed.

### Reproduce

```bash
cd sparse_poly_discovery
zig build-exe tier8_gate_v5.zig -O ReleaseFast   # zig 0.14.1
./tier8_gate_v5    # ~10 min, 2 threads (main + 1 big-stack worker)
# CSV → results/gate_v5_2026_07_10.csv  (103 audit rows)
```

## Results (measured 2026-07-10)

### ADMISSION — C08 reconstructed coverage (need ≥ 0.90; live v4 = 1.000)

| Seed | v4 | v5-full ε=0…0.08 | v5-margin | **v5-ladder** |
|------|-----|------------------|-----------|---------------|
| 0xF023… | 1.000 | 0.506 | 0.506 | **1.000** |
| 0xC1B1… | 1.000 | 0.483 | 0.483 | **1.000** |
| 0xC2B1… | 1.000 | 0.502 | 0.502 | **1.000** |
| **PASS** | 3/3 | **0/3** | **0/3** | **3/3** |

The C08 escape's `test_acc(3) = 1.0000` on every seed — the full audit basis
reconstructs parity-count perfectly (mod-synth/pipeline columns), so **no ε
and no margin can admit it without admitting everything**: true remixes in the
planted pool carry the same statistic at the same value. For full-basis gates
the admission/discrimination trade-off is irreducible at this budget — a
measured result, not a design opinion. `test_acc(1)` = 0.718–0.728 < 0.90,
so v5-ladder admits, and the rebuilt library reaches 1.000.

### DISCRIMINATION — planted pool (57 = 51 true B-remixes + 6 wrongly-blocked C08 escapes)

| Gate | Whole pool blocked | True-remix partition (51) | Wrongly-blocked escapes (6) |
|------|--------------------|---------------------------|------------------------------|
| v4 (live, recomputed) | 0/57 (admits 100%) | 0/51 | admits 6/6 |
| v5-full ε=0…0.08 | 57/57 | 51/51 | **blocks 6/6** (the admission failure) |
| v5-margin | 57/57 | 51/51 | **blocks 6/6** |
| **v5-ladder** | 51/57 | **51/51 (100%)** | **admits 6/6** |

The v4 hole is reproduced on real candidates, not hypotheticals: recomputing
the live gate (basis 4 + lane) on all 57 planted candidates admits every one.
v5-ladder's six "misses" on the whole pool are exactly the six C08 certified
escapes — on the partitioned pool its discrimination is perfect in both
directions.

### NO-HARM — real ARM-ON promotions (21 pre-revision + 22 post-revision)

| Gate | Pre-rev flips (live = v3-strict) | Post-rev would-block (live = admit) |
|------|----------------------------------|--------------------------------------|
| v5-full ε=0…0.08 | **0/21** (faithful shadow of v3) | 18/22 |
| v5-margin | — | 18/22 |
| **v5-ladder** | **0/21** | **13/22** |

- The 0/21 pre-revision line for v5-full(ε=0) doubles as a methodology check:
  it *is* the v3-full test, and it reproduces every live v3-strict decision.
- Post-revision verdict structure: the 22 events split 9 novel / 13 remix
  under v4's family-conditioned measurement. **v5-ladder agrees with the v4
  verdict on 22/22** — it blocks exactly the 13 remix-verdict events and
  admits exactly the 9 novel-verdict events (v5-full agrees only 21/22; on
  one `library`-family row greedy non-monotonicity shows up:
  `test_acc(3)=0.690 < test_acc(1)=0.901`, a reminder these statistics are
  greedy approximations, not true reconstructibility bounds).
- So no variant is no-harm-proven **as a binding gate**: v5-ladder would
  flip 13 real admits to blocks. 12 of the 13 are cov 0.5→1.0 *solving*
  promotions on battery-B targets whose block would force escalation-lane
  rescues; `tier8_tax_gate_promotion.md` measured that economics (arm A:
  −2/33 solves, 5.4× evals). The 13th is a borderline B4-like library hit
  (cov_before 0.898, `test_acc(1)` 0.9006 — 0.6pp over the bar).
- Equivalently: **making the v4 measurement binding was already not
  no-harm; v5-ladder inherits that**, because on post-revision events it IS
  the v4 measurement (22/22).

### Eval overhead vs v4

Per check, every variant costs one greedy budget-8 fit like v4's measurement;
they differ only in column count. v5-ladder ≈ library + ~430 static columns —
never more expensive than v4's family-conditioned check (v4 runs level 2 —
similar static pool minus one family, plus 16 xor — for walsh/world/clifford
candidates, but **full level 3** for everything else via `remixOptsFor`'s
else-branch). v5-full/margin always run level 3 (~130 extra audit-only
columns, ≈1.3× the static pool). Used as a verdict replacement (recommended),
v5-ladder is a drop-in with no added checks and a small per-check saving.
Used as a binding gate, the dominant cost is not the check but the
re-derivation loop measured in the gate-promotion experiment (5.4× evals) —
another reason not to bind it in-loop.

## Recommendation

**Adopt v5-ladder at the verdict layer; keep promotion measurement-only;
retire the v4 lane.** Concretely, in the settled tax-role design
(measure + revision trigger + export filter):

1. **Measure:** replace the family-conditioned witnessRemix verdict with the
   v5-ladder verdict (`test_acc(1) < COVER`). It corrects v3's 6 false blocks
   (the load-bearing revision effect survives), reproduces v4's post-revision
   verdicts 22/22, is cheaper per check, and rests on one stated principle
   instead of per-family carve-outs. The escape-authentic lane becomes
   unnecessary rather than merely disabled: C08 survives on the merits
   (verdict = novel), so the gate stops being vacuous **without** an
   override path.
2. **Revision trigger (T8-AG-21):** feed it the ladder-verdict novel rate.
   Post-revision that signal is 9/22 ≈ 41% here — alive again, versus the
   lane-pinned 100% that made the monitor blind after revision.
3. **Export filter (T8-AG-28f minimal-lift):** lift to wcore/downstream only
   ladder-novel features. On this data that exports the 3 genuine battery-B
   escapes + the C08 escape per seed and keeps the 13 remix-verdict library
   conveniences internal — exactly the split the gate-promotion experiment
   said to make ("keep them all, label the remixes"; the labels now
   discriminate).
4. **Do NOT bind v5-ladder in-loop.** 13/22 real promotions would flip; the
   measured cost of that class of gate is a solve-rate regression and ~5×
   evals. Blocking inside the solve loop remains the wrong layer.

For the pre-registered full-basis designs, the honest headline stands: **no
threshold on full-basis reconstructibility separates the C08 escape from
remix — admission and discrimination trade off irreducibly for that gate
family at this budget.** The trade-off is broken only by changing what the
remix test quantifies over (engine-expressible columns), not by tuning it.

## Honest scope

- **Shadow-gate methodology.** No live run with a binding v5 was performed
  (that would require editing `equivalence_tax.zig`'s decision path or wiring
  new toggles; out of scope for a new-files-only round). Trajectory
  equivalence is *proven* only on slices with 0 flips (all pre-revision
  slices; post-revision admits). The 13 would-block flips are a bounded risk
  statement, deliberately not simulated further.
- **The decisive band is still one witness class.** Admission rests on C08
  (plus its battery-B twin B8, visible in the no-harm pool with the same
  `test_acc(1)` ≈ 0.72 signature). Battery-D (round experiment 6) is the
  planned fix for effect size.
- **v5-ladder's definition is relative to the engine.** "Level 1" must track
  the engine's promotable families: if a future revision adds an xor rung to
  the ladder, the ladder basis must gain xor columns or the gate silently
  weakens. This coupling is a feature (the test quantifies over the engine's
  actual closure) but needs a guard when the ladder grows.
- **Greedy fits are non-monotone in basis size** (observed: one row with
  `test_acc(3) = 0.690 < test_acc(1) = 0.901`; the correlation prefilter can
  be flooded by weakly-combining audit columns). All reconstructibility
  statistics here are greedy approximations, not certified bounds.
- The planted pool's "true remix" labels come from the v3 verdicts of the
  taxonomy work, produced by the same greedy machinery; the partition into
  51 + 6 was verified positionally against the ablation CSV, not assumed.

## Files

- Harness: `sparse_poly_discovery/tier8_gate_v5.zig`
- Data: `results/gate_v5_2026_07_10.csv` (103 audit rows: 3 admission + 57
  planted + 43 no-harm; columns include per-variant decisions,
  `test_acc(3)`, `test_acc(1)`, recomputed coverages, revision-boundary flag)
- Related: `docs/research/tier8_ablation.md` (the hole this closes),
  `tier8_tax_gate_promotion.md` (why not to bind in-loop),
  `tier8_ag_22f_v4_basis.md` (the v4 lane), `tier8_ag_02f_taxonomy.md`
  (the planted-remix provenance)
