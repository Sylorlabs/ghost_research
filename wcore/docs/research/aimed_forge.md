# Aimed forge — coupling novelty pressure to the frontier (headline experiment, round 2026-07-10b)

**Date:** 2026-07-10
**Runner:** `wcore/src/inv_aimed.zig` (new standalone file; imports existing wcore
sources read-only, ports the private helpers from `inv_iterate.zig` / `inv_open.zig`)
**Diagnosis probe:** `wcore/src/inv_aimed_probe.zig` (new standalone file, 21 s)
**Build:** `zig build-exe -O ReleaseFast src/inv_aimed.zig -femit-bin=bin/inv_aimed` (Zig 0.14.1)
**Data:** `results/aimed_forge_2026_07_10.csv` (per-arm, per-seed, per-round; 88 rows)
**Runtime:** 9m48s single-threaded, 4 arms x 2 seeds x 10 rounds + retro-audits
**Reproduce:** `./bin/inv_aimed ../results/aimed_forge_2026_07_10.csv 0xA70F 0x5EED2 --pop=90 --gens=45 --rounds=10`

## Question

A1–A6 (`a1a6_iterated_promotion.md`) ended with: "the bottleneck is coupling the
forge's novelty pressure to the frontier you care about." This experiment builds
that coupling and measures whether it works. Headline metric: does an AIMED forge
reach ANY structured-family target (distinct-count / hash-table / union + hidden
compositions) that the unaimed forge never touched in 10 rounds?

**Answer: partially — and the decomposition is the finding.** Aiming the *search*
(novelty/residual blend) fails completely at equal budget. Aiming the *promotion
decision* produces the first structured-family solves ever recorded in this arc
(hashtbl + union, 1 of 2 seeds). The distinct-count family never flips under any
configuration, and the diagnosis probe shows why: its residual landscape is a
conjunction wall, not a climbable gradient.

## Design

### The F/E split (fixed before round 1, disjoint, same 18-target A1–A6 battery)

The 18-target held-out battery, hidden library, and every seed/threshold constant
are IDENTICAL to `inv_iterate.zig`, so results are apples-to-apples with A1–A6.
The battery is partitioned once, before any run:

- **F (FRONTIER, aimed at) — 9 targets:** the distinct-count-centric structured
  family A1–A6 proved the unaimed forge never touches: `distinct`, `hashtbl`,
  `union`, `dist->gxor`, `gadd->dist`, `dist->dist`, `dist->rmw`, `shift->dist`,
  `shift->dist->gxor`.
- **E (EVAL / transfer, never aimed) — 9 targets:** the rmw-centric structured
  family (`rmw`, `xorscan`, `rmw->pkxor`, `pkadd->dist->pkadd`, `rmw->rmw->gadd`,
  `dist->shift->rmw`) plus the three decoy sentinels (`decoy1–3`). No E target's
  behaviour is ever visible to any fitness function. E measures transfer
  (do atoms invented FOR F help a family never aimed at?); the decoys inside E
  keep the A1–A6 forge-re-draws-itself pathology measurable.

Rationale for splitting along the dist-vs-rmw axis: it puts every never-flipped
structured target on the aimed side (the hardest possible F), keeps a structured
family on the eval side for a real transfer measurement, and keeps all three
decoys un-aimed.

### Arms (identical budget: pop 90 x gens 45 x 10 rounds x seeds 0xA70F, 0x5EED2)

| arm | forge selection/admission | promotion policy |
|---|---|---|
| `unaimed` (control) | pure novelty (`open.search`, info descriptor) — exact A1–A6 config, re-run fresh | shortest certified-irreducible |
| `aimed_flat` | combined = 0.5·novelty_norm + 0.5·residual | shortest certified-irreducible |
| `aimed_annealed` | combined, alpha annealed 0 -> 0.85 across each round's 45 gens (novelty early, residual late) | shortest certified-irreducible |
| `aimed_promote` | same forge as `aimed_flat` | **highest-residual** certified-irreducible (ties -> shorter) |

*Residual* = best fractional per-symbol agreement (8 x 28 random streams — the
certifier's own behaviour-comparison primitive) between the raw candidate alone
(depth 1) and each currently-unsolved F target. Promotion in all arms uses the
same depth-3 exhaustive certifier (`forge.reducibleLib`) over the census of the
<=80 shortest clean archive members; reachability re-measurement and the
depth-4/5 retro-audit are verbatim A1–A6 protocol. `aimed_promote` adds <=80
depth-1 residual comparisons per round — negligible next to the census's
exhaustive depth-3 certifications, so all four arms are equal-budget for
practical purposes.

The fourth arm was added mid-experiment because of what the diagnosis probe
found (below): the first three arms all share A1–A6's promotion policy
(shortest irreducible), which turns out to discard exactly the information the
aiming pressure creates.

### Control fidelity

The `unaimed` arm reproduced yesterday's A1–A6 run **exactly** (identical
per-round archive/clean/irreducible counts, promotions, and flips across both
runs of this binary and vs `a1a6_openatom_2026_07_10.csv`; only ms timings
differ). This is a faithful re-run under matched conditions, not a re-quote.

