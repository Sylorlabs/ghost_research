# LABS dial-3 campaign — proven small-N optima + heuristic frontier to N=64
> **Belongs to: Round 2026-07-10 · experiment 1 of 8 (LABS dial-3 campaign)** — [round index](../../../docs/research/research_round_2026_07_10.md).

**Status:** built, measured, independently verified. 2026-07-10.
**Verdict up front:** nothing here is new-to-humanity. Proven optima for N ≤ 24 (which the
literature has had for decades), and heuristic sequences that *match* the literature's proven
optima for every N ≤ 43 and most odd N to 59, but fall short at even N ≥ 44 and at N ∈ {61,63,64}.
The EXTRAORDINARY-NEEDS-SCRUTINY flag never fired.

## The target

Low-Autocorrelation Binary Sequences (LABS): for S ∈ {+1,−1}^N, the aperiodic autocorrelations
are C_k = Σ_{i=0}^{N−1−k} s_i s_{i+k}; energy E = Σ_{k=1}^{N−1} C_k²; merit factor F = N²/(2E).
Minimizing E is a genuinely-hard open combinatorial problem — the repo's north-star
"genuine unknown" (see `../../../CLOSURE_PRINCIPLE.md`, `dial_three.md`,
`addition_frontier.md` for the campaign pattern). Optima are proven in the literature only up
to N = 66 (branch-and-bound, CPU-years); beyond that, everything anyone has is heuristic.

## Reproduce (from repo root; single-threaded; ≈4 m 15 s + 0.6 s verify)

```bash
zig build-exe boundary_crossing/labs_campaign.zig -O ReleaseFast -femit-bin=/tmp/claude-1000/labs_campaign
/tmp/claude-1000/labs_campaign          # add --quick for a ~3 s smoke run
zig build-exe scripts/zig/labs_check.zig -O ReleaseFast -femit-bin=/tmp/claude-1000/labs_check
/tmp/claude-1000/labs_check results/labs_claims_2026_07_10.json   # exit 0 = all verified
```

zig 0.14.1. Outputs: `results/labs_yield_2026_07_10.csv` (yield curve),
`results/labs_claims_2026_07_10.json` (claims for the independent verifier).

## Method

* **N = 2..24 — exhaustive (PROVEN).** Gray-code walk over all 2^(N−1) sequences with s_0 = +1
  fixed (negation symmetry E(s) = E(−s)); each Gray step is one flip → O(N) incremental
  C_k/E update. N=24 is 8.4 M sequences; the whole proven tier runs in ~2 s.
* **N = 25..64 — tabu local search (HEURISTIC).** Single-flip neighborhood with O(N)
  incremental ΔE, tabu tenure 4 + rand(N/4), aspiration when a move beats the global best,
  restart on stagnation (no global improvement for 60·N moves). For **odd N** additionally a
  tabu search restricted to **skew-symmetric** sequences (s_{c+d} = (−1)^d s_{c−d},
  c = (N−1)/2 — forces all odd-lag C_k to 0 and halves the dimension); global best is taken
  over both. Budgets: 20 M plain evals (N < 40) / 60 M (N ≥ 40), +6 M / 18 M skew evals for odd N.
  One "eval" = one neighbor ΔE probe (O(N); a skew pair-flip probe costs ~4 O(N) passes but
  counts as one neighbor).
* **Internal guards:** after every restart the incremental energy is re-checked against a
  from-scratch computation (process aborts on mismatch — never fired); every reported artifact
  is re-evaluated from scratch before being claimed.
* Fixed seeds (0xC0FFEE^N, 0x5EED^N) → the run is reproducible bit-for-bit.

## Best-known table: provenance and confidence

The embedded table (optimal E per N) has per-entry provenance:

| N range | provenance | confidence |
|---|---|---|
| 3,4,5,7,11,13 | Barker sequences; classical optimality | **HIGH** |
| 2..24 (rest) | literature exhaustive values | **HIGH** — and independently **re-proven by this run's exhaustive tier** |
| 25..64 | recalled from Packebusch & Mertens 2016 (J. Phys. A 49, 165001; arXiv:1512.02475), who proved optima to N=66 | **MEDIUM** — the *literature* proof is solid, but my *recall* of the exact numbers was not re-checked against the paper in this session |

