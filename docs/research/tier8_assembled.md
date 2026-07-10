# Tier 8 assembled engine — does the settled architecture cohere as one pass?

**Harness:** `sparse_poly_discovery/tier8_assembled.zig` (new file; no existing file modified)
**Date:** 2026-07-10 (round 2026-07-10c, integration experiment)
**Seeds:** `0xF0235A11CE0FF1CE`, `0xC1B10D20260706`, `0xC2B10D20260707` (the 3 standard ablation seeds)
**Verdict:** **COHERES — the composite hits every battery's best-known number
simultaneously with zero decision-level interference.** Battery B 33/33,
battery C 8/33, battery D decisive 9/9, at the *same* battery-B eval budget as
revision-only (2072) and with the aimed stage 35% cheaper than it is without
revision (13,122 vs 20,099 evals) because revision removes 16 stuck targets
from its queue. The two escape mechanisms compose additively on disjoint
targets and dedupe correctly on the one overlapping target (D11). One
integration-adjacent finding, bounded and traced: unsolved targets' *reported
terminal coverage* drifts by ±0.01–0.02 downstream of any point where two arms
genuinely diverge — a pre-existing shared-scratch channel (identical drift
exists between yesterday's settled ablation's own arms), never a changed
decision in 300 audited rows.

**Tax-file state (mandatory disclosure):** built and run against the
**uncommitted taxfix working-tree state** of
`sparse_poly_discovery/equivalence_tax.zig` — md5
`a0565dde4c9ced40d31e7af2076e0fd9`, i.e. commit `67fdd13` plus the z-scoring
fix another agent landed this round (greedyFit now standardizes the *train*
columns with train statistics before `fitLogit`, so the fitted weights and the
z-scored test evaluation operate on the same scale; pre-fix, raw-scale weights
were evaluated against z-scored test columns). All binaries were compiled from
this snapshot before any run, so the results are insulated from further
mid-session edits. **Every baseline in this doc is re-measured in-harness
against the fixed tax; deviations from the pre-fix documented numbers are
attributed explicitly below.**

---

## Architecture (as assembled, one engine pass)

```
per (seed, arm):   tax state: v3-strict, reality lane OFF, stats/log/replay reset
  │
  ├─ Battery B (11 targets) ── full production engine (ie.solveBlindTarget,
  │        shared growable library; rescue lanes bypass the tax as in production)
  ├─ Battery C (11 targets) ── ladder-only slice (ui.solveOneTarget, fresh
  │        8-monomial library per target; every promotion tax-gated)
  ├─ Battery D decisive {D01,D07,D11} ── same ladder-only slice
  │
  │   after EVERY target ──► T8-AG-21 revision trigger (checked ≥5, novel rate
  │        <0.20) → witnessed T8-AG-22/25 revision → basis v4 + reality lane
  │        [revision-enabled arms only; fired after target 1 in all 6
  │         revision-enabled (seed,arm) passes]
  │
  │   after any target the ladder leaves UNSOLVED ──► AIMED PROPOSER stage
  │        [aimed-enabled arms only]: evidence mining (162-mask monomial sweep
  │        + 256-pattern Walsh sweep, read-only) → 6-lens scan on the mined
  │        anchor mask → greedy grow/shrink → certify at the production bar
  │        (escape ≥0.90 held-out from below AND R²<0.40).
  │        The tax gate is NEVER consulted here (selection-boundary principle);
  │        a correlation tax-proxy + a v5-ladder verdict are recorded for export.
  │
  └─ end of pass ──► v5-LADDER VERDICT AUDIT over every real gate capture
           (test_acc(level=1) < COVER ⇒ ladder-novel): recording + monitor feed
           + export filter. NEVER blocks — promotion stays measurement-only.
           Exported library = live-admitted AND ladder-novel (+ ladder-novel
           aimed composites).
```

Arms (leave-one-out attribution): `frozen` (v3 forever, no aimed),
`revision` (= assembled−aimed), `aimed_norev` (= assembled−revision),
`assembled` (everything). All arms record the v5 verdict layer.

## Phase 0 — the taxfix moved the decisive band (re-classification)

Because the tax's greedyFit changed under our feet, battery D's band
membership was re-measured first (production seed, same probe as
`tier8_ablation_d.zig` Phase 1):

| Class | pre-fix (tier8_battery_d.md) | post-fix (this run) |
|---|---|---|
| DECISIVE | D01, D07, D11 (3/11) | **D01, D02, D03, D04, D07, D09, D10, D11 (8/11)** |
| TOO_EASY | D02–D06, D09, D10 | D05, D06 (k > mod-synth range — the predicted boundary) |
| TOO_HARD | D08 | D08 (ladder-reachability gap, unchanged) |