## Results

### Headline table (both seeds; E baseline is 3/9 at round 0, F baseline 0/9)

| arm | seed | **F reached /9** | E reached /9 | flips self/composed | self-rate | leaks | redundant |
|---|---|---|---|---|---|---|---|
| unaimed | 0xA70F | **0** | 7 | 3/1 | 75% | 0/10 | 0/10 |
| unaimed | 0x5EED2 | **0** | 7 | 3/1 | 75% | 1/10 | 3/10 |
| aimed_flat | 0xA70F | **0** | 7 | 0/4 | 0% | 0/10 | 1/10 |
| aimed_flat | 0x5EED2 | **0** | 6 | 1/2 | 33% | 1/10 | 3/10 |
| aimed_annealed | 0xA70F | **0** | 7 | 1/3 | 25% | 0/10 | 1/10 |
| aimed_annealed | 0x5EED2 | **0** | 7 | 2/2 | 50% | 0/10 | 0/10 |
| aimed_promote | 0xA70F | **0** | 7 | 3/1 | 75% | 0/10 | 1/10 |
| aimed_promote | 0x5EED2 | **2** (hashtbl, union) | 7 | 5/1 | 83% | 2/10 | 2/10 |

### The solve (aimed_promote, seed 0x5EED2, round 4)

`hashtbl` and `union` both flip at round 4, witness = the round-4 promoted atom
alone (they share OUT_R behaviour under `runStream`, so they are one behaviour).
The atom (len 12) was promoted *because* it had the highest residual vs the
unsolved F set among that round's 45 certified-irreducible candidates. The
retro-audit holds everywhere for it: irreducible vs its promotion-time prefix at
depth 4 AND 5, non-redundant vs the final library minus itself at depth 3 and 4.
This is the first time in the arc that any structured-family target became
reachable — ten A1–A6 rounds plus thirty aimed-search rounds never touched one.
It is an aimed re-discovery of the hash-table mechanism, found on demand.

Honest characterization: this is a SELF flip — promotion of a found behaviour,
not a composition. The same witness shape that was a *pathology* in A1–A6
(atoms accidentally equal to decoys nobody wanted) is the *success mode* here
(an atom deliberately selected to equal a named frontier target). What changed
is that the re-draw is now directed.

### Aiming the search alone does nothing for F (arms 2–3)

`aimed_flat` and `aimed_annealed` both end at F 0/9 on both seeds — identical to
the control. The pressure demonstrably changes the search: archives shrink
(33–77 vs 57–146 members), the census irreducible fraction falls faster as the
library grows, and the SELF-match rate on flips collapses (75% unaimed -> 14%
flat / 38% annealed) with decoys flipping via composition instead of self-match.
But none of that converts into frontier reach when the promotion gate still
picks the shortest irreducible candidate. Annealing made no meaningful
difference vs flat blending.

### The diagnosis probe (`inv_aimed_probe.zig`) — why, mechanistically

The residual signal itself, characterised (chance agreement at V=4 is 0.25;
match bar 0.95):

| F singleton | random-clean p50 | p90 | p99 | max (5000 samples) | greedy climb (8 x 30k mutations) |
|---|---|---|---|---|---|
| distinct | 0.295 | 0.420 | 0.656 | 0.723 | **0.862 — BELOW the bar** |
| hashtbl | 0.478 | 0.893 | 0.893 | **1.000** | 1.000 — reaches the bar |
| union | 0.478 | 0.893 | 0.893 | **1.000** | 1.000 — reaches the bar |

Nearest known mechanisms: xorscan sits at 0.656 from distinct, pk_xor at 0.545
from hashtbl; everything else <=0.5. The 0.893 shelf is echo-like programs that
match the hash-table's output everywhere except first occurrences. Two failure
modes, cleanly separated:

1. **distinct-count is a residual WALL.** Even undiluted greedy residual
   pressure (240k mutations from the best of 5000 random starts) plateaus at
   0.862 < 0.95. The mechanism (seen-flag store + counter increment + output
   move, 5 coordinated instructions) is a conjunction with no smooth agreement
   path — the same conjunction wall this substrate showed when `fuse` never
   found pk_add in 16M evals. Behavioural proximity is a deceptive gradient
   here; no blend weight fixes that at this budget.
