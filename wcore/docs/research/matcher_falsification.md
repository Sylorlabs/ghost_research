# Matcher falsification — can the 0.95/8×28 statistical matcher be made to lie?

**Date:** 2026-07-10 (round 2026-07-10c, red-team)
**Runner:** `wcore/src/matcher_attack.zig` (new standalone file; imports wcore sources
read-only, ports the private chain helpers, same convention as `claimc_attack.zig`)
**Build:** `cd wcore && zig build-exe -O ReleaseFast src/matcher_attack.zig -femit-bin=bin/matcher_attack` (Zig 0.14.1)
**Run:** two phases sharing a serialized state file (the reproduced a1a6 artifact),
so run2 attacks the exact same 20 promoted atoms + census run1 built:
```
./bin/matcher_attack run1 state.bin csv_run1.csv   # repro + A1 (false-equal) + A2 (false-different), 52 s
./bin/matcher_attack run2 state.bin csv_run2.csv   # A3 seed-flips + A4 ROC + A5 corrected verdicts, 523 s
cat csv_run1.csv csv_run2.csv > results/matcher_attack_2026_07_10.csv
```
Both ≤ 2 compute threads, each well under the 15-minute cap. (Optional `run3` skips
the A3 sweep, `run4` skips A3+A4 — resume helpers if a phase is interrupted.)
**Data:** `results/matcher_attack_2026_07_10.csv` (215 rows)

**Culture:** adversarial. The depth attack (`claimc_depth_attack.md`) left one named
axis un-attacked: the certifier's *matcher* — `behaviorMatches`-style agreement
`≥ 0.95` measured on `8 streams × 28 symbols` with a **fixed** seed
(`inv_atomforge.matchesChain`, used by `reducibleLib`, which certifies every
atom-forge promotion). The kill-test had passed by 0.008. This round attacks the
matcher directly, in both directions.

## Headline

**The matcher lies, in the false-equal direction, and not only in corner cases: it
is structurally blind past its 28-symbol horizon, certifies provably-different
programs as "the same behaviour" (all 9 constructed adversaries certified reducible
by the production certifier — 7 of them, dev_k3–k8 + horizon_bomb, at 100% of 500
stream seeds; the two threshold-straddling ones at 38–69% — each with an exact
disagreement witness), and 8/189 = 4.2% of the real a1a6 census "reducible"
verdicts are false-equals (worst true agreement 0.32).**
The false-different direction is clean (0/90,000). The 20 promoted-atom
irreducibility verdicts themselves are seed-robust (0 flips across 20 atoms × 100
stream seeds at production depth 3; the only depth-4 flips are the known inv8 real
reduction, which holds at 100% of seeds). An exact-match protocol (threshold 1.0,
64×256 symbols, 2 independent seeds, with a 32-symbol early-exit gate) drives the
measured false-equal rate to **0** on 2,489 labeled pairs while keeping true-equal
detection at **1.0000**, catches every constructed adversary down to deviation
rate ~1.8e-4, and is **cheaper than the production protocol** (13 ms vs 70 ms for
one depth-4 census, thanks to first-mismatch early exit). Under it, **14/189
census verdicts migrate reducible→irreducible but promotion identity is unchanged
in 0/20 rounds — every a1a6 promotion stands, and the depth-attack inv8 flip
([5,9,6,0]) stands (exact on 2×16384 symbols).**

## What was attacked

The production matcher semantics: *program P ≡ chain C iff agreement ≥ 0.95 over
8 random streams × 28 symbols drawn from a fixed PRNG seed* (`fseed = seed+0xA70F`),
inside `inv_atomforge.reducibleLib` (depth-3 census + promotion gate for the a1a6
open-atom program) — plus, by re-use, everything downstream of that instrument:
census verdicts, promotions, kill-tests, `dropAblation`, `greedyMinimal`,
`coveragePreserved`.

Prior instrument work this extends (and where it stopped):

- **I54/I55 (`swarm_i54_i55_behavior_matches.md`)** stress-tested the *coevo-side*
  matcher with naturally-occurring near-misses: worst wrong-pair agreement 0.64,
  "ample margin below 0.95", verdict-stable 32→4096 symbols. It never constructed
  adversaries and never varied the stream seed of production verdicts.
- **claimc depth attack** measured a 0.9420 closest adversarial approach at depth 8
  and named the matcher as the thinnest axis, without attacking it.

This round shows the I54/I55 conclusion ("trustworthy") does not survive
adversarial inputs: the 0.31-point margin exists only for *natural* near-misses.

## 0. Baseline reproduction — exact, again

