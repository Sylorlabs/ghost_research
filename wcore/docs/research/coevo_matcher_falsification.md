# Coevo matcher falsification — does the 12×32 Claim-C matcher lie the same way?
> **Belongs to: Round 2026-07-11 · experiment E6 of 6 (coevo matcher audit)** — [round index](../../../docs/research/research_round_2026_07_11.md).

**Date:** 2026-07-11 (round 2026-07-11, red-team, instrument-trust lever)
**Runner:** `wcore/src/coevo_matcher_attack.zig` (new standalone file; imports wcore
sources read-only, ports the private stage-genome comparison logic, same
convention as `matcher_attack.zig`/`claimc_attack.zig`)
**Build:** `cd wcore && zig build-exe -O ReleaseFast src/coevo_matcher_attack.zig -femit-bin=bin/coevo_matcher_attack` (Zig 0.14.1)
**Run (4 phases, all ≤2 threads, all well under the 15-min cap):**
```
./bin/coevo_matcher_attack run1     state.bin csv1.csv   # repro 85/86 corpus + A1 + A2   (197 s)
./bin/coevo_matcher_attack run2     state.bin csv2.csv   # A3 + A4 + A5                   (114 s)
./bin/coevo_matcher_attack followup state.bin csv3.csv   # deep-budget push on the 1 census FE (<1 s)
./bin/coevo_matcher_attack ladder2  csv4.csv              # 2-seed exact ladder             (6 s)
cat csv1.csv csv2.csv csv3.csv csv4.csv > results/coevo_matcher_attack_2026_07_11.csv
```
**Data:** `results/coevo_matcher_attack_2026_07_11.csv` (362 rows)

**Culture:** adversarial. Round c (`matcher_falsification.md`) red-teamed the
atomforge-side matcher (8 streams × 28 symbols, chains of atom-Programs) and
found it lies in the false-equal direction (4.2% of a real census). It
explicitly named this file's target — the **coevo-side matcher**
(`inv_coevo.behaviorMatches`: agreement ≥ 0.95 over **12 streams × 32 symbols**,
used by `reducible()`/`reducibleWithBudget`) as **not-yet-attacked**, the
instrument behind the Claim-C **"85/86 breadth corpus"** headline
(`claim_c_breadth.md`, `budget_scan.md`). Prior coevo-side work (I54/I55,
`swarm_i54_i55_behavior_matches.md`) used only naturally-occurring near-misses
(worst wrong-pair agreement 0.64, "ample margin") and never constructed an
adversary or varied the matcher's own stream seed on a real production verdict.
This round does both.

## Headline

**The coevo-side matcher lies in the false-equal direction by the identical
mechanism round c found on the sibling matcher — 7/9 constructed adversaries
(rare-pattern deviators dev_k3…dev_k8 and a horizon bomb tuned to the coevo
window, L=32) fool it at 100% of 500 seeds, each with an exact witness, and
production coevo.reducible() itself certified them "REDUCIBLE" — and a
byte-for-byte reproduction of the real 16-seed / 116-deep-solver / 86-novel /
1-irreducible corpus (self-check 0/116 mismatches against the shipped
instrument) contains 1 real false-equal (0x63, candidate 6, matched to genome
[shift,shift] at true agreement 0.664 on 98,304 symbols).** That false-equal
sits **outside** the specific 86 fingerprint-"novel" solvers that make up the
literal "85/86" headline number (it is fingerprint non-novel), so **the 85/86
number itself is not falsified by this run** — but the same corpus, same
instrument, produced a solver that is **irreducible under exhaustive EXACT
matching to depth 8** (488,880+ genomes fully enumerated, twice, on
independent 32,768-symbol seeds) while the **loose production matcher never
even flags it as suspicious** (it reports "REDUCIBLE" at every depth up to 8,
because it stops at the first — wrong — match at depth 2). Budget-scan-style
remediation (push depth on flagged-irreducible items) cannot catch this class
of leak, because the leak never trips the "irreducible, investigate" alarm in
the first place. Random-background search (20,000 programs) found 0
false-equals at this budget — the leak comes from hand construction and from
the novelty-archive corpus, exactly as round c's own hypothesis predicted, not
from generic random programs. The false-different direction is clean (0/1,200
seed-checks). Seed-flip sweeps show 0/11,500 verdict flips — the false-equal
is **seed-robust**, not seed-lucky. A corrected exact-match protocol (64×256
symbols, 2 independent seeds) is derived; it is **cheaper** than production
(1 ms vs 12 ms, early-exit dominates) and re-running the full corpus under it
leaves the headline numerically unchanged (115/116 either way) through a
coincidental wash — one item migrates reducible→irreducible (the census
false-equal), another resolves irreducible→reducible at depth 5 (the known
historical 0xD00D exception, independently re-confirmed here under exact
matching) — but the **corrected protocol still cannot catch dev_k7/dev_k8**
(deviation rates 4.6e-5 / 1.1e-5): they survive the corrected protocol 23.9%
/ 68.2% of the time even with 2 independent seeds, the same residual blind
spot round c measured on the sibling matcher almost to the digit.