2. **hashtbl/union is CLIMBABLE — the failure was the promotion gate.**
   Residual-1.000 programs exist within a 5000-sample random draw and greedy
   climb finds them reliably. The aimed arms' archives contained F-proximal
   candidates, but the shortest-irreducible promotion policy (A1–A6's) never
   picks them. Arm 4 fixed exactly this and converted the climbable half of F
   into solves on one seed.

The probe also explains two secondary observations: (a) in `aimed_promote` both
seeds promote an xorscan-equivalent atom (xorscan flips SELF) — xorscan is the
residual-closest known behaviour to distinct (0.656), so maximizing residual
toward distinct promotes xorscan-like atoms; (b) round-1 residual-max atoms
match decoy2/decoy3 in both seeds — consistent with those decoys sitting on the
0.893 echo shelf the hashtbl residual rewards (inference from the numbers, not
separately verified).

### E-transfer (the disjoint eval set)

Structured E subset (6 targets, baseline 3): every arm, every seed ends at 4/6 —
the +1 is always xorscan, A1–A6's one genuine generalisation event, reproduced
everywhere. **Aiming at F neither helped nor hurt structured transfer.** The two
E targets containing distinct-count as a hidden component (`pkadd->dist->pkadd`,
`dist->shift->rmw`) never flip in any arm — consistent with the F wall: every
behaviour touching the distinct-count mechanism stays unreachable. Decoys flip
in 5–6 of 6 arm-seed combinations regardless of aiming; only the witness shape
changes (SELF under unaimed, mostly COMPOSED under aimed search).

### SELF-match rate (pooled over both seeds)

| arm | flips | SELF | rate | of which decoy-SELF / aimed-F-SELF |
|---|---|---|---|---|
| unaimed | 8 | 6 | 75% | 6 / 0 (pure pathology) |
| aimed_flat | 7 | 1 | 14% | 0 / 0 (the 1 is xorscan) |
| aimed_annealed | 8 | 3 | 38% | 3 / 0 |
| aimed_promote | 10 | 8 | 80% | 4 / 2 (hashtbl+union — the success) |

Aiming the search *does* fix the re-draws-itself pathology (75% -> 14–38%).
`aimed_promote`'s high rate is a different phenomenon: residual-max promotion
*deliberately* promotes atoms that equal target behaviours, so SELF becomes the
intended mechanism rather than the failure mode. The number to watch is the
decoy-SELF column, which aiming reduces in every variant.

### Retro-reduction audit (depth-4/5 certifier leak check, all 80 promoted atoms)

4/80 leaks (5%) — same rate A1–A6 measured: unaimed 0x5EED2 inv8 (d4+d5, the
exact leak A1–A6 caught, reproduced), aimed_flat 0x5EED2 inv3 (d5 only),
aimed_promote 0x5EED2 inv4 (d5) and inv9 (d4). Redundancy 11/80. Note the cost
signature of residual-max promotion: it selects longer atoms (mean 10.5
instructions vs 4.1 under shortest-policy) and produced 2/10 leaks on one seed —
longer promoted programs are likelier to hide deep compositions. The
hashtbl-solving atom itself holds at every audit depth.

## Verdict

**Aiming works only if it reaches the promotion decision, and only up to the
residual landscape's climbability.** Three-part decomposition, each part
measured:

1. **Aimed search + unaimed promotion: fails.** F 0/9 on 4/4 arm-seed runs
   despite measurably redirected search. Blending or annealing residual into
   novelty selection is not the coupling that matters.
2. **Aimed promotion: the first frontier solves of the arc.** hashtbl+union on
   1/2 seeds, certified at depth 3, holding at depth 4/5 — an existence proof
   that frontier-coupled promotion converts archive proximity into library
   reach. Seed-dependent at this budget (the other seed's census never
   contained a >=0.95 candidate), and it buys the *climbable* half of F only.
3. **The conjunction wall stands.** distinct-count and all six of its hidden
   compositions (7/9 of F) never flip in any arm: 80 promotions across 8
   runs, zero progress. The probe pins the cause on the landscape (greedy
   plateau 0.862 < 0.95), not on the coupling.

For the frontier-coupled-proposer direction this settles the design question
the same way exps 5–6 settled the tax question: **aim information belongs at
the gate (promotion choice), not in the inner variation loop** — it is nearly
free there (<=80 depth-1 comparisons/round) and it is the only placement that
paid. And it sharpens what "aimed escape" cannot do: behavioural-proximity
pressure cannot cross a conjunction wall. Crossing distinct-count needs a
different escape generator — mechanism-level descriptors (e.g. memory access
patterns), stepping-stone curricula (pk_xor-style transfer, which bridged
exactly this kind of wall in the coevo arc), or residuals over depth->1
compositions rather than lone candidates. That is the next experiment, and it
now has a measured target: lift greedy-climbable residual from 0.862 to >=0.95
on distinct-count.

## Honest limitations

- 2 seeds, 10 rounds, one substrate, one depth budget (3), one residual design
  (depth-1 best-agreement vs unsolved F). Residuals over deeper chains, or
  descriptor-space distances, are untested here.
- The headline positive (hashtbl+union) is 1 seed of 2; treat as existence
  proof, not a rate estimate.
- hashtbl and union are behaviourally identical under `runStream` (OUT_R only),
  so the "2 targets" solved are one behaviour counted twice by the battery's
  own accounting (A1–A6 counted them the same way).
- Residual values were not logged per-round in the main run; landscape numbers
  come from the separate probe (same comparison primitive and seed).
- Aimed-arm archive sizes are not directly comparable to the unaimed arm's:
  the 0.12 admission threshold applies to the combined score, whose scale
  differs from raw novelty. The census (what promotion sees) still covered
  every clean candidate in the aimed arms (n_checked never hit the 80 cap).
- Behaviour matching is 0.95 agreement on 8x28 random streams — statistical,
  not exact; retro-audit "holds" means "no chain found at that budget," not a
  proof (same caveat as A1–A6).