The five band-joiners (D02–D04, D09–D10) are **exactly the set the battery-D
diagnosis predicted was leaking TOO_EASY through the raw-vs-z-scored scale
mismatch**. Independently cross-checked: the taxfix agent's own re-runs
(`results/battery_d_taxfix_2026_07_10.csv`) classify all 11 targets
identically and measure the same post-fix ablation aggregate (OFF B 29/33, ON
B 33/33). Two harnesses, two agents, same numbers.

Consequence for this experiment: the decisive *suite* was kept at
{D01, D07, D11} for comparability with the stated baselines (1/9 frozen, 9/9
revision), and the post-fix frozen baseline is re-measured below.

## Composite results (3 seeds × {11 B, 11 C, 3 D} × 4 arms; 300 target-rows)

| Arm | Battery B | Battery C (ladder / final) | Battery D decisive (ladder / final) | evalsB | aimed evals | wall |
|---|---|---|---|---|---|---|
| frozen (v3, post-fix) | 29/33 | 0/33 / 0/33 | 0/9 / 0/9 | 4499 | — | 4m51s |
| revision (=asm−aimed) | **33/33** | 3/33 / 3/33 | **9/9** / 9/9 | 2072 | — | 4m20s |
| aimed_norev (=asm−revision) | 29/33 | 0/33 / **5/33** | 0/9 / **3/9** | 4499 | 20,099 | 7m54s |
| **assembled** | **33/33** | 3/33 / **8/33** | **9/9** / 9/9 | **2072** | **13,122** | 6m13s |

Against every documented baseline:

- **Battery B:** assembled 33/33 = the production PASS bar and the prior
  ARM-ON result. Post-fix **frozen drops 32/33 → 29/33** (B3 `sum%7` blocked
  on all 3 seeds, B10 on one) — the stricter v3 now blocks *everything*
  (84/84 checks remix, 0 novel), so framework revision is now load-bearing
  for battery B too, not just C08/D.
- **Battery C:** frozen 0/33 (= documented), revision 3/33 (= documented,
  all C08), **assembled 8/33 (= the aimed-proposer round's 8/33)** with the
  *identical* five flips (C02, C06 @seed0; C05 @seed1; C04, C06 @seed2),
  byte-identical evidence masks to ground truth, mod2 lens, tax-proxy novel
  (best corr ≤ 0.05).
- **Battery D decisive:** frozen 0/9 (pre-fix 1/9 — D07's borderline seed is
  now cleanly blocked; the separation *sharpened*), revision & assembled 9/9
  (= documented).

The composite loses nothing anywhere: it equals the best arm on every battery
simultaneously. **No integration regression in any solve count.**

## Interference findings

1. **Decision-level: ZERO.** Comparing all ladder-side columns (solved, cov,
   label/route, per-target checked/novel/blocked deltas, library size, basis
   at target, revision timing) per (seed, battery, target):
   - revision vs assembled — 0 differences on every decision column across
     all 75 row-pairs; revision fired after target 1 in every pass of both
     arms; identical gate-capture streams (50 captures, same verdict
     sequence).
   - frozen vs aimed_norev — same: 0 decision differences.
2. **Terminal-coverage drift on unsolved targets (bounded, pre-existing).**
   The only differing values anywhere are the *reported final coverages of
   unsolved targets* (the ~0.50 saturation zone), by ±0.01–0.02, e.g. C02
   stuck at 0.4983 (revision) vs 0.5097 (assembled). Traced: it is
   deterministic (both aimed arms agree with each other exactly, both
   non-aimed arms agree with each other exactly) and appears only *downstream
   of a genuine divergence point* (the first aimed-stage invocation, or —
   in frozen-vs-revision, where NO aimed stage exists — downstream of C08's
   genuinely-different promotions: C09 reads 0.4949 vs 0.4903). The same
   drift with the same digits exists between yesterday's settled
   `tier8_ablation.zig`'s own two arms (its CSV shows C09 off=0.4949 vs
   on=0.4903 on the same seed). Mechanism class: cross-target reuse of shared
   scratch state (the shared `X` feature matrix / `phiTgt` scratch the rungs
   overwrite), a property of the harness *pattern* inherited from the settled
   rounds — not introduced by assembly. In 300 rows it never crossed a
   decision boundary (never flipped solved/stuck, never changed a route, a
   gate verdict, or the trigger). Flagged for a cleanliness fix in the
   harness pattern (re-derive scratch per target), not as an architecture
   problem.
3. **Does revision change aimed behavior?** On the 30 stuck targets shared
   between aimed_norev and assembled, the aimed stage produced **30/30
   identical outcomes** (same mined mask, same walsh evidence, same chosen
   lens, same certify verdict). Revision's only effect on the aimed stage is
   *queue relief*: 16 target-seeds that reach the aimed stage in aimed_norev
   are already solved upstream in assembled (B3×3, B10×1, C08×3, D01×3,
   D07×3, D11×3), cutting aimed attempts 46 → 30 and aimed evals 20,099 →
   13,122 (−35%).