## What was attacked

The production matcher semantics: *a solver's stream behaviour equals a
composed stage-genome iff agreement ≥ 0.95 over 12 random streams × 32 symbols
from a per-call seed* (`inv_coevo.behaviorMatches`, `MATCH_THRESHOLD = 0.95`),
used by `reducible()`/`reducibleWithBudget()` — the certifier behind:

- `claim_c_breadth.md`'s 16-seed / 86-"novel" / 85-reducible / 1-exception
  headline (`scripts/claim_c_breadth.sh` → `wcore-invent irreducible <seed>` →
  `inv_main.zig:alienIrreducible`, which calls `coevo.reducible(&solver, 4,
  tseed)` on every depth≥2 deep solver from the shared `buildDeepArch` §24
  ladder);
- `budget_scan.md`'s resolution of the lone exception at depth 5 (same
  matcher, deeper budget);
- `auditscan`/`matchstress` (I54/I55), which stress-tested it with
  natural near-misses only.

This round builds the *identical* 16-seed corpus from scratch (same
`buildDeepArch` construction, same fingerprint-novelty anchors, same
`base_seed`-derived RNG streams) with a witness-capturing port of the matcher,
then attacks it in both directions, exactly mirroring `matcher_attack.zig`'s
five-attack structure (A1 false-equal, A2 false-different, A3 seed-flip, A4
ROC, A5 corrected re-run), plus two follow-ups (deep-budget push on the
found false-equal; a 2-independent-seed exact ladder).

## 0. Baseline reproduction — exact, and self-checked

The 16-seed corpus (`1 2 7 42 99 1000 0x1111 0xBEEF 0xC0FFEE 0xD00D 0xACE
0x5EED 0xFACE 0x1234 0xABCD 0x9999` — the exact `scripts/claim_c_breadth.sh`
list) was rebuilt from scratch: **116 deep (depth≥2) solvers, 86
fingerprint-"novel", 1 production-irreducible** — an **exact match** to
`claim_c_breadth.md`'s "86 | 1 | 16/16" headline. The witness-capturing port
of `coevo.reducible` agreed with the shipped `inv_coevo.reducible()` on **all
116 checks, 0 mismatches** — the instrument is faithful before it is attacked.

**One documentation-precision correction, found as a side effect:** the
historical prose ("85 of 86... reducible... the lone exception") implicitly
treats the 86 "novel" solvers and the 1 "irreducible" solver as the same
population (1 of the 86). In this exact reproduction they are not: **all 86
fingerprint-novel solvers are production-reducible (86/86 within that
bucket)**; the one production-irreducible solver (`0xD00D`, candidate 7) is
**fingerprint non-novel**. `alienIrreducible`'s own code computes `novel` and
`reducible` as independent tallies over the same solver population, not a
strict subset — the shell script's aggregation (`novel=…; irr=…`) inherited
that independence. This does not change any measured count; it corrects an
implicit assumption in how the two numbers were narrated together.

## 1. FALSE-EQUAL hunt

### 1a. Constructed adversaries: 7/9 fool the production matcher (500/500 seeds)

