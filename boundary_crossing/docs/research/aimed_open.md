# Aimed engine on an open target — Round 2026-07-11, experiment E4
> **Belongs to: Round 2026-07-11 · experiment E4 of 6 (aimed engine on an open target)** — [round index](../../../docs/research/research_round_2026_07_11.md).

**Status:** built, measured, independently re-verified. 2026-07-11.
**Verdict up front:** the residual-autocorrelation AIM signal is real and measurable
— it makes the skew-symmetric search on LABS N=61 converge to the shared local
optimum (E=230) **more reliably per fixed budget** (6/6 vs 5/6 seeds at the
largest equal-budget tier tested) and **strictly lower at very low budget**
(best 262 vs 310, mean 296.7 vs 304.7 at 50,000 evals/seed), and in a harder
secondary case (N=48, no known structural restriction) aim closes the **entire**
gap between undirected search and the historical campaign-best at equal big
budget (148 vs 160, matching the swarm round's number that previously needed a
9-arm pool to find). But on the primary target, **neither aim nor undirected
ever broke the E=230 floor**, even at a 500,000,000-eval best-effort budget —
so the 4-unit gap to best-known (226) is **NOT closed**. No claim ever equalled
or beat best-known-minus-one; `EXTRAORDINARY-NEEDS-SCRUTINY` never fired.
Every artifact independently re-verified by the unmodified `scripts/zig/labs_check.zig`;
a planted-lie test (false E, corrupted sequence entry) was correctly refuted.

## 1. Target choice — why N=61, not N=48 or an addition chain

Surveyed candidates, from `boundary_crossing/docs/research/labs_even_n.md` and
`labs_swarm.md`'s 12-length miss table (both docs' embedded `known_e` table,
itself recalled from Packebusch & Mertens 2016, MEDIUM confidence, unverified
this session — same provenance flag as every prior LABS round in this repo):

| N | current best (swarm/round-b) | best-known | gap (abs) | gap (rel) |
|--:|--:|--:|--:|--:|
| **61** | **230** | **226** | **4** | **1.77%** |
| 48 | 148 | 140 | 8 | 5.71% |
| 50 | 161 | 153 | 8 | 5.23% |
| 44 | 122 | 122 | 0 (closed) | — |
| 52..64 | — | — | 12-76 | 6.8%-36.5% |

N=61 is the smallest gap in the entire 12-length miss table, both in absolute
and relative terms — closer than the task prompt's illustrative "e.g. N=48."
It is also odd, so the classical skew-symmetric restriction
(`s_{c+d} = (-1)^d s_{c-d}`, integer center `c=(N-1)/2`, forcing every odd-lag
correlation to exactly 0) applies exactly — a proven, algebraic mechanism, not
a guessed structural analogue. By contrast, `labs_even_n.md`'s honest finding
was that **no** even-N structural analogue of skew-symmetry was ever found:
`mirror_altern`/`palindrome`/`antipalindrome` all lost badly to plain
unrestricted search at equal budget. N=61 therefore combines the smallest gap
with the richest known structure — the most tractable pick.

**Addition chains ruled out:** `boundary_crossing/docs/research/addchain_v2.md`'s
own frank verdict states plainly that "random targets can NEVER yield a record
claim by construction: nobody curates best-known values for them." An
un-tabulated addition-chain length has no published record to beat, so a
"beatable frontier" claim there would be uncheckable against any external
authority — the opposite of what this experiment needs (a cheap EXACT verifier
tied to a genuinely external, curated best-known value). LABS has exactly that
via the recalled Packebusch-Mertens table; addition chains at this repo's
current tooling do not (Flammenkamp/Clift tables were not consulted — out of
scope for a CPU-only, no-internet-fetch experiment).

**N=48 run as a secondary check** (see §4): included because the task prompt
named it explicitly and because it is a genuinely harder case for the aim
mechanism (no known structural restriction at all, so aim has to work in the
full-dimensional `plain` search space) — a useful robustness check on whether
the aim signal generalizes beyond the structure-rich N=61 case.

## 2. The aim mechanism