4. **Does the aimed stage change revision behavior?** No — trigger timing,
   basis trajectory, and all 50 gate captures identical (finding 1). By
   construction the aimed stage never touches the tax, the trigger
   statistics, or any shared library; the measurement confirms the
   construction.

## Attribution (leave-one-out)

| Piece removed | B | C | D | Interpretation |
|---|---|---|---|---|
| both (frozen) | 29/33 | 0/33 | 0/9 | post-fix floor |
| aimed (revision arm) | +4 → 33/33 | +3 → 3/33 | +9 → 9/9 | revision carries B rescues, C08, all of D |
| revision (aimed_norev arm) | +0 → 29/33 | +5 → 5/33 | +3 → 3/9 | aimed carries the XOR family; D11 only |
| none (assembled) | 33/33 | 8/33 | 9/9 | **exactly additive: 3+5 on C, no double-count on D11** |

- The two mechanisms address **disjoint escape classes**: revision unblocks
  targets whose certified escape the v3 tax wrongly killed (C08's walsh,
  D01's world, D07's spectral, B3's sum%7); the aimed stage composes features
  the ladder *cannot certify at all* (mod-2 lens XOR masks — not in the
  Feature union).
- **D11 is the overlap case and it dedupes correctly:** in aimed_norev the
  aimed stage flips D11 on all 3 seeds via the th3 lens on mask 0x0F — but
  the export layer correctly identifies this composite as
  **engine-expressible** (tax-proxy corr = 1.0 remix; v5-ladder
  test_acc(1) = 1.000, ladder-remix): it is the ladder's own monomial-sign
  feature under another name, the one v3 kept blocking. In assembled,
  revision admits the ladder's native route first and the aimed stage never
  runs on D11. The architecture resolves the overlap in the right order and
  the verdict layer tells the truth about it in both orders.
- aimed_norev also shows what aiming alone *cannot* do post-fix: with v3
  blocking everything, B stays 29/33 (the aimed stage attempted B3/B10 and
  produced no certified composite) and D01/D07 stay stuck — mod-k structure
  has no mod-2-lens expression.

## v5-ladder verdict layer (recording, monitor feed, export filter)

| Arm | captures | pre-rev ladder-novel | post-rev ladder-novel | live survivors | exported (ladder-novel) |
|---|---|---|---|---|---|
| frozen | 84 | 15/84 (17.9%) | — | 0 | 0 |
| revision | 50 | 0/21 | **15/29 (51.7%)** | 29 | 15 |
| aimed_norev | 84 | 15/84 | — | 0 | 0 |
| **assembled** | 50 | 0/21 | **15/29 (51.7%)** | 29 | **15 (+5 composites)** |

- **The honest novel rate is alive again**: post-revision 51.7% (vs the
  v4-lane-pinned 100% the gate-v5 round flagged as monitor-blinding). On the
  B+C slice alone the taxfix agent's independent re-run measured 9/22 ≈ 41%;
  the delta to 51.7% is battery D's genuinely-novel promotions (sum%2,
  spectral, the D-target features), not a disagreement.