Same two families as round c (rare-pattern run-length deviators `dev_k`, and a
**horizon bomb**), recalibrated to the coevo window **L=32** (production
atomforge used L=28): the bomb is exact for the first 32 positions of every
stream, then deviates on every position from #33 on — a window the 12×32
protocol structurally cannot see past, at any threshold or seed. All run
against genome `[st_gxor]` (bit-identical to these deviators off-trigger) and
against the **actual production `coevo.reducible()`**:

| adversary | true agreement (98k syms) | production pass rate (500 seeds) | `coevo.reducible()`@d4 says | witness |
|---|---|---|---|---|
| dev_k2 | 0.9536 | 0.708 | irreducible (near-band) | `33`→pos 1: exp 0, got 1 |
| dev_k2or3 | 0.9416 | 0.320 | irreducible (near-band) | `33`→pos 1 |
| dev_k3 | 0.9881 | **1.000** | **REDUCIBLE** | `333`→pos 2: exp 3, got 0 |
| dev_k4 | 0.9970 | **1.000** | **REDUCIBLE** | `3333`→pos 3 |
| dev_k5 | 0.9993 | **1.000** | **REDUCIBLE** | `33333`→pos 4 |
| dev_k6 | 0.99978 | **1.000** | **REDUCIBLE** | `333333`→pos 5 |
| dev_k7 | 0.99996 | **1.000** | **REDUCIBLE** | `3333333`→pos 6 |
| dev_k8 | 0.99999 | **1.000** | **REDUCIBLE** | `33333333`→pos 7 |
| **horizon_bomb** | **0.333** (L=96), **0.125** (L=256) | **1.000** (L=32) | **REDUCIBLE** | 32 zeros→pos 32: exp 0, got 1 |

Every witness is a concrete stream + position where the two behaviours
provably differ. dev_k2/dev_k2or3 straddle the threshold exactly as in round
c — genuine seed-noise, not a leak (see §2 near-band).

### 1b. Random-Program background hunt: 0 false-equals at this budget

20,000 random `alien.Program`s (2 threads, `alien.randProg`), 1,238 "alive"
(non-degenerate). Of these, 79 pass the production budget (`reducible()` at
depth ≤4, checked against the **entire** enumerated 780-genome depth-≤4
stage-genome space) — all 79 are "gray" (true agreement in [0.95, 1) at
1024×96 = 98,304 symbols), **0 false-equals** (true < 0.95). This is a clean
**negative** result and it *differs* from round c, which found 2 false-equals
among 5,803 passing random atomforge pairs (~3.4e-4 rate): at this trial
count/depth, generic random programs essentially never land in the
gray-to-false-equal band on the coevo side. The leak here comes from
hand-construction (§1a) and from the novelty-archive corpus (§1c) — a search
process biased toward unusual conditional behaviour — not from uniform random
programs, exactly as round c's own caveat ("the census samples from a novelty
archive... pushed toward unusual conditional behaviours") predicted.

### 1c. The real 85/86-corpus census: 1/115 reducible verdicts is a false-equal

Every "reducible" verdict actually issued while building the 16-seed corpus
(115 of 116 deep solvers) was re-measured against its own matched genome at
1024×96 = 98,304 symbols:

| class | count | share |
|---|---|---|
| exact (0 mismatches in 98,304 syms) | 114 | 99.13% |
| gray (true agreement in [0.95, 1)) | 0 | 0% |
| **FALSE-EQUAL (true < 0.95)** | **1** | **0.87%** |

The one false-equal: **seed 0x63 (99 decimal), candidate 6** — production
matched it to genome `[shift, shift]`, true agreement **0.6641** on 98,304
symbols (worst single number in the whole census), witness at position 35 on
stream `220112100231231320123300330213332103...` (expected 1, got 3).

**Breakdown by fingerprint-novelty (precisely: does this touch the 85/86
number?):** of the 86 novel+reducible solvers (the literal 85/86 bucket), **0
false-equals**. Of the 29 non-novel deep solvers that were also reducible
(outside the headline count entirely), **1 false-equal** — the one above. **So
the specific 85/86 number is untouched by this census's one false-equal**, but
the *instrument* that produces it has a measured, witnessed leak in the same
corpus, at the same rate order as round c's atomforge-side census (4.2%) —
here 0.87% of 115 (or 1/116 = 0.86% of all deep solvers checked).