**Audit of the recall:** the exhaustive tier reproduced the recalled table entry **exactly for
all 23 values N = 2..24** (including the non-obvious ones: E(17)=32, E(19)=29, E(23)=47). That
is a 23/23 spot-check of the recall process, which raises — but does not certify — confidence
in the 25..64 band. Any "BELOW-known" gap below should be read against a MEDIUM-confidence
reference; any *excess* over it would be flagged EXTRAORDINARY-NEEDS-SCRUTINY, and the recalled
entry would be suspected first.

## Results (full table)

Status: **PROVEN** = exhaustive at this run, optimum certain. **HEURISTIC** = best found within
budget. "= known" means our E equals the (recalled) literature optimum.

| N | best E | best F | known F | status | evals |
|--:|--:|--:|--:|:--|--:|
| 2 | 1 | 2.0000 | 2.0000 | PROVEN = known | 2 |
| 3 | 1 | 4.5000 | 4.5000 | PROVEN = known (Barker) | 4 |
| 4 | 2 | 4.0000 | 4.0000 | PROVEN = known (Barker) | 8 |
| 5 | 2 | 6.2500 | 6.2500 | PROVEN = known (Barker) | 16 |
| 6 | 7 | 2.5714 | 2.5714 | PROVEN = known | 32 |
| 7 | 3 | 8.1667 | 8.1667 | PROVEN = known (Barker) | 64 |
| 8 | 8 | 4.0000 | 4.0000 | PROVEN = known | 128 |
| 9 | 12 | 3.3750 | 3.3750 | PROVEN = known | 256 |
| 10 | 13 | 3.8462 | 3.8462 | PROVEN = known | 512 |
| 11 | 5 | 12.1000 | 12.1000 | PROVEN = known (Barker) | 1 024 |
| 12 | 10 | 7.2000 | 7.2000 | PROVEN = known | 2 048 |
| 13 | 6 | **14.0833** | 14.0833 | PROVEN = known (Barker; the all-time F record) | 4 096 |
| 14 | 19 | 5.1579 | 5.1579 | PROVEN = known | 8 192 |
| 15 | 15 | 7.5000 | 7.5000 | PROVEN = known | 16 384 |
| 16 | 24 | 5.3333 | 5.3333 | PROVEN = known | 32 768 |
| 17 | 32 | 4.5156 | 4.5156 | PROVEN = known | 65 536 |
| 18 | 25 | 6.4800 | 6.4800 | PROVEN = known | 131 072 |
| 19 | 29 | 6.2241 | 6.2241 | PROVEN = known | 262 144 |
| 20 | 26 | 7.6923 | 7.6923 | PROVEN = known | 524 288 |
| 21 | 26 | 8.4808 | 8.4808 | PROVEN = known | 1 048 576 |
| 22 | 39 | 6.2051 | 6.2051 | PROVEN = known | 2 097 152 |
| 23 | 47 | 5.6277 | 5.6277 | PROVEN = known | 4 194 304 |
| 24 | 36 | 8.0000 | 8.0000 | PROVEN = known | 8 388 608 |
| 25 | 36 | 8.6806 | 8.6806 | HEURISTIC = known | 26.0 M |
| 26 | 45 | 7.5111 | 7.5111 | HEURISTIC = known | 20.0 M |
| 27 | 37 | 9.8514 | 9.8514 | HEURISTIC = known | 26.0 M |
| 28 | 50 | 7.8400 | 7.8400 | HEURISTIC = known | 20.0 M |
| 29 | 62 | 6.7823 | 6.7823 | HEURISTIC = known | 26.0 M |
| 30 | 59 | 7.6271 | 7.6271 | HEURISTIC = known | 20.0 M |
| 31 | 67 | 7.1716 | 7.1716 | HEURISTIC = known | 26.0 M |
| 32 | 64 | 8.0000 | 8.0000 | HEURISTIC = known | 20.0 M |
| 33 | 64 | 8.5078 | 8.5078 | HEURISTIC = known | 26.0 M |
| 34 | 65 | 8.8923 | 8.8923 | HEURISTIC = known | 20.0 M |
| 35 | 73 | 8.3904 | 8.3904 | HEURISTIC = known | 26.0 M |
| 36 | 82 | 7.9024 | 7.9024 | HEURISTIC = known | 20.0 M |
| 37 | 86 | 7.9593 | 7.9593 | HEURISTIC = known | 26.0 M |
| 38 | 87 | 8.2989 | 8.2989 | HEURISTIC = known | 20.0 M |
| 39 | 99 | 7.6818 | 7.6818 | HEURISTIC = known | 26.0 M |
| 40 | 108 | 7.4074 | 7.4074 | HEURISTIC = known | 60.0 M |
| 41 | 108 | 7.7824 | 7.7824 | HEURISTIC = known | 78.0 M |
| 42 | 101 | 8.7327 | 8.7327 | HEURISTIC = known | 60.0 M |
| 43 | 109 | 8.4817 | 8.4817 | HEURISTIC = known | 78.0 M |
| 44 | 126 | 7.6825 | 7.9344 | HEURISTIC, BELOW known (E 126 vs 122) | 60.0 M |
| 45 | 118 | 8.5805 | 8.5805 | HEURISTIC = known | 78.0 M |
| 46 | 131 | 8.0763 | 8.0763 | HEURISTIC = known | 60.0 M |
| 47 | 135 | 8.1815 | 8.1815 | HEURISTIC = known | 78.0 M |
| 48 | 160 | 7.2000 | 8.2286 | HEURISTIC, BELOW known (E 160 vs 140) | 60.0 M |
| 49 | 136 | 8.8272 | 8.8272 | HEURISTIC = known | 78.0 M |
| 50 | 161 | 7.7640 | 8.1699 | HEURISTIC, BELOW known (E 161 vs 153) | 60.0 M |
| 51 | 153 | 8.5000 | 8.5000 | HEURISTIC = known | 78.0 M |
| 52 | 174 | 7.7701 | 8.1446 | HEURISTIC, BELOW known (E 174 vs 166) | 60.0 M |
| 53 | 170 | 8.2618 | 8.2618 | HEURISTIC = known | 78.0 M |
| 54 | 199 | 7.3266 | 8.3314 | HEURISTIC, BELOW known (E 199 vs 175) | 60.0 M |
| 55 | 171 | 8.8450 | 8.8450 | HEURISTIC = known | 78.0 M |
| 56 | 208 | 7.5385 | 8.1667 | HEURISTIC, BELOW known (E 208 vs 192) | 60.0 M |
| 57 | 188 | 8.6410 | 8.6410 | HEURISTIC = known | 78.0 M |
| 58 | 229 | 7.3450 | 8.5381 | HEURISTIC, BELOW known (E 229 vs 197) | 60.0 M |
| 59 | 205 | 8.4902 | 8.4902 | HEURISTIC = known | 78.0 M |
| 60 | 254 | 7.0866 | 8.2569 | HEURISTIC, BELOW known (E 254 vs 218) | 60.0 M |
| 61 | 230 | 8.0891 | 8.2323 | HEURISTIC, BELOW known (E 230 vs 226) | 78.0 M |
| 62 | 283 | 6.7915 | 8.1787 | HEURISTIC, BELOW known (E 283 vs 235) | 60.0 M |
| 63 | 271 | 7.3229 | 9.5870 | HEURISTIC, BELOW known (E 271 vs 207) | 78.0 M |
| 64 | 312 | 6.5641 | 9.8462 | HEURISTIC, BELOW known (E 312 vs 208) | 60.0 M |

