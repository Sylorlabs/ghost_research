# Claim-C depth attack — I53-style depth push on the wcore irreducibility certifier
> **Belongs to: Round 2026-07-10b · experiment 4 of 6 (Claim-C depth attack)** — [round index](../../../docs/research/research_round_2026_07_10b.md).

**Date:** 2026-07-10 (round 2026-07-10b, red-team)
**Runner:** `wcore/src/claimc_attack.zig` (new standalone file; imports existing wcore
sources read-only, ports the private chain helpers from `inv_atomforge.zig`)
**Build:** `cd wcore && zig build-exe -O ReleaseFast src/claimc_attack.zig -femit-bin=bin/claimc_attack` (Zig 0.14.1)
**Run:** `./bin/claimc_attack ../results/claimc_attack_2026_07_10.csv`
**Data:** `results/claimc_attack_2026_07_10.csv`
**Runtime:** 10m24s wall, exactly 2 threads (one per research seed in phases 1–2;
the same 2-thread budget reused for the vacuity phase), deterministic modulo
per-row completed depth (the per-call safety cap is wall-clock, see "budget rows").

**Culture:** adversarial. The assignment was to break wcore's Claim-C machinery the
same way I53 broke the synergy substrate's pair-necessity claims — push the depth
budget past the depth the claims were made at, and count verdict flips.

## Headline

**The attack confirms and sharpens the known ~5% certifier leak; it found no new
cracks at deeper budgets, and the kill-test survives a fully-completed depth-8
enumeration — but with an uncomfortably thin 0.008 agreement margin.** The one
false-irreducible promotion (seed 0x5EED2, round 9) flips exactly at depth 4
(production certifier depth is 3) and its witness chain is verified bit-exact on an
independent 4096-symbol sample. Every other promotion verdict **holds at every depth
the budget allowed to complete** — up to depth 8 against 5-atom prefixes, depth 5–6
against mid-size prefixes, depth 4 against the full 14-atom libraries. The flip
depth distribution is concentrated entirely at +1: nothing flips at +2 … +5 within
completed budgets. So wcore's verdicts are *quantitatively* budget-relative exactly
as I53 predicted, but the measured decay is front-loaded: if a depth-3 verdict
survives depth 4, no deeper budget we could afford overturns it.

## What was attacked (and one correction to the task brief)

Two different instruments in wcore say "irreducible":

1. **`inv_coevo.reducible()`** (Stage-genome reducer) — behind the INDEX.md Claim-C
   line "85/86 behaviours reducible at depth 4; 1 exception reducible at depth 5;
   0 survivors at deeper budget" (`claim_c_breadth.md`, `budget_scan.md`). Its
   *reducible* verdicts are witness-producing and safe-direction; the repo itself
   already budget-scanned it to depth 8 and dissolved its one anomaly.
2. **`inv_atomforge.reducibleLib()`** (atom-Program-library certifier,
   `COMPOSE_DEPTH = 3`) — the gate that **certifies promotions** in the atom-forge
   and in the A1–A6 iterated-promotion loop (`inv_iterate.zig`). Here the risk runs
   the *dangerous* direction: a false "irreducible" becomes a bogus library atom.
   The A1–A6 retro-audit had already caught 1/20 at depth 4.

This round attacks (2) — the promotion certifier — with the real 20-promoted-atom
artifact from the a1a6 seeds (0xA70F, 0x5EED2), and re-runs (2)'s kill-test
(`distinctCountProg`, the same true outsider both instruments use) at the deepest
completed budget as the vacuity control.

**Correction to the brief:** the task named `wcore/src/checker.zig` and
`wcore/src/evaluator.zig` as certifier files. They are not — both belong to the
separate STLC/W-type research line (a total type-checker and a beta-reducer) and
have no connection to Claim C. They were read and confirmed unrelated. The actual
certifier code is `inv_coevo.zig` + `inv_atomforge.zig` as above.

**Register/width axis:** I53's substrate had a second resource wall (K=2 registers).
`reducibleLib` has no analogue — it composes whole atom programs by chaining their
*stream outputs* (`applyChain`), so composition depth is the only resource axis this
certifier exposes. Stated rather than silently skipped. (The per-atom substrate
register file is fixed by `inv_alien.Program` and is not a certifier parameter.)

## 1. Baseline reproduction — exact

The promotion loop (novelty search pop=90 gens=45, clean filter, depth-3
`reducibleLib` census over the 80 shortest clean candidates, promote first
irreducible, 10 rounds) was re-run from scratch for both seeds. Result: **exact
match with `results/a1a6_openatom_2026_07_10.csv`** — same archive/clean/checked/
irreducible counts and the same promoted-atom lengths every round
(0xA70F: 2,4,2,6,4,5,5,3,5,4; 0x5EED2: 5,4,3,3,4,3,5,2,6,7), both libraries 5→15.