The a1a6 promotion loop was re-run from scratch for both seeds (0xA70F, 0x5EED2):
same counts every round, same 20 promoted-atom lengths, libraries 5→15. The
witness-capturing port of the certifier agreed with production `forge.reducibleLib`
on **all 1,479 census verdicts** (705 + 774) — the instrument is faithful before it
is abused. State (atoms + full census) serialized so run2 attacks the *same*
artifact.

## 1. FALSE-EQUAL hunt — the matcher's lying direction

### 1a. Constructed adversaries: 9/9 fool the production matcher

Family 1 — **rare-pattern deviators** `dev_k`: compute g_xor exactly, but output
+1 (mod 4) at exactly the positions where the run of consecutive symbol-3s reaches
length k. True disagreement rate ≈ (3/4)·4⁻ᵏ per position. Family 2 — the
**horizon bomb**: compute g_xor exactly for the first 28 positions of every
stream, then deviate on *every* position from #29 on (a 3-instruction latch).

All are `clean()` by the forge's own gate and all were run against the production
certifier itself (`reducibleLib`, depth 3, base-5 library):

| adversary | true agreement (98k syms) | production pass rate (500 seeds) | certified "reducible" by production `reducibleLib`? | disagreement witness |
|---|---|---|---|---|
| dev_k2 | 0.9536 | 0.690 | YES | `33` → pos 1: exp 0, got 1 |
| dev_k2or3 | 0.9416 | 0.378 | YES | `33` → pos 1 |
| dev_k3 | 0.9881 | **1.000** | YES | `333` → pos 2: exp 3, got 0 |
| dev_k4 | 0.9970 | **1.000** | YES | `3333` → pos 3 |
| dev_k5 | 0.9993 | **1.000** | YES | `33333` → pos 4 |
| dev_k6 | 0.99978 | **1.000** | YES | `333333` → pos 5 |
| dev_k7 | 0.99996 | **1.000** | YES | `3333333` → pos 6 |
| dev_k8 | 0.99999 | **1.000** | YES | `33333333` → pos 7 |
| **horizon_bomb** | **0.109** (L=256) | **1.000** | YES | 29 zeros → pos 28: exp 0, got 1 |

Every witness is a concrete input stream on which the two programs' outputs
provably differ (verified by direct execution; the tables' rates were confirmed
against the binomial model to 3 decimal places).

Two structurally different lies:

1. **Threshold lie (dev_k3…k8):** any deviation rarer than ~5% per position passes
   *at every stream seed*. This is not seed luck — no protocol at threshold 0.95
   can see these. A program that is g_xor except on 1-in-10⁵ inputs is certified
   as *equal to g_xor* and (production consequence) **rejected from promotion as
   "reducible" even though it is a genuinely different function.**
2. **Horizon lie (horizon_bomb):** the production matcher's streams are 28 symbols
   long, so behaviour past position 28 is *unobservable*. The bomb scores a perfect
   1.000 agreement at **every** one of 500 seeds while agreeing with g_xor on only
   10.9% of symbols on length-256 streams. No threshold, stream count, or seed
   fixes this — only longer streams do. All wcore behaviour claims are therefore
   claims about the first 28 positions only.

### 1b. Random search: natural false-equals exist and were found

120,000 random program pairs (P, mutant of P), production-matched at the real
production fseed: 5,803 pairs pass. Of these, **2 are false-equals** (true
agreement < 0.95 on 98k symbols; both with independently-generated witnesses):

- `fe_pair_0`: production score **1.0000**, true agreement **0.3333** — a natural
  horizon-bomb/rare-trigger analogue found in 120k random draws; witness stream
  `1232110001221202223120123020122 23` disagrees at pos 32 (exp 3, got 0).
- `fe_pair_1`: production 0.9688, true 0.9267 — a threshold-adjacent leak.

Rate: ~3.4e-4 of production-passing random pairs are false-equals (and 21 more in
the gray band [0.95, 1)). Rare among *random* programs — but the census samples
from a novelty archive, which is *pushed toward* unusual conditional behaviours.

### 1c. The production census itself: 8/189 reducible verdicts are false-equals

Every "reducible" verdict the production loop actually issued during the 20
promotions (189 of 1,479 census checks) was re-measured against its own matched
chain on 98k symbols:

| class | count | share |
|---|---|---|
| exact (0 mismatches in 98k) | 176 | 93.1% |
| gray (true agreement in [0.95, 1)) | 5 | 2.6% |
| **FALSE-EQUAL (true < 0.95)** | **8** | **4.2%** |

The 8 false-equals (all witnessed, full streams in the CSV):