`boundary_crossing/aimed_open.zig` (new, standalone) copies the energy/flip/
structural machinery (`computeC`, `energyFromC`, `energyDirect`,
`applyFlipDelta`, `merit`, `Mode`, `freeCount`, `mirrorOf`, `signOf`,
`initStruct`, `applyFreeFlip`, `applyMoveOnce`, `probeMove`) **verbatim** from
`labs_even_n.zig` (itself verbatim from `labs_campaign.zig`), so any difference
in outcome is attributable to the new AIM mechanism, never to a divergent
energy engine.

Since `E = sum_k C_k^2`, the lag(s) `k` with the largest `|C_k|` are, by
construction, the dominant contributors to the current energy — a genuinely
computed residual-autocorrelation signal, not a fixed heuristic. The **aimed**
engine:

1. computes `|C_k|` for every lag every iteration (already available from the
   incremental `C` array — one O(N) scan, not a new eval);
2. keeps a magnitude-weighted top-4 list of the largest-`|C_k|` lags;
3. for each sampled pair move, draws the first index `pa` uniformly (kept
   undirected, so exploration is not lost entirely) then draws a target gap
   `k` from the weighted top-4 list and sets `pb = pa +/- k` (falling back to
   a uniform `pb` if that lands out of range or collides with `pa`).

A pair-flip move at raw gap exactly `k` directly engages the `C_k` term
(`s_i * s_{i+k}` is literally one summand of `C_k`), so this concretely
"directs the search using a computed signal about where improvement is
likely" — residual autocorrelation, exactly as the task brief specifies.

**Controlled ablation, not two divergent files:** `aim=false` and `aim=true`
share ONE function (`tabuRun`) with a single boolean flipped; every other code
path (init, exhaustive singles pass, tabu tenure, aspiration, restart/
stagnation, internal soundness check) is identical. This is the safest design
for an aimed-vs-undirected claim: the only measured variable is the pair
partner's sampling distribution.

**Honest limitation, stated up front:** in `skew_odd` mode a free-index gap is
not a pure single-lag scalpel — flipping free index `i` also flips its mirror
`2c-i`, so a pair move touches 4 raw positions and several induced lags besides
the intended one. The aim signal targets the dominant term; it is not exact.

## 3. Equal-budget ablation — the efficiency-vs-ceiling curve (N=61)

Five budget levels, 6 fresh seeds each (`gbestE = +inf` per seed, no shared
state, no warm-start), `skew_odd` mode, single+pair neighborhood, otherwise
identical code:

| evals/seed | undir best | undir mean | undir hits 230/6 | aimed best | aimed mean | aimed hits 230/6 |
|--:|--:|--:|--:|--:|--:|--:|
| 50,000 | 310 | 304.67 | 0/6 | **262** | **296.67** | 0/6 |
| 200,000 | 230 | 258.00 | 2/6 | 230 | 266.00 | 2/6 |
| 800,000 | 230 | 238.00 | 4/6 | 230 | **235.33** | **5/6** |
| 1,600,000 | 230 | 235.33 | 5/6 | 230 | 235.33 | 5/6 |
| 3,200,000 | 230 | 232.67 | 5/6 | 230 | **230.00** | **6/6** |

