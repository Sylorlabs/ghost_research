# Auto-curriculum — can bulk parallel proposal discover the stepping stone? (round 2026-07-10d headline)
> **Belongs to: Round 2026-07-10d · experiment 5 of 6 (auto-discover curriculum)** — [round index](../../../docs/research/research_round_2026_07_10d.md).

**Status:** built, measured. Reproduce (each bulk/seed pair as its own
invocation — combining both seeds in one call, as `inv_wall.zig` does, would
push the bulk=1000 case past the 15-minute-per-run cap; see "Compute budget"
below):
```bash
cd wcore && zig build-exe -O ReleaseFast src/auto_curriculum.zig -femit-bin=bin/auto_curriculum
./bin/auto_curriculum selftest
for bulk in 0 50 300 1000; do
  for seed in 0xA70F 0x5EED2; do
    ./bin/auto_curriculum run $bulk ../results/auto_curriculum_2026_07_10.csv $seed
  done
done
```
Single-threaded, deterministic per (bulk, seed). Each invocation ran
5m22s–10m27s (see the headline table below); CSV opens in append mode so all
runs share one results file.

## The hypothesis under test

Round c (`conjunction_wall.md`) crossed the distinct-count conjunction wall
(frontier reach 0/9 → 6/9) but **only with a hand-designed two-rung curriculum**
(S1 "membership" → S2 "noveltyflag" → distinct), written by a human who already
knew the target mechanism. Round c named auto-discovering that decomposition —
without being told which sub-conjunction has gradient and composes to the
target — "the next frontier."

This experiment tests the user's standing hypothesis ("pump more out at once")
against exactly that frontier: **can bulk parallel proposal discover a working
stepping-stone decomposition with zero human-given stones?** If bulk
substitutes for the missing auto-discovery capability, more candidates per
round should eventually surface a promotable stone. If it cannot, that sharply
bounds what "pump more" can do — a crucial finding either way.

## Design

### The auto-decomposition loop (mechanism-blind, no membership/noveltyflag given)

Every round:

