# Addition-chain campaign v2 — stronger constructions, external verification (2026-07-10)

Extends the 2026-07-07 campaign (`results/addchain_campaign_2026_07_07.md`). New engine:
`boundary_crossing/addchain_v2.zig`. New generator: `scripts/zig/addchain_gen_v2.zig`.
Verifier: the EXISTING `scripts/zig/addchain_check.zig`, reused read-only — it remains the
only authority on validity/minimality; the engine asserts nothing. All targets drawn from
`/dev/urandom` post-build. Single-threaded, CPU-only. Zig 0.14.1, `zig build-exe -O ReleaseFast`.

## Methods implemented (all emit chains re-checked externally)

| method | what it is | provenance |
|---|---|---|
| binary  | MSB-first double-and-add, len = ⌊log₂n⌋+ν(n)−1 | textbook (fixed baseline) |
| factor  | recursive l(ab) ≤ l(a)+l(b); primes → chain(p−1)+1; base n ≤ 1024 exact IDDFS (memoized) | textbook |
| window  | sliding-window / m-ary, odd-digit windows k = 1..6 (best k kept), odd-ladder dictionary | textbook |
| search  | bounded stochastic improver: (a) randomized backward decomposition (pop largest needed value; split by halving / subtract-largest / subtract-closest-to-half / subtract-random — Bos-Coster-flavored), (b) randomized-width windows, (c) deletion-repair local search over chain structure (drop any element whose loss keeps every other element decomposable), applied to stochastic candidates AND classical chains | known heuristic family, this combination hand-rolled |
| exact   | complete iterative-deepening DFS (node-budgeted; ABSTAINS rather than emit if budget trips) | Knuth TAOCP 4.6.3 |

Chains are built as decomposition-closed value sets (every element a sum of two strictly
smaller members), so sortedness ⇒ validity; validity is still re-proven locally and then
independently by `addchain_check`.

## Results (this run; seeds recorded, targets from /dev/urandom)

Mean chain lengths per batch (`results/addchain_v2_2026_07_10.csv`, 118 targets):

| batch | count | n range | binary | factor | window | search | best | independently proven minimal |
|---|---|---|---|---|---|---|---|---|
| SMALL1K  | 20 | [2, 1024]        | 11.95 | 11.20 | 11.40 | 11.20 | 11.20 | **20/20 VERIFIED minimal** |
| SMALL4K  | 20 | [1025, 4096]     | 16.00 | 14.40 | 14.55 | 14.20 | 14.00 | **20/20 VERIFIED minimal** |
| SMALL16K | 10 | [4097, 16384]    | 18.30 | 17.00 | 16.80 | 16.40 | 16.40 | **10/10 VERIFIED minimal** |
| SMALL64K |  8 | (16384, 65536]   | 23.50 | 20.63 | 20.38 | 20.00 | 19.50 | 0/8 (VALID, UNPROVEN — see below) |
| MID      | 60 | 24–40 bit        | 49.17 | 44.42 | 42.88 | **41.67** | **41.67** | 0/60 (VALID, UNPROVEN — NP-hard) |

Verifier verdicts: **118/118 chains independently VALID, 0 refuted, 0 abstained.**
MID: 60/60 BEATS-BINARY. Engine run time: MID 11 s (60 targets, 4000 restarts/target).

### Win rates (MID, 24–40 bit — the campaign's main question)

- best < binary: **60/60 (100%)**
- best < best-window: **53/60 (88%)**
- search < min(binary, factor, window) — the honest **invention yield: 52/60 (87%)**,
  mean saving vs the best classical heuristic ≈ 1.2 additions, max 3 (n=858105880543).

**Ablation (mandatory honesty check).** "search" includes deletion-repair applied to the
classical chains themselves, and dr(window) trivially prunes unused dictionary entries.
Re-running with `--restarts 0` (dr-of-classical only, same seed): yield drops to **12/60,
mean 42.65**. So the genuinely stochastic component contributes ~40/60 of the yield and
~1.0 addition of the mean improvement. On small targets the stochastic search adds almost
nothing: yield 0/20, 0/20, 1/10 — classical + exact already saturate short chains.

### Lower-bound gaps

The bound requested for this campaign, `lb_task = ⌈log₂n⌉ + ⌈log₂ν(n)⌉`, is **NOT a sound
lower bound**. Measured refutation: n=15 has l(15)=5 (chain 1→2→3→6→12→15, VERIFIED minimal
by `addchain_check`) but lb_task=6 — gap −1. Every small batch shows gap_task min = −1.
The sound bound is Schönhage's l(n) ≥ log₂n + log₂ν(n) − 2.13 (`lb_sch`, floored at ⌈log₂n⌉).

| batch | gap vs lb_task (mean/min/max) | gap vs lb_sch (mean/min/max) |
|---|---|---|
| SMALL1K  | −0.60 / −1 / 0 | 1.60 / 0 / 2 |
| SMALL4K  | −0.60 / −1 / 0 | 1.80 / 1 / 2 |
| SMALL16K | −0.10 / −1 / 0 | 2.30 / 2 / 3 |
| MID      | 3.45 / 1 / 6   | 5.97 / 3 / 8 |