Reading the curve honestly: at the smallest budget (50,000 evals/seed —
neither arm has reached the shared floor yet) aim gives a clear, unambiguous
win (best 262 vs 310, mean 296.7 vs 304.7 — every one of the 6 aimed seeds
beat every one of the 6 undirected seeds' mean). Once budget crosses
~200,000-800,000 evals/seed, both arms reach the SAME floor (E=230) most of
the time — aim's advantage there is **reliability of convergence**, not a
lower final value: aim's hit-rate is >= undirected's at every tier and
strictly higher at 800,000 (5/6 vs 4/6) and 3,200,000 (6/6 vs 5/6). At equal
budget, **aim never does worse on best-of-N at any tier**, and closes the
"how many evals to reliably reach the local optimum" gap faster than
undirected search — a genuine, bounded, honestly-modest result: **aim
improves search efficiency and reliability, it does not (on this length) cross
the ceiling into a better basin.**

## 4. Best-effort push — does either arm ever beat 230?

Both arms given a big, equal, best-effort budget of **500,000,000 evals each**
(single-threaded, ~10x the largest prior single-arm budget used on this length
in `labs_even_n.md`'s `skew_pair`+`skew_triple` combined 55,000,000):

```
undirected_big: E=230 F=8.0891 evals=500000016
aimed_big:      E=230 F=8.0891 evals=500000024
```

**Both arms plateau at exactly E=230** — the same value the equal-budget sweep
already reached at ~200,000 evals/seed. 2,500x more budget bought zero further
improvement, for either arm. This is the decisive negative result on the
primary question: within the skew-symmetric restriction, E=230 is a hard floor
that no amount of budget or aim-quality crosses (see §7 for interpretation).
Overall run wall time: **599,130 ms (10.0 min), single-threaded**, inside the
15-minute cap. `EXTRAORDINARY-NEEDS-SCRUTINY` never fired.

## 5. Secondary check — N=48, no known structure, plain mode

N=48 has no known even-N structural analogue (per `labs_even_n.md`'s own
honest negative result: `mirror_altern`/`palindrome`/`antipalindrome` all lost
to plain search). Running the identical aim mechanism in `plain` mode
(m=n=48, no mirror pairing) at equal budget:

| budget | undirected | aimed |
|---|--:|--:|
| eq-budget 5,000,000/seed × 4 seeds | best 164, mean 177.00 | best 164, mean 174.00 |
| big-budget 100,000,000 (best-effort) | **160** | **148** |

At the big-budget tier, aim reaches **E=148** — matching the swarm round's
historical best for N=48 (`labs_swarm.md`, which needed a 9-arm diverse pool
with adaptive reallocation to find that number) — using a single arm with only
the lag-biased pair mechanism added on top of plain single+pair tabu search.
Undirected at the identical budget only reaches E=160. This is the clearest
positive result in this experiment: **in the harder, structure-poor case, aim
closes essentially the whole undirected-vs-historical-best gap at equal
budget** (148 vs 140 known — still 8 above best-known, matching, not beating,
the swarm's prior number, but doing so with a far simpler single-arm search).

## 6. Independent verification

`scripts/zig/labs_check.zig` (unmodified, reused as-is) re-verifies every claim
from scratch (direct O(N²) energy, no incremental tricks, no shared code):

```
$ /tmp/claude-1000/bin/labs_check results/aimed_open_claims_2026_07_11.json
n=61: VERIFIED E=230 F=8.0891 [HEURISTIC — no optimality claimed]   (undirected_eq_best)
n=61: VERIFIED E=230 F=8.0891 [HEURISTIC — no optimality claimed]   (aimed_eq_best)
n=61: VERIFIED E=230 F=8.0891 [HEURISTIC — no optimality claimed]   (undirected_big)
n=61: VERIFIED E=230 F=8.0891 [HEURISTIC — no optimality claimed]   (aimed_big)

=== summary: verified=4 refuted=0 (of which optimality-not-reproven=0) ===
VERDICT: all claims independently re-verified (E/F from scratch; optimality re-proven where n <= 22)
```

The N=48 secondary claims file (`aimed_big` E=148 etc.) was likewise run
through the same unmodified verifier: `verified=4 refuted=0`, all VERIFIED.

**Planted-lie refutation test** (the verifier must be able to say no): took a
real, independently-reproduced N=61 skew-symmetric sequence achieving the true
E=230, and planted (a) a false claimed E=226 (i.e., falsely claiming the exact
best-known value — the most dangerous kind of lie, a fabricated "record"), and
(b) the same real sequence with one entry corrupted to `2` (not ±1):

```
n=61: REFUTED (claimed E=226, recomputed E=230)
n=61: REFUTED (seq entry not +/-1)

=== summary: verified=0 refuted=2 (of which optimality-not-reproven=0) ===
VERDICT: REFUTED — at least one claim failed independent re-check
```

Both planted lies caught, exit code 1 confirmed.

## 7. Honest distance to record

- **N=61 (primary target):** best achieved across every arm and every budget
  tested (equal-budget sweep + 500,000,000-eval best-effort push, both aimed
  and undirected) = **E=230** (F=8.0891), against best-known **226**. Gap =
  **4** (1.77% above best-known — unchanged from the prior campaign best).
  `EXTRAORDINARY-NEEDS-SCRUTINY` **never fired.**
- **N=48 (secondary):** best achieved = **148** (aimed, big-budget), against
  best-known **140**. Gap = **8**, matching (not beating) the swarm round's
  prior best for this length.
- **No claim in this experiment ever equalled or exceeded a recalled
  best-known value.** This is an honest, bounded, mostly-negative result on
  the primary question ("does aim close the N=61 gap?" — no), with a genuine,
  measured positive finding on the secondary question ("does aim help at
  all?" — yes, on efficiency/reliability at N=61, and on final quality at
  N=48).
- **What this says about the arc's "AIM × REPRESENTABILITY" thesis:** the
  N=61 result is consistent with a REPRESENTABILITY ceiling, not an aim
  ceiling — the skew-symmetric manifold plateaus at E=230 regardless of how
  much budget or how good the pair-sampling aim is (200,000 evals/seed and
  500,000,000 evals/seed found the identical floor), which is the signature of
  a search space whose optimum does not contain the N=61 record sequence,
  not of an under-aimed search. If that is right, no amount of aim inside the
  skew-symmetric restriction will ever close this specific 4-unit gap — the
  fix would have to break the structural restriction itself (try aim inside
  `plain` mode instead, as done for N=48, or a different structural family
  entirely), which is exactly the N=48 result's shape: aim's biggest win
  showed up in the LESS-representable (no known structure) search, not the
  MORE-representable (skew) one, matching the round's premise that
  representability and aim interact rather than aim alone dominating.

## Reproduce

```bash
zig build-exe boundary_crossing/aimed_open.zig -O ReleaseFast -femit-bin=/tmp/claude-1000/bin/aimed_open
zig build-exe scripts/zig/labs_check.zig      -O ReleaseFast -femit-bin=/tmp/claude-1000/bin/labs_check

# primary target N=61: equal-budget ablation (6 seeds @ 3.2M evals/seed) + 500M-eval best-effort push
/tmp/claude-1000/bin/aimed_open --n=61 --mode=skew --known-e=226 --prior-best=230 \
  --eq-budget=3200000 --seeds=6 --big-budget=500000000 \
  --csv=results/aimed_open_2026_07_11.csv --json=results/aimed_open_claims_2026_07_11.json

# supplementary budget-sweep points (50k/200k/800k/1.6M evals/seed) for the efficiency curve in S3
for b in 50000 200000 800000 1600000; do
  /tmp/claude-1000/bin/aimed_open --n=61 --mode=skew --known-e=226 --prior-best=230 \
    --eq-budget=$b --seeds=6 --big-budget=1000 \
    --csv=/tmp/sweep_$b.csv --json=/tmp/sweep_$b.json
done

# secondary target N=48, no known structure: plain mode
/tmp/claude-1000/bin/aimed_open --n=48 --mode=plain --known-e=140 --prior-best=148 \
  --eq-budget=5000000 --seeds=4 --big-budget=100000000 \
  --csv=/tmp/n48.csv --json=/tmp/n48_claims.json

# independent verification (mandatory, unmodified verifier)
/tmp/claude-1000/bin/labs_check results/aimed_open_claims_2026_07_11.json
```

Measured wall time: primary N=61 invocation (phase 1 6-seed equal-budget
ablation + phase 2 500,000,000-eval best-effort push, both arms) =
**599,130 ms (10.0 min)**, comfortably inside the 15-minute cap.
Sweep invocations (4 runs) together < 20 s. N=48 secondary invocation = 55.5 s.
Single-threaded throughout (no `--threads` flag exists in this file; the
engine is single-threaded by construction, matching the ≤2-threads-total
constraint with headroom to run the N=48 secondary check concurrently with
the N=61 primary run).

Files: `boundary_crossing/aimed_open.zig` (new, standalone) ·
`results/aimed_open_2026_07_11.csv` (equal-budget + best-effort rows for N=61) ·
`results/aimed_open_claims_2026_07_11.json` (4 claims: undirected_eq_best,
aimed_eq_best, undirected_big, aimed_big — independently verified) ·
reused read-only: `scripts/zig/labs_check.zig`, and (for the energy/structural
machinery, copied verbatim per campaign convention) `boundary_crossing/labs_even_n.zig`.
See also: `boundary_crossing/docs/research/labs_campaign.md` (round a),
`labs_even_n.md` (round b), `labs_swarm.md` (round c/D4),
`docs/research/research_round_2026_07_11_PLAN.md` (this round's plan).