1. **GENERATE** (bulk, parallel in the "many candidates per round" sense):
   - **Source A — pure random**: `bulk` fresh uniformly-random short programs
     (`alien.randProg`, the same unbiased proposer every arm in this arc
     uses — no load/store bias, no hint that memory ops matter).
   - **Source B — archive prefixes**: the ordinary novelty+residual forge
     search (`familySearch`, ported verbatim from `inv_wall.zig`'s ctrl arm)
     runs as usual against the unsolved wall family; every archive member's
     `.step` instruction sequence is truncated at **every** cut point
     (`stepPrefix`), producing one candidate per cut. Prefixing is a fully
     generic operation on any straight-line program — it does not know
     distinct-count is a 5-instruction chain, it just tries every prefix of
     whatever the ordinary, unaimed search happened to find.
2. **FILTER**, cost-ordered (cheapest first) so the expensive check only ever
   runs on the rare survivors, not on the full bulk pool:
   - **(a) CLIMBABLE/CERTIFIABLE** — not reducible from the current atom
     library at the production certifier depth (3), *and* not reducible at
     the settled +1-depth promotion gate (4). This is literally "would
     `aimed_promote` be willing to promote this" — the same bar every other
     arm in this arc uses. No entropy/clean prefilter: the payoff test below
     is strictly stronger and more relevant, and a real clean filter would
     (per `inv_wall.zig` selftest #6) reject the whole saturating-counter
     family, including the hand stones themselves.
   - **(b) PAYOFF** — hypothetically append the candidate to the library and
     re-run the real reachability check (`targetSolvable`, depth ≤ 3) against
     every currently-unsolved member of the **wall family** (distinct-count +
     its 6 hidden compositions, `WALL_IDX`, identical to `inv_wall.zig`). Kept
     only if ≥ 1 newly composable.
3. **PROMOTE** the best surviving candidate (highest payoff, ties → shorter)
   for real — this is what "auto-discovered" would mean. If **no** candidate
   survives both filters, fall back to the plain ctrl-arm promotion (same
   archive, same census, same gate-polish) so the library still grows every
   round. **This makes the auto-loop a strict superset of ctrl**: if bulk
   discovery never fires, frontier reach must equal ctrl's 0/9 exactly — a
   built-in falsifiability check on the implementation itself (confirmed
   below, every run).
4. **Sweep bulk** (`{0, 50, 300, 1000}` random candidates/round, both seeds)
   to find whether there is a quantity threshold where discovery becomes
   reliable, or whether it never triggers.

### Genuineness instrument (verification-only, never used in the search)

`membershipProg`/`noveltyFlagProg` (S1/S2 from round c) are ported into this
file **only** to (a) sanity-check the certify/payoff pipeline before trusting
it, and (b) report a discovered stone's behavioural agreement with the known
stones after the fact. They are never consulted by the candidate generator,
the certify test, or the payoff test — the search cannot see them and cannot
be steered toward them.

## Instrument fidelity (`selftest`, all as expected)

```
stepPrefix(noveltyFlagProg,2) == membership reference: PASS
stepPrefix(distinctCountProg,2/3) constant-zero on OUT_R: k=2 constant-0 (as expected)  k=3 constant-0 (as expected)
baseline WALL reachability (base atoms only) = 0/7 (expect 0)
membership(S1):  certifiable=yes  payoff=0/7  -- necessary but insufficient
noveltyflag(S2): certifiable=yes  payoff=6/7  -- the sufficient stone
genuineness(noveltyflag): agree_s1=0.000 (expect ~0.000) agree_s2=1.000 (expect 1.000, it IS s2)
agreeDistinct(distinctCountProg) = 1.000 (expect 1.000)
```

Two things worth separating:

1. **A genuine wrinkle found while building the instrument, not asserted up
   front**: the *real* hidden mechanism (`coevo.distinctCountProg`) does
   **not** route through the output register (`r3`/OUT_R) until its very
   last instruction — it accumulates through `r8` (seen-flag) and `r7`
   (running count), only `mov`-ing to `r3` at the end. So naively prefixing
   the *exact* hidden program does **not** reveal S1/S2; every proper prefix
   of it is constant-zero on OUT_R. The hand-designed S1/S2 route through
   `r3` directly at every step by construction. Prefixing is therefore not a
   free lunch even in principle — it only surfaces a useful stone from a
   candidate that happens to wire an *early* instruction straight to the
   output register, which is a real, additional bottleneck for discovery
   beyond "contains the right instructions in the right order."
2. **A positive control that the detection apparatus itself works**: run
   directly against the hand stones (never through the search), the
   certify+payoff pipeline reproduces round c's exact finding from scratch —
   membership passes certify but scores payoff **0/7** (necessary,
   insufficient — matches the "S1/S2 are behavioural complements, agreement
   0.000" trap round c measured), while noveltyflag passes certify **and**
   scores payoff **6/7** (the sufficient stone). If the bulk generator ever
   produced a program behaviourally close to noveltyflag, this pipeline
   would recognize and promote it. The question the sweep answers is
   whether the generator ever gets there.

## Results

### Headline table — frontier reach vs round c's hand-curriculum

| arm | seed | F reach /9 | E reach /9 | total candidate-behaviours tested | stones auto-discovered | wall-clock |
|---|---|---|---|---|---|---|
| round c **ctrl** (reference, hand-stone-free, no bulk layer) | 0xA70F | **0** | 4 | — | — | — |
| round c **ctrl** (reference) | 0x5EED2 | **0** | 5 | — | — | — |
| round c **curr** (reference, hand-designed S1→S2 stones) | 0xA70F | **6** | 4 | — | — | — |
| round c **curr** (reference, hand-designed S1→S2 stones) | 0x5EED2 | **6** | 4 | — | — | — |
| auto, bulk=0 (archive-prefixes only, no extra random draws) | 0xA70F | **0** | 4 | 3,882 | 0 | 5m46s |
| auto, bulk=0 | 0x5EED2 | **0** | 5 | 2,976 | 0 | 5m22s |
| auto, bulk=50 | 0xA70F | **0** | 4 | 4,382 | 0 | 5m36s |
| auto, bulk=50 | 0x5EED2 | **0** | 5 | 3,476 | 0 | 5m41s |
| auto, bulk=300 | 0xA70F | **0** | 4 | 6,882 | 0 | 6m47s |
| auto, bulk=300 | 0x5EED2 | **0** | 5 | 5,976 | 0 | 6m01s |
| auto, bulk=1000 | 0xA70F | **0** | 4 | 13,882 | 0 | 10m27s |
| auto, bulk=1000 | 0x5EED2 | **0** | 5 | 12,976 | 0 | 8m13s |

(round c's ctrl/curr numbers are the published reference from `conjunction_wall.md` /
`results/conj_wall_2026_07_10.csv`, reproduced here for comparison, not re-run.)

**Every single round of every single (bulk, seed) combination reports
`n_d3` candidates surviving the cheap depth-3 filter, but `n_payoff_pos = 0`
and `n_certified = 0` — zero candidates, across the entire sweep, ever showed
nonzero payoff.** Verified directly against the raw CSV:
```
tail -n +2 results/auto_curriculum_2026_07_10.csv | awk -F, '$6>0 || $7>0 {print}'
```
returns **no rows**. Frontier reach for every auto-loop run matches round c's
ctrl arm exactly (F=0/9, same E-transfer trajectory 3→4 or 3→5 depending on
seed) — confirming the built-in falsifiability check: since bulk discovery
never fired even once, the auto-loop degenerates to ctrl's own mechanism every
round, and the measured frontier reach shows exactly that.

### Bulk-needed threshold

There is no threshold within the tested range. `bulk ∈ {0, 50, 300, 1000}`
(random candidates/round; combined with the archive-prefix source this
reaches **13,882 total candidate-behaviours evaluated in the largest single
10-round run** (bulk=1000, seed 0xA70F), **54,432 across the whole 8-run
sweep**) never produced a single candidate with nonzero payoff — verified
directly against the raw CSV (the `awk` check above returns zero rows across
all 8 runs). Increasing bulk 20x (50 → 1000 random candidates/round) changed
the *cost* of each round (10–18s → up to 77s per round as the library and
pool grew) but did not change the *outcome* — F stayed at 0/9 and
`n_payoff_pos` stayed at 0 identically at every scale tested, on both seeds.
The honest reading is not "the threshold is higher than 1000, keep going" but
"bulk alone shows no sign of approaching a threshold in this regime" — see
Verdict.

### Compute budget (why the sweep tops out at bulk=1000, not higher)

The dominant per-candidate cost is the depth-3/depth-4 irreducibility check
(`forge.reducibleLib`), which is `O(library_size^depth)`. Early timing showed
this scales badly enough that a naive bulk=2000 round at library size ~15
would cost multiple minutes *per candidate* if depth-4 were checked
unconditionally on the whole pool. Two changes made the sweep tractable
within the 15-minute-per-run cap:
1. **Reordered the filter pipeline** (cheap depth-3 check → payoff test →
   expensive depth-4 check *only* on payoff-positive survivors), which are
   empirically rare-to-nonexistent, so the O(n^4) cost is paid a handful of
   times per round instead of `bulk` times.
2. **Reduced the ported gate-polish budget** (`POLISH_CHAINS` 8→4,
   `POLISH_NEIGH`/`POLISH_GREEDY` 15,000→3,000 each) used only in the
   ctrl-equivalent fallback path. This does not touch the discovery
   mechanism itself (gate-polish never runs when a stone is found) and does
   not appear to have weakened the fallback's fidelity to round c's ctrl —
   every auto-loop run's F/E reach matches ctrl's own published numbers
   exactly, which is the sanity check this reduction had to pass.

With both changes, `bulk=1000` completed 10 rounds in **8m13s** (seed
0x5EED2) and **10m27s** (seed 0xA70F) — both comfortably under the 15-minute
cap, with the smaller-bulk runs (0/50/300) all finishing in 5–7 minutes. Both
seeds were run as separate invocations (rather than one call covering both,
as round c's arms did) purely to keep each individual run short and
independently timed; this is a scheduling choice, not a budget cut.

## Genuineness

Not applicable in the direct sense — no stone was discovered, so there is
nothing to check for disguise. The relevant genuineness question this
experiment *can* answer is the inverse one: **is the failure to discover a
failure of the detection apparatus, or of the generator?** The selftest
positive control settles this: run directly against the true noveltyflag
program, the certify+payoff pipeline correctly flags it as certifiable
*and* payoff-positive (6/7). The apparatus recognizes the answer on contact.
The bottleneck is squarely upstream, in generation: neither pure-random
short programs nor prefixes harvested from an unaimed novelty+residual
archive, at up to ~13,000 evaluated behaviours per run, ever produced a
program whose early instructions read a persistent per-symbol memory cell
into the visible output register — the one structural feature every useful
stone in this family needs.

## Verdict

**Bulk parallel proposal cannot find the decomposition; the human insight is
still required.** Sweeping four bulk levels from 0 to 1000 random
candidates/round (**54,432 candidate-behaviours evaluated in
total** across the 8-run sweep, all mechanism-blind, all screened by a
strictly stronger payoff-based test than any prior arm in this arc used)
produced **zero** discovered stepping stones and **zero** frontier-reach lift
over the hand-stone-free control, on both seeds, at every bulk level.

Round c's curriculum crossed 0/9 → 6/9 the moment a human-designed
sub-conjunction (noveltyflag) was handed to the forge as a climbing target;
this experiment shows that without that hand, the forge does not stumble
onto an equivalent sub-conjunction even with three orders of magnitude more
candidates thrown at each round (a single candidate vs. up to ~1,400
per round at bulk=1000) than a plain population-based search normally
generates, and even when the promotion criterion is the *strongest* one
tried in this arc so far (proven payoff, not a proxy).

This sharply bounds "pump more out at once" as an escape from missing
auto-discovery: quantity substitutes for insight only insofar as the insight
happens to be *cheap to stumble into* by construction (as the recombination/
composition escape in earlier rounds of this arc was). Here the required
insight — that a 2-3 instruction seen-flag mechanism, wired to route through
the visible output register early, is the one sub-conjunction with both
gradient and payoff — is not cheap to stumble into: it requires either (a) a
generator biased toward the right structural feature (untested here,
deliberately, to keep this a fair "no human hints" test — see below), or (b)
a genuinely different auto-discovery mechanism than bulk generate-and-filter.

## Honest limitations

- Two candidate sources tried (pure random, archive prefixes); other
  generation strategies — systematic short-program enumeration, crossover/
  recombination between already-promoted atoms, or a generic (not
  distinct-count-specific) bias toward memory ops (`alien.Params.mem_bias`,
  which exists in the substrate and was deliberately **not** used here to
  keep this a fair test of blind bulk) — are untested and could change the
  answer. That the substrate's own proposer already supports a memory-op
  bias lever is itself informative: the honest next experiment is "does a
  *generic* (not target-specific) structural bias combined with bulk cross
  the wall," which is a different, weaker claim than "quantity alone."
- Compute-budget-driven simplifications (reordered filter pipeline, reduced
  gate-polish budget in the fallback path only) were needed to keep every
  run under 15 minutes; both are documented above and validated against
  round c's published ctrl numbers as the fidelity check.
- 2 seeds, one substrate, one battery (18-target held-out set ported
  verbatim from `inv_wall.zig`/`inv_aimed.zig`), one depth budget (payoff at
  depth ≤ 3, certify gate at depth ≤ 4) — same bars every other arm in this
  arc used, for comparability, but untested at other depths.
- "Bulk" here means candidates-per-round, not OS threads — this file runs
  single-threaded throughout (0 threads spawned), respecting the ≤2-thread
  constraint by a wide margin; up to two independent invocations (different
  bulk/seed pairs) were run concurrently as separate OS processes to shorten
  wall-clock time for the sweep, never more.
- Behaviour matching is 0.95 agreement on 8×28 random streams — statistical,
  not exact (same caveat as every other file in this arc).

## Files
- `wcore/src/auto_curriculum.zig` — the experiment (`selftest` / `run <bulk> <csv> [seeds] [--pop=][--gens=][--rounds=]`)
- `results/auto_curriculum_2026_07_10.csv` — every round, every (bulk, seed) combination