Scorecard: **23/23 PROVEN optima** (N ≤ 24, each re-proving the recalled literature entry);
heuristic tier **matched the recalled proven optimum on 28/40 lengths**, including every
N ≤ 43 and every odd N ≤ 59; **12/40 fell short**, all even N ≥ 44 plus {61, 63, 64}.
No value ever exceeded best-known — the EXTRAORDINARY-NEEDS-SCRUTINY path exists in the code
and was never taken.

Showcase artifacts (each re-checkable by hand or via the verifier):

```
N=13  E=6    F=14.0833  +-+-++--+++++                       (Barker)
N=27  E=37   F=9.8514   +++----+++-+++-+++-++-+--+-        (matches proven optimum)
N=57  E=188  F=8.6410   ---+++--+++--++++++---+-+-+--+++++++-++-+-+--++-++--+--+-
N=64  E=312  F=6.5641   (heuristic; proven optimum is E=208 — we are 50% above in energy)
```

## Yield curve (best F vs evals; full data in `results/labs_yield_2026_07_10.csv`)

The CSV logs every global-best improvement event (N, method, cumulative evals, E, F) plus a
final row per N — 1 192 rows. The consistent shape: random init lands at F ≈ 1; the first
~100·N evals of tabu recover F ≈ 4–5; F ≈ 6–7 arrives by ~1 M evals; the last few energy
quanta cost orders of magnitude more. N = 57 is representative:

