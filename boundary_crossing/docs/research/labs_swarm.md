# LABS round 2026-07-10d — the swarm rematch: diversity + concentration vs pure concentration
> **Belongs to: Round 2026-07-10d · experiment 4 of 6 (parallel swarm on LABS)** — [round index](../../../docs/research/research_round_2026_07_10d.md).

**Status:** built, measured, independently re-verified.
**Verdict up front:** at **equal total eval budget**, a pool of diverse strategies beat a
single concentrated method on **9 of 12** miss lengths — a direct reversal of round b's
headline ("concentrating budget in one arm beats splitting it"). But the mechanism behind
that win is humbler than "diversity discovers something concentration can't": the single
biggest contributor inside every diverse pool, on **all 12 lengths**, was the *same*
long-tenure plain-pair tabu arm that also served as the concentrated baseline — the pool's
edge looks like **independent-restart diversification of one good strategy**, not
strategy-level discovery. Measured against the best number *either* prior round already
had, the swarm **regressed on 7/12 lengths**, **tied on 3**, and **improved on 2**
(48, 64) — so this round's diverse-pool design is not a strict upgrade over the campaign
line as a whole, even though it beats its own equal-budget concentrated control most of the
time. No claim ever exceeded best-known; EXTRAORDINARY-NEEDS-SCRUTINY never fired.

## The hypothesis under test

Round a (`labs_campaign.zig`) ran one concentrated method per length and missed all even
N ≥ 44 plus {61,63,64} (12 lengths; see `docs/research/labs_campaign.md`). Round b
(`labs_even_n.zig`) attacked those 12 misses by **splitting one enlarged budget across
7-8 diverse arms run sequentially** and found the split **hurt**: 4/12 lengths came in
worse than round a's simpler, fully-concentrated run (`docs/research/labs_even_n.md`,
"Honest accounting" section). Round b's own conclusion: *"concentrate budget in whichever
arm is winning rather than spreading it evenly across many hypotheses."*

This round asks the direct follow-up question that round b's design could not answer,
because it never held total budget fixed while varying *only* the diversity/allocation
structure: **does a properly-concentrated diverse pool (adaptive reallocation toward
whichever strategy is improving) beat both (a) one concentrated method and (b) round b's
naive even split — at the identical total eval budget?**

## Design

Five experiments per length, each a **fresh** independent-best-tracking run
(`gbestE = +inf` at the start) at the **same total budget T = 50,000,000 evals**:

| config | pool size | allocation | mechanism |
|---|--:|---|---|
| `concentrated_1` | 1 | n/a | one arm (`tabu_pair_long_tenure`), the whole budget in one continuous run — "few deep strategies" |
| `pool3_equal` | 3 | equal | 3 diverse arms (one tabu / one structural / one memetic family), budget split evenly every round, no feedback — round b's mechanism, generalized |
| `pool3_adaptive` | 3 | adaptive | same 3 arms; from round 2 on, half each round's budget is a floor split evenly, half is reallocated toward whichever arm(s) improved the shared best most in the *previous* round |
| `pool9_equal` | 9 | equal | full 9-arm diversity pool, even split every round |
| `pool9_adaptive` | 9 | adaptive | full 9-arm pool, adaptive reallocation |