Instrument self-check: at every one of the 20 promotions, the attack's own
witness-capturing certifier (`certify()`) was compared against the production
`forge.reducibleLib()` at depth 3 on the same atom/library/seed — **20/20
agreement.** The ported instrument is faithful before it is pushed deeper.

## 2. Depth push — flip counts per depth increment

Every promoted atom re-certified against (a) its promotion-time prefix library and
(b) the final library minus itself, at depths past production (library-size-adaptive
targets, per-call wall-clock caps of 20s/15s; a capped call reports the deepest
*fully completed* level). Full per-row data in the CSV.

Flips relative to the production depth-3 verdict, **promotion-time prefix** (the
certifier-leak question):

| depth increment | flips | denominator (rows whose completed depth reached it) |
|---|---|---|
| +1 (depth 4) | **1** — 0x5EED2 inv8 | 20/20 |
| +2 (depth 5) | 0 | 18/19 remaining |
| +3 (depth 6) | 0 | 9 |
| +4 (depth 7) | 0 | 4 |
| +5 (depth 8) | 0 | 2 |

Against the **final library minus itself** (the redundancy question — reducibility
here is *not* a certifier error, since the reducing atoms did not exist at
promotion time): 3/20 reducible — 0x5EED2 inv0 and inv5 at depth 3, inv8 at depth 4;
0 additional at completed depth 4 for the other 17. All three match the a1a6 audit.

**Closest approaches:** for every never-flipped verdict the best agreement any
enumerated chain achieved is recorded (CSV `best_agreement`): range 0.388–0.839,
i.e. the holds are not 0.94-style threshold-teeterers.

### Budget rows (where budget, not proof, is the limit)

All `irreducible_incomplete` rows are wall-clock-capped, and the honest claim is
only "irreducible at depth ≤ depth_reached":

- prefix checks: requested 6–9, completed 4–8 (5-atom prefixes complete depth 8;
  13–14-atom prefixes complete only 4–5 — 14⁶ ≈ 7.5M chains ≈ ~3 min > cap);
- final-minus-self checks (14 atoms): requested 6, completed 4 — exactly the depth
  a1a6 already covered; **the depth ≥ 5 regime against 14-atom libraries is open**
  at single-run 15-minute budgets (it is reachable in ~hours, not in this round);
- completed depth can vary ±1 between runs on a loaded machine (the cap is
  wall-clock); the CSV records the per-row value for this run.

## 3. Witness audit — every flip has a checked reduction