```
evals      1     286    10 945   492 k    6.1 M   14.3 M   60.0 M(skew)  61.0 M(skew)
F        1.02    3.44    5.14     6.15     6.45     7.13     7.38→7.66      8.64
```

Note the mechanism: plain tabu stalled at F = 7.125 after 14 M evals; the **skew-symmetric
restriction** then took N=57 to the proven optimum F = 8.641 within its first million evals.
The same pattern explains the miss profile: every odd N ≤ 59 (skew search available) matched
best-known; the misses are concentrated at even N (no skew restriction exists) and at
N ∈ {61, 63} where the optimum is presumably not skew-symmetric or the basin is too deep.
Diminishing returns are steep: tripling the budget (20 M → 60 M) at N ≥ 40 fixed N = 40 and 42
and improved-but-did-not-close N = 44..64.

## Independent verification (never trust the search binary)

`scripts/zig/labs_check.zig` shares **no code** with the campaign: energy is recomputed with a
direct O(N²) double loop (no incremental updates, no Gray code), and for PROVEN claims with
N ≤ 22 it re-proves optimality with its own naive brute-force enumeration (full re-evaluation
per candidate). PROVEN claims at N = 23, 24 get E/F re-verified but optimality is reported as
**not independently re-proven** (honest non-claim; the brute cap keeps the verifier under a
second). Run on the real claims file:

```
=== summary: verified=63 refuted=0 (of which optimality-not-reproven=2) ===
VERDICT: all claims independently re-verified   (exit 0, 0.58 s)
```

**Refutation test** (the verifier must be able to say no): a planted claims file with
(a) Barker-13 sequence with E claimed 5 (true 6), (b) the all-+1 N=13 sequence with correct
E = 650 but a false "PROVEN" optimality tag, (c) a sequence containing a 2:

```
n=13: REFUTED (claimed E=5, recomputed E=6)
n=13: REFUTED non-optimal (independent brute force found E=6 < claimed optimal 650)
n=5:  REFUTED (seq entry not +/-1)
VERDICT: REFUTED   (exit 1)
```

All three lies caught, nonzero exit confirmed.

## Frank verdict: distance from the published state of the art

* **Proven tier.** Our exhaustive N ≤ 24 is trivial by literature standards: Packebusch &
  Mertens (2016) *proved* optima to **N = 66** with branch-and-bound over symmetry-reduced
  classes at a cost of CPU-years. Matching that would need their bounding machinery (partial-
  sequence energy lower bounds), not a bigger Gray scan (2^63 is out of reach forever).
* **Heuristic tier.** Matching proven optima to N = 43 with a ~90 M-eval single-threaded tabu
  run is respectable but well behind specialized solvers (memetic/self-avoiding-walk searches:
  lssOrel, xLastovka, MAGMA-class work), which reach best-known values to N in the hundreds
  and skew-symmetric records to N in the thousands, at F ≈ 6.2–6.4 asymptotically. Our even-N
  misses at N ≥ 44 are exactly where those solvers' richer move sets (combined flips,
  shift/rotation moves, population methods) and vastly larger budgets pay off.
* **What it would take to be competitive:** (1) a branch-and-bound proven tier with the
  Mertens-style bound if we ever want new *proofs* (N > 66 — months of CPU even for one
  length); (2) for heuristics, a memetic layer (crossover + tabu descent) and the
  even-N analogue tricks; (3) the honest path to *new-to-humanity* here is the skew-symmetric
  record frontier at large odd N (thousands), where the search space collapses and records are
  still actively published — that is a compute-scale project, not a new idea, exactly the
  dial-3 conclusion of `dial_three.md` and `addition_frontier.md`.
* **Nothing in this run is a discovery.** Its value is the *mechanism*, run honestly end-to-end
  at CPU-seconds-to-minutes scale: genuine-unknown target, sound proofs where feasible, clearly
  flagged heuristics elsewhere, a best-known table with per-entry provenance, an independent
  refutation-tested verifier, and a measured yield curve.

Files: `boundary_crossing/labs_campaign.zig` · `scripts/zig/labs_check.zig` ·
`results/labs_yield_2026_07_10.csv` · `results/labs_claims_2026_07_10.json`.
See also: `dial_three.md`, `addition_frontier.md`, repo-root `CLOSURE_PRINCIPLE.md`.