6 rounds per pool config (round 0 always equal-split, since there's no history yet).

**The 9-arm pool** covers every diversity axis named in the brief:

| arm | axis | detail |
|---|---|---|
| `tabu_pair_long_tenure` | tenure | tenure = iter+8+rand(m/2) |
| `tabu_pair_short_tenure` | tenure | tenure = iter+1+rand(m/8) |
| `tabu_triple_w4` | neighborhood | triple-flip, window 4 |
| `tabu_triple_w14` | neighborhood | triple-flip, window 14 |
| `tabu_pair_aggr_restart` | restart policy | stagnation limit 15·N (aggressive) |
| `tabu_pair_periodic_restart` | restart policy | forced restart every 800 iters regardless of stagnation |
| `structural` | structural restriction | skew-symmetric (odd N) / mirror-alternating (even N), the best of round b's structural hypotheses |
| `memetic_uniform` | memetic + crossover | population 10, **uniform** crossover |
| `memetic_twopoint` | memetic + crossover | population 10, **two-point** crossover (round b's original) |

`pool3` = `{tabu_pair_long_tenure, structural, memetic_twopoint}` — one representative per
method family. Energy/flip core and all structural-mode machinery
(`computeC`/`energyFromC`/`energyDirect`/`applyFlipDelta`/`Mode`/`freeCount`/`mirrorOf`/
`signOf`/`initStruct`/`applyFreeFlip`/`applyMoveOnce`/`probeMove`) are **copied verbatim**
(read-only reuse) from `labs_even_n.zig`, so any difference in outcome across all three
files in this campaign line is attributable to search strategy, never to a different
energy engine.

**Attribution rule** (avoids a real correctness pitfall): tabu arms are **never**
warm-started from the shared best across rounds/arms — matching round b's own precedent
(it never warm-started structural or plain tabu arms either, only its trailing memetic
step). This matters because warm-starting a skew/mirror-restricted arm from a plain-mode
best sequence would silently break the structural invariant the arm exists to test. Only
memetic arms warm-start half their population from the current shared best each round
(exactly as round b did). The shared `gbestE` pointer plus the aspiration criterion
(`curE + delta < gbestE`) is the sole channel of collaboration between arms.

**Adaptive reallocation, concretely**: per round r>0, `weight_i = 0.5/pool_size +
0.5 * (gain_i_prev_round / sum(gain_prev_round))`, falling back to even split if no arm
improved last round. `gain_i` = the drop in shared `gbestE` attributable to arm i's own
slice (clean attribution since arms run strictly sequentially, never concurrently).

## Reproduce

```bash
zig build-exe boundary_crossing/labs_swarm.zig -O ReleaseFast -femit-bin=/tmp/claude-1000/labs_swarm
# single-threaded per invocation; split into 3 groups to stay well under the 15-min/run cap
# (measured: group1 5.1 min, group2 5.8 min, group3 6.7 min; group1+group2 run concurrently
# as 2 processes = 2 threads total, group3 run after):
/tmp/claude-1000/labs_swarm --ns=44,48,50,52 --csv=/tmp/g1.csv --yield-csv=/tmp/g1_y.csv --json=/tmp/g1.json
/tmp/claude-1000/labs_swarm --ns=54,56,58,60 --csv=/tmp/g2.csv --yield-csv=/tmp/g2_y.csv --json=/tmp/g2.json
/tmp/claude-1000/labs_swarm --ns=61,62,63,64 --csv=/tmp/g3.csv --yield-csv=/tmp/g3_y.csv --json=/tmp/g3.json
# merge -> results/labs_swarm_2026_07_10.csv, results/labs_swarm_yield_2026_07_10.csv,
#          results/labs_swarm_claims_2026_07_10.json
zig build-exe scripts/zig/labs_check.zig -O ReleaseFast -femit-bin=/tmp/claude-1000/labs_check
/tmp/claude-1000/labs_check results/labs_swarm_claims_2026_07_10.json   # exit 0 = all verified
```
`--quick` (div=500) gives a fast smoke run; `--div=N` scales all budgets by 1/N;
`--rounds=N` and `--budget=N` override the round count / per-config total budget.

Measured wall time: group1 (44,48,50,52) = 307.7 s, group2 (54,56,58,60, run concurrently
with group1) = 350.6 s, group3 (61,62,63,64) = 402.4 s — total experiment wall-clock
≈ 753 s (12.6 min) using at most 2 concurrent processes throughout, every individual
invocation comfortably inside the 15-minute cap. No `INTERNAL ERROR` (incremental-vs-direct
energy soundness check) and no `EXTRAORDINARY-NEEDS-SCRUTINY` printed in any of the 3 logs
across all 60 (length × config) runs.

## Results — the full breadth-vs-concentration table

Every cell is a from-scratch-verified best E found within that config's T=50,000,000-eval
budget (E, lower is better).

| N | conc_1 | p3_eq | p3_ad | p9_eq | p9_ad | **swarm best** | won by | round a | round b | best-known |
|--:|--:|--:|--:|--:|--:|--:|:--|--:|--:|--:|
| 44 | 130 | 126 | 138 | 134 | **122** | **122** | pool9_adaptive | 126 | 122 | 122 |
| 48 | 168 | 164 | 160 | **148** | 164 | **148** | pool9_equal | 160 | 160 | 140 |
| 50 | **161** | 185 | 169 | 177 | 185 | **161** | concentrated_1 | 161 | 153 | 153 |
| 52 | 210 | 186 | **178** | 194 | 198 | **178** | pool3_adaptive | 174 | 178 | 166 |
| 54 | 231 | **207** | 223 | 215 | 207 | **207** | pool3_equal | 199 | 207 | 175 |
| 56 | 256 | 252 | 252 | 244 | **232** | **232** | pool9_adaptive | 208 | 196 | 192 |
| 58 | **245** | 269 | 245 | 253 | 245 | **245** | concentrated_1 | 229 | 245 | 197 |
| 60 | 278 | **258** | 266 | 278 | 262 | **258** | pool3_equal | 254 | 246 | 218 |
| 61 | 246 | **230** | 230 | 230 | 246 | **230** | pool3_equal | 230 | 230 | 226 |
| 62 | 307 | 307 | 315 | **283** | 315 | **283** | pool9_equal | 283 | 307 | 235 |
| 63 | 327 | **271** | 271 | 271 | 271 | **271** | pool3_equal | 271 | 259 | 207 |
| 64 | **284** | 320 | 320 | 324 | 300 | **284** | concentrated_1 | 312 | 312 | 208 |

(bold = the best value in that row among the 5 configs; ties resolved to the
first-encountered config in the run order `concentrated_1, pool3_equal, pool3_adaptive,
pool9_equal, pool9_adaptive`.)

Config win tally across all 12 lengths (first-found on ties):
**pool3_equal 4/12** (54,60,61,63), **concentrated_1 3/12** (50,58,64),
**pool9_equal 2/12** (48,62), **pool9_adaptive 2/12** (44,56), **pool3_adaptive 1/12** (52).

## Finding 1: at equal budget, diversity beats pure concentration on 9/12 lengths

`concentrated_1` achieves the length's swarm-best (including ties) on only **3/12** lengths
(50, 58*, 64 — *58 is a 3-way tie with pool3_adaptive and pool9_adaptive). On the other
**9/12** lengths, some diverse pool config **strictly** beats the single concentrated arm
at the identical total budget. This is the direct, controlled version of round b's
concentration-vs-diversity question — round b's original comparison was never apples-to-
apples (round a's concentrated run got a much larger *absolute* budget than any single
arm's share in round b's split); here `concentrated_1` and every pool config get exactly
the same T. Under that controlled comparison, diversity (equal or adaptive) wins more
often than not.

## Finding 2: the pool's edge is restart-diversification of ONE arm, not strategy discovery

This tempers finding 1 considerably. Tracked per pool-config-run (48 total: 4 pool configs
× 12 lengths), the single largest-contributing arm (by cumulative shared-best improvement)
was **`tabu_pair_long_tenure` in all 48 of 48 pool runs** — the exact same arm that IS
`concentrated_1`. `arms_contributed` (arms with *any* positive contribution) averaged
3.5/9 for pool9_equal and 3.25/9 for pool9_adaptive (range 1-6), and 1.33-1.42/3 for pool3
— so other arms (structural, memetic, triple-neighborhood, different tenure/restart
policies) genuinely did contribute *something* on most lengths, just never the largest
share. The most defensible reading: splitting the SAME good strategy into several smaller,
independently-seeded slices (each getting a fresh random restart) plus small supplementary
contributions from a few other arms, sometimes escapes a local optimum that one long
continuous run of the same strategy gets stuck in — a known restart-diversity effect in
metaheuristics — rather than a structurally different move class or crossover operator
"discovering" something concentration cannot reach. Diversity helped, but mostly by
giving the campaign's best-known move type more independent shots on goal, not by a
different idea winning outright.

## Finding 3: adaptive reallocation — a wash at pool3, a mild edge at pool9

Direct adaptive-vs-equal comparison at fixed pool size and budget:

| pool size | adaptive strictly better | equal strictly better | tie |
|--:|--:|--:|--:|
| 3 | 4/12 (48,50,52,58) | 4/12 (44,54,60,62) | 4/12 (56,61,63,64) |
| 9 | 6/12 (44,54,56,58,60,64) | 5/12 (48,50,52,61,62) | 1/12 (63) |

At pool3, "concentrate on whichever is improving" is a coin flip against plain even
splitting. At pool9, adaptive edges ahead (6-5-1) — consistent with the mechanism having
more room to matter when there are more arms to differentiate between, but this is a mild
signal, not a decisive one, and not worth over-reading from 12 data points.

## Finding 4: measured against the best of EITHER prior round, this round is mixed, not a clean advance

Comparing the swarm's best number per length against `min(round a, round b)` — the honest
bar to clear, not either round in isolation:

| N | swarm best | best of round a/b | vs. best-prior | vs. known |
|--:|--:|--:|:--|:--|
| 44 | 122 | 122 | TIE | **CLOSED** |
| 48 | 148 | 160 | **IMPROVED** | +8 above |
| 50 | 161 | 153 | REGRESSED | +8 above |
| 52 | 178 | 174 | REGRESSED | +12 above |
| 54 | 207 | 199 | REGRESSED | +32 above |
| 56 | 232 | 196 | REGRESSED | +40 above |
| 58 | 245 | 229 | REGRESSED | +48 above |
| 60 | 258 | 246 | REGRESSED | +40 above |
| 61 | 230 | 230 | TIE | +4 above |
| 62 | 283 | 283 | TIE | +48 above |
| 63 | 271 | 259 | REGRESSED | +64 above |
| 64 | 284 | 312 | **IMPROVED** | +76 above |

**2/12 improved** on the best prior number (48, 64), **3/12 tied** (44, 61, 62),
**7/12 regressed** (50, 52, 54, 56, 58, 60, 63) despite this round's aggregate compute
(5 configs × 50 M = 250 M evals/length) matching or exceeding round b's per-length total
(160-185 M evals/length). **No new gap was closed** beyond what round b already had: N=44
merely re-matches round b's existing closure (122 = known), it is not a new result. The
two clear improvements (48, 64) are real and reproducible, but the 7 regressions are just
as real — this design's specific arm roster and per-round chunking is not uniformly better
than either prior round's approach, even though it does beat its own same-budget
concentrated control most of the time (Finding 1). Reported as-is, not smoothed over,
per the repo's honesty rule.

## Independent verification

`scripts/zig/labs_check.zig` (unmodified, reused as-is) re-verifies the overall best
sequence per length (across all 5 configs) from scratch:

```
=== summary: verified=12 refuted=0 (of which optimality-not-reproven=0) ===
VERDICT: all claims independently re-verified (E/F from scratch; optimality re-proven where n <= 22)
```

**Refutation test** (the verifier must be able to say no): a planted-lie claims file with
(a) the real N=44 sequence (true E=122) but a false claimed E=100, (b) the real N=64
sequence with one entry corrupted to `2` (not ±1):

```
n=44: REFUTED (claimed E=100, recomputed E=122)
n=64: REFUTED (seq entry not +/-1)
=== summary: verified=0 refuted=2 (of which optimality-not-reproven=0) ===
VERDICT: REFUTED — at least one claim failed independent re-check
```

Both planted lies caught, exit code 1 confirmed. No claim in this round ever exceeded
best-known (`EXTRAORDINARY-NEEDS-SCRUTINY` never printed across all 60 length×config runs) —
the closest approach was N=44 at exactly best-known (122 = 122), never below it.

## Honest verdict: is parallel diversity the lever for open-target records?

**Partially, and with an important caveat.** At a controlled equal-budget comparison,
union-of-diverse-strategies (with either naive equal-split or adaptive reallocation) beats
one concentrated method on 9/12 real, open miss lengths — a genuine, reproducible result
that directly refutes round b's blanket "concentration always beats splitting" framing
*when the comparison is apples-to-apples on total budget*. But attribution shows the
mechanism is mostly **restart diversification of the single best-known strategy**
(the same arm wins every pool-config-run) plus modest, real, but secondary contributions
from genuinely different move classes/crossover operators/structural restrictions — not a
different idea structurally out-searching concentration. And measured against the best
number either prior round already had, this specific swarm design is a net-mixed result
(2 improved, 3 tied, 7 regressed), not a clean escape from the 44.30-style ceiling pattern
seen in this repo's other invention-engine research lines. The honest reading: **"pump more
out at once" helps when it's structured as proper concentration-with-diversity (adaptive
or even just several independent seeded slices of the good strategy) rather than naive
even-splitting — but it is not a free lever that reliably beats a well-tuned, larger-budget
single run, and it did not close any new gap or approach a record here.** Nothing in this
run is new-to-humanity; the deliverable is the measured breadth-vs-concentration curve
itself, honestly reported including its regressions.

Files: `boundary_crossing/labs_swarm.zig` (new, standalone) ·
`results/labs_swarm_2026_07_10.csv` (60 rows: the breadth-vs-concentration curve) ·
`results/labs_swarm_yield_2026_07_10.csv` (auxiliary yield-event log) ·
`results/labs_swarm_claims_2026_07_10.json` (12 claims, independently verified) ·
reused read-only: `boundary_crossing/labs_campaign.zig`, `boundary_crossing/labs_even_n.zig`,
`scripts/zig/labs_check.zig`.
See also: `docs/research/labs_campaign.md` (round a), `docs/research/labs_even_n.md`
(round b), `dial_three.md`, `addition_frontier.md`, repo-root `CLOSURE_PRINCIPLE.md`.