| census verdict | matched chain | true agreement |
|---|---|---|
| 0xA70F r6 c52 | [7,7] | 0.888 |
| 0xA70F r6 c60 | [7,7] | 0.910 |
| 0xA70F r8 c50/c51/c58/c60 | [11,5] | **0.428** (all four) |
| 0x5EED2 r5 c65 | [7] | 0.664 |
| 0x5EED2 r9 c34 | [5,9,6] | **0.323** |

A production score ≥ 0.95 cannot reach a true rate of 0.32–0.43 by binomial
noise on 224 symbols — these are **content-conditional divergences the fixed
fseed streams never trigger** (natural rare-pattern/horizon cases, found in the
production artifact, not constructed). Production consequence: these candidates
were *discarded as compositions* when they are provably not — i.e., the known
leak direction is not only "false atom admitted" (the depth attack's inv8) but
also **"real candidate wrongly rejected"**. Promotion *identity* — which atom got
promoted each round — rests on these verdicts (quantified in §5).

## 2. FALSE-DIFFERENT hunt — the safe direction, confirmed and bounded

The matcher compares both programs on the *same* generated streams and the
substrate is total and deterministic, so an extensionally-equal pair scores
agreement 1.0 identically — a false-different is structurally impossible for
exact equality. Measured: 900 provably-equal syntactic variants (appended nop /
dead self-move / dead setup constant; each verified mismatch-free on 32k symbols)
× 100 stream seeds = **0/90,000 verdicts below 0.95; minimum observed agreement
1.000000 exactly.**

The honest boundary of that safety: pairs whose TRUE agreement sits near 0.95 get
**seed-noise verdicts**, not answers. dev_k2 (true 0.9536 — "equal" under the
certifier's own ≥0.95 semantics) is called *different* by 32.1% of stream seeds;
dev_k2or3 (true 0.9416 — "different") is called *equal* by 38.7%. Both match the
binomial-sampling model (0.65/0.34 predicted). Any pair within ~±0.015 of the
threshold is decided by seed luck at the production sample size.

## 3. Seed-flip distribution on the production verdicts

The 20 promoted atoms (vs their promotion-time prefix, the certified verdict) and
the distinct-count kill-test were re-certified across many stream seeds (seed
index 0 = the production fseed):

| group | seeds | verdict flips | best-agreement range (min…max over seeds) |
|---|---|---|---|
| 20 atoms × depth-3 (production verdict) | 100 each | **0 / 2000** | 0.31 … 0.84 |
| 20 atoms × depth-4 | 16 each | 16 / 320 — **all one atom** (0x5EED2 inv8) | that atom 1.000 at every seed; other 19 ≤ 0.83 |
| dc kill vs base-5, depth 3…8 | 16–100 each | **0** at every depth | best approach rises 0.82→0.9375 with depth, never ≥ 0.95 |
| dc kill vs 15-atom finals, depth 3–4 | 16–100 each | **0** | ≤ 0.866 |

**Not a single production depth-3 verdict flips across 100 alternative stream
draws** — the 0.008 kill-test margin from the depth attack was a property of the
*aggregate closest-approach over an enormous search*, not of any individual
verdict. Every atom's own best-approaching chain sits 0.16–0.64 below threshold and
stays there across seeds; these verdicts are decided, not teetering. The only
seed-independent flips are the 16 depth-4 hits on 0x5EED2 inv8 — and they flip at
*100% of seeds* because the [5,9,6,0] chain is a genuine reduction (true agreement
1.0000), i.e. the depth-attack leak is real and seed-robust, not a lucky draw.

The kill-test's rising best-approach with depth (0.82 at d3 → 0.9375 at d8) is the
matcher's thin-margin axis restated: at d8 over base-5, *some* 8-chain gets within
0.0625 of distinct-count on 224 symbols — but 0/16 ever cross, at any of the seeds.
The margin is real but the verdict is stable.

Known witness chains re-checked across 100 seeds: the depth-attack flip
`inv8_prefix_d4 [5,9,6,0]` and the two redundancy witnesses `inv0_minus_self
[5,9,10]` / `inv5_minus_self [10,5,11]` each pass **100/100** seeds with agreement
min=max=1.0000 and are exact on 64×256 = 16,384 independent symbols. These
reductions are seed-independent facts.

## 4. Corrected protocol — empirical ROC and cost

Labeled pairs: 2,200 natural mutant pairs (98k-symbol ground truth: DIFF = true
< 0.95, GRAY = [0.95,1), EQ0 = zero mismatches in 98k) + 300 provably-equal
syntactic pairs (EQSYN) + the constructed ladder. Protocol grid: streams
{8,16,32,64} × symbols {28,64,128} × thresholds {0.95, 0.97, 0.99, exact}, 5
eval-seeds per cell.

Labeled: DIFF=470, GRAY=11, EQ0=1719, EQSYN=300 (×5 eval seeds each). Selected
cells (full grid in the CSV, `A4_roc` rows):

| protocol cell | threshold | FALSE-EQUAL rate (DIFF pass) | true-equal detect (EQ0 / EQSYN) |
|---|---|---|---|
| **8 × 28** (production) | 0.95 | **1.28e-3** | 1.0000 / 1.0000 |
| 64 × 28 | 0.95 | 8.5e-4 | 1.0000 / 1.0000 |
| 64 × 64 | 0.95 | 0 (of these pairs) | 1.0000 / 1.0000 |
| **any cell** | **exact (1.0)** | **0.000000** | **1.0000 / 1.0000** |

The exact-match threshold zeroes the false-equal rate on labeled pairs at *every*
sample size while leaving true-equal detection at 1.0000 — the ROC target
(FE < 1e-3, true-equal > 0.99) is met with margin. Raising the *fractional*
threshold helps sub-linearly (0.95→exact is the real lever, not 0.95→0.99). GRAY
pairs (true agreement in [0.95,1)) are correctly rejected by exact match — they are
genuinely different functions the loose matcher was calling equal.

Deviator ladder at exact match (single 64×256 seed, 2,000 stream seeds):

| adversary | true dev-rate | pass@0.95 (L=256) | pass@exact (64×256, 1 seed) | pass@exact (64×256, **2 seeds**) |
|---|---|---|---|---|
| dev_k2 | 4.7e-2 | 0.988 | 0.0000 | 0.0000 |
| dev_k3 | 1.2e-2 | 1.000 | 0.0000 | 0.0000 |
| dev_k4 | 2.9e-3 | 1.000 | 0.0000 | 0.0000 |
| dev_k5 | 7.3e-4 | 1.000 | 0.0000 | 0.0000 |
| dev_k6 | 1.8e-4 | 1.000 | 0.0650 | **0.0025** |
| dev_k7 | 4.6e-5 | 1.000 | 0.4825 | **0.2330** |
| dev_k8 | 1.1e-5 | 1.000 | 0.8365 | **0.7000** |
| horizon_bomb | (post-28) | **0.0000** | 0.0000 | 0.0000 |

**Recommended protocol: exact match (threshold 1.0, zero mismatches), 64 streams ×
256 symbols, confirmed on 2 independent seeds, with a 32-symbol first-stream
early-exit gate.** L=256 ≫ 28 closes the horizon lie (the bomb is caught even at
0.95 once L>28); exact match closes the threshold lie down to ~1/16384 per-symbol
deviation; the second seed squares the residual leak (dev_k6 0.065→0.0025). This
is the (threshold, streams, symbols) = (1.0, 64, 256)×2 point where false-equal
rate drops below 1e-3 and true-equal detection stays > 0.99.

**Cost: cheaper than production.** One depth-≤4 census of the inv8 atom against its
13-atom prefix cost **70 ms** under production (8×28, 0.95) and **13 ms** under the
corrected exact (64×256, 2-seed) protocol — the ~19× larger nominal sample is more
than offset by first-mismatch early exit: a non-matching chain is abandoned after
~32 symbols instead of consuming all 224. Whole-round corrected census of a
14-atom library is seconds, not minutes.

Residual blind spot (stated, not hidden): any sampling protocol with N symbols is
blind to deviation rates ≲ 1/N. The recommended protocol (32k symbols across 2
seeds) reliably catches rates ≥ ~2e-4 (dev_k6, caught 99.75%) and misses rarer:
dev_k7 (4.6e-5) survives 23% of the time, dev_k8 (1.1e-5) survives 70%. Catching
arbitrarily-rare divergence requires exhaustive/symbolic equivalence, which does
not exist for this substrate. Behaviour claims must therefore say "equal on the
protocol distribution (32k symbols)", never "equal".

## 5. Headline verdicts under the corrected protocol

Every headline re-run under exact 64×256 2-seed matching:

**The 20 promoted atoms.** 19/20 are irreducible at d3, d4 and d5 under the
corrected protocol — identical to production. The single exception is **0x5EED2
inv8**, irreducible at d3 but **REDUCIBLE at d4 and d5** via `[5,9,6,0]`
(= inv0→inv4→inv1→g_xor). This is exactly the depth-attack leak: it is a
*depth* artifact, not a *matcher* artifact — the corrected matcher confirms it at
d4 rather than creating or hiding it. **The depth-attack flip stands** (exact on
2×16384 symbols).

**Promotion identity — the load-bearing question.** Re-running the corrected
matcher over the entire 189-verdict reducible census: **14 verdicts migrate
reducible→irreducible** (the 8 witnessed false-equals plus 6 gray-band cases whose
alternate seed pair happened to disagree). But in **0 / 20 rounds** does the
*promoted* candidate change: the promotion rule takes the first irreducible
candidate in length order, and every migrated verdict either sits after that index
or only *adds* irreducibles — it can never displace the first one. **All 20 a1a6
promotions are unchanged under the corrected matcher.** The a1a6 headline
conclusions (no fixed point, flat lengths, invented-on-invented) rest on
*promotion identity*, which is matcher-robust even though 7.4% of the intermediate
reducible verdicts were wrong.

**Kill-tests.** distinct-count stays irreducible under the corrected protocol:
16/16 complete at exact d≤8 vs base-5; 6/6 at exact d≤5 vs each 15-atom final. The
0.008 production margin does not translate into a single corrected-protocol flip.

**Constructed adversaries.** Under the corrected census, 7/9 are now caught
(dev_k2–k6, horizon_bomb → irreducible); dev_k7 and dev_k8 (deviation rates
4.6e-5 and 1.1e-5) **still fool even the corrected matcher** — the honest residual
that no finite-sample protocol removes.

## What was NOT attacked (honest list)

- The coevo-side instrument (`inv_coevo.reducible` over Stage genomes — the
  85/86 breadth corpus and budget_scan numbers) was not re-run; this round's
  false-equal mechanics (rare-pattern, horizon) apply to its 12×32-symbol
  matcher too, but its claims are mostly in the safe (reducible, witnessed)
  direction. Its kill-test uses the same `distinctCountProg` re-attacked here.
- Depth beyond the production +2 (atoms) / d8 (base-5 kill) was not pushed —
  that axis belongs to the depth attack and was not re-opened.
- The novelty-search side (whether `open.search` archives preferentially contain
  matcher-fooling candidates) was not measured beyond the observation in §1c
  that 8 such candidates reached the census.
- The horizon fix (longer streams) was folded into the corrected protocol; a
  systematic scan of *how much* history the substrate can hide beyond L=256
  (e.g. latches triggered at position 10⁴) was not done — the same construction
  obviously scales, which is exactly why the honest wording must be
  distribution-relative.
- Witness verification is behavioural (direct execution on explicit streams) —
  exact and machine-checked, but per-witness, not a proof of the deviators'
  full truth tables (the deviator constructions make those self-evident).

## Verdict table

| attack | claim attacked | verdict |
|---|---|---|
| constructed deviators k3–k8 | "≥0.95 on 8×28 ⇒ same behaviour" | **BROKEN** — 6/6 pass at 100% of 500 seeds with true agreement up to 0.99999 < 1, all certified "reducible" by production `reducibleLib`, all with exact witnesses |
| horizon bomb | same | **BROKEN, structurally** — perfect 1.000 production score at every seed, true agreement 0.109; the protocol cannot observe behaviour past symbol 28 at any threshold/seed |
| census audit | "the 189 production reducible verdicts are real reductions" | **8/189 = 4.2% FALSE** (worst 0.32), 5 more gray — witnessed, in the shipped a1a6 artifact |
| random-pair hunt | matcher robust for natural programs | **2 false-equals / 5,803 passes** (incl. one at production score 1.0000, true 0.3333) |
| false-different | "equal programs can score < 0.95" | **SURVIVED** — 0/90,000; structurally impossible for exact equality; near-band (±0.015) is seed-noise, quantified |
| seed-flip on 20 promotions | "certified irreducible (depth 3)" | **SURVIVED** — 0/2000 (20 atoms × 100 seeds) flip at d3; the only d4 flip (inv8) is seed-robust at 100% and is a real reduction, not seed luck |
| kill-test margins across seeds | "non-vacuous, closest approach 0.9420" | **SURVIVED** — 0 flips across depths 3–8 and 16–100 seeds each; best-approach rises to 0.9375 at d8 but never crosses 0.95; the aggregate 0.008 margin is not per-verdict fragility |
| corrected protocol | derive (thr, streams, symbols) with FE<1e-3, TE>0.99 | **exact / 64 / 256 ×2 seeds**: FE rate 0 on labeled pairs, TE 1.0000, 13 ms < 70 ms production; a1a6 promotions 20/20 unchanged, depth-attack flip stands; only sub-2e-4 deviators (dev_k7/k8) survive it |