The MID gap vs the (unsound but empirically tight-ish) task bound is 1–6, i.e. the true
optimum for 24–40 bit targets lies somewhere in a ~1–6 addition window we cannot close.
On the 64K batch, where exact search still terminates, exact beat the best heuristic on
4/8 targets by exactly 1 — the heuristic stack sits ≈ 0.5 additions above minimal at
16 bits; the distance at 24–40 bits is unknown (NP-hard).

### Minimality: the provable range (task 4)

- **Provable and PROVEN: all 50 random targets with n ≤ 16384** (plus the 6 known-value
  demo targets 15/127/255/511/1023/1000, all matching the 2026-07-07 campaign values).
  Checker cost: 0.02 s (1K), 0.4 s (4K), 5.9 s (16K batch).
- **The wall is (16384, 65536]:** all 8 targets there have best length 18–20, i.e.
  claimed−1 = 17–19 > 16 = `addchain_check`'s IDDFS proof cap, so the independent verdict
  degrades to VALID + minimality-UNPROVEN even though the engine's own complete IDDFS
  terminated (9 m 11 s for 8 targets at 3×10⁹-node budget; the unbudgeted variant DNF'd a
  10-minute wall — documented negative result). Per campaign discipline the engine's own
  search is NOT accepted as proof; **the largest independently-provable range demonstrated
  is n ≤ 16384** (bounded by the checker's depth-16 cap, and in practice by IDDFS cost).

### Verifier evidence (soundness of the pipeline)

- 118/118 real chains: independent validity re-check passed, exit 0 per batch.
- Refutation test 1 (planted non-minimal): n=15 claimed len 6 (chain 1,2,3,4,8,12,15) →
  `REFUTED non-minimal (independent IDDFS found length 5 < claimed 6)`, exit 1.
- Refutation test 2 (planted invalid): n=20 chain 1,2,4,7,20 (7 is no sum of two priors) →
  `REFUTED invalid chain`, exit 1.

## Reproduce

```bash
cd /tmp && mkdir -p acv2 && cd acv2
zig build-exe <repo>/boundary_crossing/addchain_v2.zig      -O ReleaseFast -femit-bin=./addchain_v2
zig build-exe <repo>/scripts/zig/addchain_gen_v2.zig        -O ReleaseFast -femit-bin=./addchain_gen_v2
zig build-exe <repo>/scripts/zig/addchain_check.zig         -O ReleaseFast -femit-bin=./addchain_check

./addchain_gen_v2 bits 60 24 40 MID t_mid.csv          # /dev/urandom targets
./addchain_v2 --targets t_mid.csv --csv c_mid.csv --json r_mid.json --restarts 4000 --seed 0xD1CE2026
./addchain_check < r_mid.json                          # exit 0, 60x VALID+BEATS-BINARY

./addchain_gen_v2 range 20 2 1024 SMALL1K t_s1k.csv    # provable range
./addchain_v2 --targets t_s1k.csv --json r_s1k.json --exact-max 1024 --restarts 2000 --seed 0xD1CE2026
./addchain_check < r_s1k.json                          # exit 0, all VERIFIED minimal
```

(Targets are random; means will differ slightly per draw. The seed fixes only the engine's
stochastic search, not the target draw.)

## Frank verdict

**Nothing here is new-to-humanity.** Binary, factor, and sliding-window are textbook
constructions; the stochastic improver is a hand-rolled combination of known heuristic
ideas (Bos-Coster-style backward splitting, dictionary randomization, local deletion
search). What the campaign genuinely establishes, with independent verification:

1. On random 24–40 bit targets, a bounded stochastic search (< 0.2 s/target, 1 thread)
   strictly beats the best classical heuristic in this implementation on 52/60 targets
   (12/60 of that is deletion-repair cleanup of the classical chains themselves) — a real,
   externally verified better-than-baseline yield, same mechanism-shape as dial_three,
   scaled from ≤10-bit to 40-bit targets.
2. The requested lower-bound formula ⌈log₂n⌉+⌈log₂ν(n)⌉ was empirically refuted as a bound
   (negative gaps at proven-minimal targets) — worth knowing before anyone cites it.
3. Independent minimality proof was pushed from the prior campaign's n ≤ 1024 to
   **n ≤ 16384**, and the exact wall was located at ~2¹⁶ for single-thread ≤ 15-min budgets.

A genuine record would require: (a) targeting the curated frontier — e.g. specific n where
published tables (Flammenkamp's `l(n)` tables, Clift's exhaustive results to 2⁶⁴-ish
lengths, Scholz–Brauer special cases) list best-known chain lengths — and strictly beating
a listed value; (b) verifying against those published values, not against our own binary/
window baselines; (c) budgets far beyond 4000 restarts (Clift's exact computations run
CPU-months), or a smarter certified search; (d) independent replication. Random targets can
NEVER yield a record claim by construction: nobody curates best-known values for them, so
"beats our own classical heuristic" is the strongest honest statement — and that is what is
reported here, nothing more.

Files: engine `boundary_crossing/addchain_v2.zig`; generator `scripts/zig/addchain_gen_v2.zig`;
per-target data `results/addchain_v2_2026_07_10.csv` (118 rows: 20+20+10+8 small/probe + 60 MID);
verifier (read-only reuse) `scripts/zig/addchain_check.zig`.