## 2. FALSE-DIFFERENT hunt — clean, with the same near-band caveat

12 provably-extensionally-equal syntactic variants (trailing nop / dead
self-move / dead setup constant) of the four reference solvers (g_xor, g_add,
pk_xor, pk_add) vs their own single-stage genome, × 100 stream seeds each =
**1,200 verdicts, 0 below 0.95, minimum observed agreement 1.000000
exactly.** False-different is structurally impossible for exact equality on
this deterministic substrate, confirmed.

Near-band (both sides of 0.95, 2,000 seeds each): dev_k2 (true 0.9536) is
called "equal" by 70.95% of seeds; dev_k2or3 (true 0.9416) is called "equal"
by 31.40% of seeds. Any pair within roughly ±0.015 of the threshold gets a
seed-noise verdict at production sample size — identical shape to round c's
finding on the sibling matcher.

## 3. Seed-flip distribution — the false-equal is seed-robust, not seed-lucky

All 115 real production "reducible" verdicts, re-certified against their own
matched genome across 100 alternative stream seeds each (11,500 jobs, 2
threads): **0 flips** — not a single verdict, including the false-equal
(0x63, cand 6), ever crosses back below 0.95 under a different draw at the
production 12×32 budget. This is the same shape round c found (0/2,000 on the
atomforge side): **the leak is a property of the budget, not of an unlucky
seed** — no re-roll at this sample size would ever have caught it.

The distinct-count kill-test (the true outsider, vs the 5 stage atoms) was
swept across depths 1–8 and many seeds: **0/all flips to "reducible" at any
depth or seed.** Best-approach rises monotonically with depth (0.5625 at d1 →
0.9089 at d8) but never crosses 0.95 — non-vacuity holds, with a margin
(0.9089 vs 0.95, gap 0.041) slightly more comfortable than the atomforge-side
kill-test's 0.008 margin from the depth attack, but still the thinnest axis in
the system.

## 4. Impact on Claim-C — precisely

Two directions, kept explicitly separate (a false-equal — matcher says
"reducible" but truly is not — is the concerning direction, because it can
hide a genuine candidate atom inside the "reducible"/"just recombination"
bucket; a false-different resolving under deeper/exact checking only
*strengthens* "it can't invent," since it means an apparent exception
dissolves into a known composition):

- **Concerning direction (false-equal): 1/115 = 0.87%** of the real production
  "reducible" verdicts in the reproduced corpus are false — genuinely outside
  the 85/86 headline's own 86-novel bucket (0 false-equals there), but inside
  the same corpus and same instrument. **Followed up to depth 8**
  (`followup` mode): under the loose production matcher, this candidate is
  reported "REDUCIBLE via [shift,shift]" at *every* depth budget up to 8,
  because the search stops at the first (wrong) match at depth 2 — it never
  trips an "irreducible, investigate deeper" flag, so **budget-scan-style
  remediation cannot find it** (budget_scan only pushes depth on
  already-flagged-irreducible items). Under the corrected exact-match protocol
  (64×256 symbols, 2 independent seeds), this candidate is **irreducible at
  every depth 5–8, with full exhaustive enumeration completed at each depth**
  (up to 488,880+ genomes at depth 8) — a genuine candidate atom the loose
  matcher was silently hiding. Honest caveat: this solver was accepted into
  the corpus by evolution's own ≥0.95-raw-fitness bar on a *small* sample
  (10 sequences × 32 symbols); it may be an imperfectly-generalizing solver
  rather than a deliberately novel mechanism — "irreducible-to-depth-8
  relative to the 5 stage atoms" is confirmed; "useful"/"a deliberate new
  atom" was not separately tested and is not claimed.