No flip is claimed without a witness chain re-verified by direct behavioural
comparison on an **independent** 4096-symbol sample (64 streams × 64, seed disjoint
from the certifier's search seed). All four verified at **1.000000** agreement:

| flip | witness (chain, applied left→right) | decoded | verified |
|---|---|---|---|
| 0x5EED2 inv8 vs prefix, d4 | `[5,9,6,0]` | inv0 → inv4 → inv1 → g_xor | 1.000000 |
| 0x5EED2 inv8 vs final−self, d4 | `[5,9,6,0]` | same chain (all parts precede inv8) | 1.000000 |
| 0x5EED2 inv0 vs final−self, d3 | `[5,9,10]` | inv1 → inv5 → inv6 (post-self indexing) | 1.000000 |
| 0x5EED2 inv5 vs final−self, d3 | `[10,5,11]` | inv6 → inv0 → inv7 (post-self indexing) | 1.000000 |

(Prefix-library indices: 0–4 = g_xor, g_add, pk_xor, pk_add, shift; 5+ = invented
atoms in promotion order. Final-minus-self indices shift down past the excluded
atom.) The inv8 chain is a *bona fide* certifier failure: a depth-4 composition of
four atoms inv8 was certified against, admitted to the library as "irreducible at
depth 3".

## 4. Vacuity check at depth — the certifier still rejects the outsider

A certifier that flips everything at depth is broken, not honest. The hand-built
true outsider `distinctCountProg` was pushed through the same attack machinery:

- **base-5 library, depth 8, 16 certifier-seed replicates: 16/16 correctly
  IRREDUCIBLE — with the full depth-8 enumeration COMPLETED** (≈488k chains per
  replicate; `irreducible_complete`, not budget-capped). This upgrades the INDEX
  line "non-vacuous at depth 8" from the coevo instrument to the atomforge
  instrument as well.
- both reproduced final 15-atom libraries, 6 replicates each: 12/12 correctly
  irreducible at completed depth 4 (budget-capped above that).
- **Margin warning:** the closest any enumerated chain came to matching the
  outsider was **0.9420** agreement (base-5 d8; 0.9152 on the finals) against the
  0.95 match threshold. The kill-test passes by 0.008. The matcher is statistical
  (8×28 samples in the certifier); a modestly larger search space or an unlucky
  stream seed could plausibly cross it. This is the same threshold-fragility axis
  the repo's own I54/I55 `matchstress` phase probes — worth keeping linked.

## Corrected qualifiers (mirroring I53's wording)

1. **Promotion language.** Every atomforge / iterated-promotion claim of the form
   "certified irreducible" must read: **"irreducible at depth ≤ 3 against the
   promotion-time library, under the production evaluator (0.95 agreement on 8×28
   random streams, fixed seed)"** — never "irreducible". Measured false-irreducible
   rate at that budget: **1/20 = 5%** (flip depth 4, witness verified).
2. **Retro-audit language.** "Holds at depth 4/5" rows (a1a6) and this round's
   deeper rows are statements of the form "no composition found at completed depth
   ≤ D" — the CSV's per-row `depth_reached` is the D that was actually enumerated,
   and for 14-atom libraries D=4–5 is all a 15-minute budget buys.
3. **INDEX.md wcore rows.** "85/86 reducible at depth 4; 1 exception at depth 5; 0
   survivors at deeper budget" — the reducible-direction claims are witness-backed
   and stand (and belong to `inv_coevo.reducible` / `budget_scan.md`, not
   `inv_atomforge.zig` as the INDEX table implies). The certifier row should read:
   "16/16 kill-tests, non-vacuous at **completed** depth 8 (both instruments),
   closest adversarial approach 0.942 vs 0.95 threshold."
4. **Claim C itself** is unharmed in its own direction: nothing here (or in any
   budget push so far) produced a behaviour that *survives* growing reduction
   budgets on a fixed atom set. What this round bounds is the *opposite*-direction
   instrument that the open-atom program leans on.

## Implication for the promotion loop

- Measured depth-artifact rate among the open-atom program's promotions: **5%
  (1/20), all at +1 depth; 0 further flips at +2 … +5 wherever enumeration
  completed.** The a1a6 headline conclusions survive: correcting the certified
  count from 20 to 19 changes no verdict (A2's no-fixed-point, A3's flat lengths,
  A4's 1-composed-flip-per-seed all stand; a1a6 already excluded inv8-style leaks
  from its key claims).
- The leak is cheap to catch: one extra certifier depth (+1) at promotion time
  found it (witness located in 76 ms; a full no-match depth-4 clearance over a
  14-atom library is ~38k chains ≈ 1 s at this run's measured chain cost). **A
  depth-4 promotion gate is affordable and would have caught the only measured
  leak.** Deeper gates buy nothing measurable at these library sizes.
- The residual honest risk is not depth but the **statistical matcher**: with a
  0.008 kill-test margin at 0.95/8×28, promotions are one unlucky sample away from
  a threshold artifact in either direction. An exact-match confirmation pass on
  candidate witnesses (as `behaviorMatchesExact` does for the coevo side) is the
  cheaper hardening axis now.

## What was NOT attacked (honest list)

- The 86-solver / 16-seed `claim_c_breadth` corpus itself was not re-run (the repo's
  own `budget_scan.md` already pushed that instrument to depth 8 with 0 survivors);
  this round's depth push covers the atomforge-side certifier only.
- `behaviorMatches` threshold behaviour (0.95, sample sizes) was not re-attacked —
  G46 and the I54/I55 `matchstress` phase cover it; the 0.9420 close call above is
  a pointer, not a new measurement of that axis.
- Depth ≥ 5 against 14–15-atom libraries (both for promoted atoms and for the
  final-library kill-tests) is enumeration-open at this round's 15-minute budget.
- The novelty-search side (whether `open.search` archives are biased toward
  fake-irreducible candidates) was not touched; only the certifier's verdicts were.
- Verification of witnesses is behavioural (4096 independent symbols, exact
  1.000000 agreement observed), not a formal proof of functional equality on all
  possible streams.

## Verdict table

| attack | claim attacked | verdict |
|---|---|---|
| depth push +1 (d4), prefix | "20 promotions certified irreducible (depth 3)" | **CONFIRMED-CRACK, known** — 1/20 flips at d4 (0x5EED2 inv8, witness `[5,9,6,0]` = inv0→inv4→inv1→g_xor, verified 1.0); reproduces + independently verifies the a1a6 leak |
| depth push +2 … +5, prefix | same, deeper | **SURVIVED** — 0 flips at completed depths 5–8 (18, 9, 4, 2 rows respectively) |
| depth push, final−self | library minimality | **3/20 redundant** (2 at d3, 1 at d4) — matches a1a6; library growth, not certifier error |
| vacuity at max depth | "certifier non-vacuous at depth 8" | **PASS, upgraded** — 16/16 kill-tests with COMPLETE depth-8 enumeration; but margin is 0.008 (0.9420 vs 0.95) — thin |
| baseline reproduction | a1a6 protocol + data | **EXACT** — all round counts + promoted lengths identical; ported certifier 20/20 agreement with production at d3 |