- **Exported library content (per seed, deduplicated): 4 gate-promoted
  features** — `sum%7` (B3, l1≈0.86), `walsh(S=0xFF)` (C08, l1≈0.73),
  `sum%2` (D01, l1≈0.55–0.62), `spectral(ω≈2.07–2.09)` (D07, l1≈0.81) —
  **plus the seed's aimed composites** (mod2-lens XOR masks, l1≈0.50, 2/1/2
  per seed). The 14 remix-verdict survivors (pair(0,4), pair(1,3),
  walsh(0xA4), monomial(0x0F) = D11's forge feature, sum%5) stay internal —
  exactly the "keep them all, label the remixes" split the gate-promotion
  round prescribed, and the labels demonstrably discriminate.
- In frozen/aimed_norev the layer also works as a *diagnostic*: 15/84 of
  v3-blocked certified candidates were ladder-novel — i.e. the fixed v3 tax
  now blocks genuine escapes at scale (these are precisely the C08/D01/D07/B3
  class), which is the standing argument for the revision mechanism.

## Cost

- Wall (3 seeds each, single-threaded): phase0 1m09s; frozen 4m51s; revision
  4m20s; aimed_norev 7m54s; assembled 6m13s. Every invocation far under the
  15-min cap; ≤2 threads honored (1 thread — greedyFit is heap-backed since
  commit `67fdd13`).
- Battery-B evals: assembled = revision = 2072 vs frozen 4499 (blocked
  promotions in frozen force repeated re-escalation — same economics as the
  prior rounds, reproduced post-fix).
- Aimed stage: 13,122 evals total in assembled (≈437/attempt, matching the
  aimed round's ≈438), 35% cheaper than without revision.
- v5 verdict audit: 50 level-1 greedy fits per arm, end-of-pass, seconds —
  cheaper per check than the v4 family-conditioned level-2/3 verdict it
  replaces.

## Recommendation — production default

Adopt the assembled configuration as the Tier 8 production default:

1. **Inner loops un-aimed and un-gated** (unchanged production ladder).
2. **Framework revision ON** (T8-AG-21 trigger → witnessed v3→v4 + reality
   lane). Post-taxfix this is no longer optional: frozen v3 blocks 84/84 and
   costs 4 battery-B solves in addition to all of C08/D.
3. **Aimed proposer as a post-ladder stage on still-stuck targets only.**
   Zero interference measured, strictly additive solves (+5 battery-C), and
   revision-first ordering both dedupes the overlap class (D11) and cuts the
   aimed budget 35%.
4. **v5-ladder verdict at the recording/monitor/export layer, never
   in-loop.** Feed the monitor the honest post-revision novel rate (51.7%
   here); export only ladder-novel features (4 unique/seed + composites);
   keep remix-labeled conveniences internal.
5. Carry-over from phase 0: **re-run the battery-D suite on the post-fix
   8-target decisive band** in the next round (this run kept {D01,D07,D11}
   for baseline comparability; the taxfix agent's 24-cell ablation already
   shows OFF 0/24 vs ON 22/24 on the widened band).
6. Cleanliness fix queued (harness pattern, not architecture): per-target
   scratch re-derivation to eliminate the ±0.01 stuck-cov drift channel that
   all Tier 8 harnesses to date share.

## Honest scope

- The 8/33 battery-C composite inherits the aimed mechanism's measured
  fragility: flips occur only when the noisy evidence argmax lands exactly on
  the true mask ((1/3)^k signal; ~17%/attempt at degree 4). This round adds
  three more seeds-worth of confirmation, not a stronger mechanism. C09
  (order-statistic) and C11 (degree-5) remain honestly out of reach; C01,
  C03, C07, C10 remain probabilistically missed this draw.
- The aimed stage's certifier is the harness-local numeric mirror (same
  hyperparameters/splits as `unified_invention.certify`), because a
  lens-transformed composite is not a `ui.Feature`; its v5-ladder verdict
  uses a never-matching dummy candidate in the skip-list (the fit is over
  target labels from library + static pool, exactly `witnessRemixAtLevel`
  level 1). Composites are export artifacts; they are never inserted into
  the live library — so "final" C solves are engine+proposer solves, not
  ladder-library growth.
- Baselines here are post-taxfix re-measurements, deliberately run in the
  same binary; the pre-fix documented numbers (B frozen 32/33, D frozen 1/9)
  are *not* reproducible against the current tax and are quoted only as
  history.
- One CSV escaping bug was found and fixed post-run: `pair(i,j)` feature
  descriptions in the v5-audit CSVs contained an unquoted comma, shifting 9
  rows' columns (the binary's own printed counters were unaffected). The
  shipped CSVs are sed-repaired (`pair(i;j)`); the in-binary counters and
  the repaired CSVs agree.
- Runs are deterministic (all PRNGs locally seeded); the drift in finding 2
  is deterministic state-dependence, not run-to-run noise — both aimed arms
  reproduce each other's stuck covs exactly, as do both non-aimed arms.

## Files

- Harness: `sparse_poly_discovery/tier8_assembled.zig`
- Merged per-target data (300 rows, 4 arms × 3 seeds × 25 targets):
  `results/assembled_2026_07_10.csv`
- Per-arm raw CSVs: `results/assembled_arm_{frozen,revision,aimed_norev,assembled}_2026_07_10.csv`
- v5 verdict-layer audits (268 capture rows):
  `results/assembled_v5_{frozen,revision,aimed_norev,assembled}_2026_07_10.csv`
- Phase-0 band re-classification: `results/assembled_phase0_2026_07_10.csv`
- Cross-references: `docs/research/tier8_ablation.md`, `tier8_battery_d.md`,
  `tier8_aimed_proposer.md`, `tier8_gate_v5.md`,
  `research_round_2026_07_10b.md`; taxfix agent's independent re-runs in
  `results/battery_d_taxfix_2026_07_10.csv`, `results/gate_v5_taxfix_2026_07_10.csv`

### Reproduce

```bash
cd sparse_poly_discovery
zig build-exe tier8_assembled.zig -O ReleaseFast   # zig 0.14.1; build against
                                                   # equivalence_tax.zig md5 a0565dde…
./tier8_assembled --phase0          # 1m09s
./tier8_assembled --arm=frozen      # 4m51s
./tier8_assembled --arm=revision    # 4m20s
./tier8_assembled --arm=aimed_norev # 7m54s
./tier8_assembled --arm=assembled   # 6m13s
```