- **Strengthening direction (false-different / depth-artifact resolution):**
  the one production-irreducible solver in the whole corpus (0xD00D, cand 7)
  resolves to **REDUCIBLE at depth 5** (genome `[shift,shift,shift,g_xor,
  g_xor]`) under the **exact**-match corrected protocol — independently
  reproducing `budget_scan.md`'s finding (which used the loose 0.95 protocol
  pushed to DMAX=8) via a completely different, stricter matching rule. This
  is a second, independent confirmation that the lone historical exception is
  a depth artifact, not a real exception.
- **Net headline arithmetic:** production says 115/116 reducible at depth≤4.
  Under the corrected protocol (exact, 64×256, 2 seeds; depth 4 for
  originally-reducible items, depth 5 for the originally-irreducible one):
  **115/116 again** — but the composition changed: one item moved
  reducible→irreducible (the census false-equal) while a different item moved
  irreducible→reducible (the known exception's depth-5 resolution). **The
  numeric coincidence should not be read as "nothing changed"**: a previously
  uncounted, genuinely-irreducible-to-depth-8 solver now exists in the record,
  sitting just outside the specific 85/86-of-86-novel accounting.

## 5. Corrected protocol — derived, and its residual blind spot

Grid over labeled pairs (1,128 natural DIFF pairs + 76 EQ pairs, random
programs vs their production-budget-matched genome or `[st_gxor]`, +
syntactic-equal controls) across streams {12,24,48,64} × symbols
{32,64,128,256} × thresholds {0.95, 0.97, 0.99, exact}: **every cell measured
FE = 0.000000** — natural random pairs are too rare at this sample size
(1,128×5 = 5,640 evaluations) to resolve the crossover empirically, an honest
limitation of the ROC-on-natural-pairs method at this budget (mirrors §1b's
low background rate).

The constructed-deviator ladder gives the real answer directly. At **64×256,
exact match, confirmed on a second independent seed** (the direct analogue of
round c's recommended point):

| adversary | true dev-rate | pass@0.95 (L=32, production) | pass@exact (64×256, 1 seed) | pass@exact (64×256, **2 seeds**) |
|---|---|---|---|---|
| dev_k2 | 4.7e-2 | 0.708 | 0.0000 | 0.0000 |
| dev_k3 | 1.2e-2 | 1.000 | 0.0000 | 0.0000 |
| dev_k4 | 2.9e-3 | 1.000 | 0.0000 | 0.0000 |
| dev_k5 | 7.3e-4 | 1.000 | 0.0000 | 0.0000 |
| dev_k6 | 1.8e-4 | 1.000 | 0.0500 | **0.0030** |
| dev_k7 | 4.6e-5 | 1.000 | 0.4880 | **0.2390** |
| dev_k8 | 1.1e-5 | 1.000 | 0.8195 | **0.6815** |
| horizon_bomb | (post-32) | 1.000 (L=32) | 0.0000 (L≥128) | 0.0000 |

**Recommended corrected protocol: exact match (threshold 1.0), 64 streams ×
256 symbols, confirmed on 2 independent seeds, with a 32-symbol first-stream
early-exit gate** — the same point round c recommended for the sibling
matcher, and the numbers land within a few points of round c's own table
(dev_k6 0.0030 vs round c's 0.0025; dev_k7 0.2390 vs 0.2330; dev_k8 0.6815 vs
0.7000) — strong evidence this is a substrate-level property of small-sample
statistical matching, not an accident of one matcher's implementation.

**Cost: cheaper than production**, same mechanism as round c (early exit on
first mismatch): one depth-≤4 census of the distinct-count kill-test cost
**12 ms** under production (12×32, 0.95) and **1 ms** under the corrected
exact (64×256, 2-seed) protocol.

**Residual blind spot (stated, not hidden):** dev_k7 (4.6e-5 deviation rate)
and dev_k8 (1.1e-5) still fool the corrected protocol 23.9% and 68.2% of the
time respectively. Any sampling protocol is blind to deviation rates well
below 1/N_total. Behaviour claims from this matcher — corrected or not — must
say "equal on the protocol's sample distribution," never "equal."

## What was NOT attacked (honest list)

- The atomforge-side matcher (8×28, chains of atom-Programs) was already
  attacked in round c (`matcher_falsification.md`) and is not re-touched here.
- The novelty-search/fingerprint side of the certifier (`open.infoDescriptor`,
  `frontier.fpDist`, `NOVELTY_THRESHOLD=0.35`) was reproduced exactly
  (needed for the 85/86-bucket breakdown) but was not itself red-teamed —
  only its interaction with the reducibility matcher (the novel/non-novel
  split in §1c/§4) was measured.
- Whether the one genuine irreducible-to-depth-8 solver found in §4 is
  *useful* (solves some interesting task well) was not tested — only its
  behavioural distinctness from every depth-≤8 composition of the 5 known
  stage atoms was confirmed. It may be a partially-degenerate/imperfectly
  generalizing evolved solver rather than a deliberately novel mechanism;
  this round establishes "not a composition," not "a useful new atom."
- Depth beyond 8 was not pushed for either the kill-test or the found
  false-equal (matches round c's and budget_scan's own depth ceiling; 5^9 ≈
  2M additional genomes per check make a single-machine ≤15-min budget the
  binding constraint).
- The ROC-on-natural-pairs method (§5) could not resolve the FE-crossover
  empirically at the sample size used (1,128 DIFF pairs) — stated as a
  limitation rather than papered over; the deviator ladder was needed to get
  the real answer.
- The A1b random background hunt used depth ≤4 (matching production); it was
  not repeated at depth ≤8, so a background false-equal rate specific to
  deeper searches is not measured.

## Verdict table

| attack | claim attacked | verdict |
|---|---|---|
| constructed deviators k3–k8 | "≥0.95 on 12×32 ⇒ same behaviour" | **BROKEN** — 6/6 pass at 100% of 500 seeds, true agreement up to 0.99999 < 1, all certified "REDUCIBLE" by the actual production `coevo.reducible()`, all with exact witnesses |
| horizon bomb (L=32) | same | **BROKEN, structurally** — 1.000 production pass rate at every seed; true agreement 0.333 (L=96) / 0.125 (L=256); the protocol cannot observe behaviour past symbol 32 at any threshold/seed |
| random-background hunt | matcher robust for natural programs | **SURVIVED** — 0 false-equals / 79 production-passing pairs among 20,000 random programs (differs from round c's atomforge-side finding of 2/5,803 — the leak here is construction/archive-driven, not generic) |
| census audit (real 85/86 corpus) | "the 115 production reducible verdicts are real reductions" | **1/115 = 0.87% FALSE** (true 0.664), witnessed, in the shipped-equivalent 16-seed corpus; **0/86 inside the specific novel bucket** — the literal 85/86 number stands, the broader instrument does not |
| deep-budget followup on the census FE | "budget-scan-style remediation would catch this" | **REFUTED** — loose matcher reports REDUCIBLE at every depth 1–8 (never flags suspicion); corrected exact match confirms IRREDUCIBLE at depths 5–8 with full enumeration completed |
| false-different | "equal programs can score < 0.95" | **SURVIVED** — 0/1,200; structurally impossible for exact equality; near-band (±0.015) is seed-noise, quantified |
| seed-flip on 115 reducible verdicts | "verdicts are seed-robust" | **CONFIRMED, including the leak** — 0/11,500 flips; the false-equal is seed-robust, not seed-lucky |
| kill-test margins across depths/seeds | "non-vacuous" | **SURVIVED** — 0 flips at any depth 1–8 or seed tested; best-approach rises to 0.9089 at d8, never crosses 0.95 |
| corrected protocol | derive (thr, streams, symbols) closing the leak | **exact / 64 / 256 × 2 seeds**: cheaper than production (1 ms vs 12 ms); catches dev_k2–k6 and the horizon bomb; dev_k7/dev_k8 (≤4.6e-5 deviation rate) still survive 24%/68% of the time — the honest residual |
| headline re-run under corrected protocol | "85/86 (86-novel-bucket accounting) stands" | **STANDS** — 0 false-equals inside the 86-novel bucket; the corpus-wide reducible count is numerically unchanged (115/116) via an unrelated one-for-one wash (census FE migrates out, known exception resolves in) |
