# LABS round 2026-07-10b — richer moves for the 12 even-N / {61,63,64} misses

**Status:** built, measured, independently re-verified. 2026-07-10 (round b, same day as the
base campaign).
**Verdict up front:** partial gap-closing, as expected. **2 of 12** misses fully closed
(N=44, 50), **3 of 12** partially closed (N=56, 60, 63), **3 of 12** unchanged (N=48, 61, 64),
and **4 of 12 came in worse than yesterday's number** (N=52, 54, 58, 62) — a genuine,
reported regression, not hidden. The EXTRAORDINARY-NEEDS-SCRUTINY flag never fired: no
claimed value ever beat best-known. Every even-N "skew-symmetry analogue" tested
(mirror-pair with alternating or constant sign) was **decisively worse** than plain
unrestricted search at equal budget — the honest answer to "what's the even-N analogue of
skew-symmetry" is **we didn't find one; none of the three tried here reproduce the odd-N
mechanism's benefit.**

## Recap: what yesterday found and why this round exists

Yesterday's campaign (`boundary_crossing/labs_campaign.zig`,
`docs/research/labs_campaign.md`) matched the recalled best-known merit factor for every
N ≤ 43 and every odd N ≤ 59, using a single-flip tabu search plus — for odd N only — a
tabu search restricted to **skew-symmetric** sequences (`s_{c+d} = (-1)^d s_{c-d}`,
`c=(N-1)/2` an *integer* center). It missed on exactly 12 lengths: all even N ≥ 44
(44,48,50,52,54,56,58,60,62,64) plus odd N ∈ {61,63}. The diagnosis: skew-symmetry needs an
integer center, which only exists for odd N — even N has no unpaired middle element, so the
exact mechanism that closed every odd-N gap has no direct analogue.

This round attacks those 12 misses with three additional move classes, per the brief:
(a) a memetic layer, (b) pair/triple-flip neighborhoods with incremental O(N) updates, and
(c) even-N structural-restriction hypotheses that generalize the skew idea.

## Moves implemented

All energy/flip machinery (`computeC`, `energyFromC`, `energyDirect`, `applyFlipDelta`,
`merit`) is **copied verbatim** from `labs_campaign.zig` so any difference in outcome is
attributable to search moves, not a different (possibly buggy) energy engine.

### (b) Pair/triple-flip neighborhoods — the general machinery

The whole file is built on one algebraic fact, checked by hand: flipping position `i` twice
(with any other positions changed in between) restores `s` and `C` exactly, because the
incremental `C` array is always the *true* correlation state for the *current* `s`, not
path-dependent. This means a composite move (2 or 3 positions flipped together) can be
**probed** without committing by applying it once (mutate) and applying it again (revert,
self-inverse) — and its delta is the sum of the two component deltas, exactly, regardless
of order. This is exactly the trick yesterday's skew-pair-flip used, generalized one level:

- **single** neighborhood: every one of the `m` free indices, one flip each (`m` evals/iter).
- **pair** neighborhood: singles **plus** `m` randomly sampled *distinct* free-index pairs,
  each evaluated as one telescoped composite move (`2m` evals/iter).
- **triple** neighborhood: singles + pairs **plus** `m` sampled *window-bounded* triples
  (index gaps of 1..6, to keep the move "local" and bound cost — a full O(N³) triple
  enumeration is intractable at N=64). `3m` evals/iter.

Eval-cost convention (same spirit as yesterday's "a skew pair-flip costs ~4 O(N) passes but
counts as 1 eval"): a single free-flip in a paired structural mode costs ~4 O(N) passes
(apply+probe+revert+revert); a pair-of-free-index move ~8 passes; a window triple ~12 passes.
Budgets below are chosen in "evals" (matching yesterday's accounting units), not raw passes.

### (c) Structural hypotheses — even-N mirror-pair generalizations of skew-symmetry

Every raw position `i` in `[0, N/2)` is paired with `N-1-i` (full pairing, no unpaired
center — unlike odd-N skew, which pairs `[0,c)` with `(c,N)` and leaves `c` itself free).
Flipping `i` always requires flipping its mirror too (proven: negating both sides of
`s_mirror = sign * s_i` preserves the relation for *either* sign — sign only matters for
deriving the initial random derived half, not for which positions a flip must touch). Three
sign conventions were tested as competing hypotheses:

- **mirror_altern**: sign alternates by free-index parity — the closest structural analogue
  of skew's alternating `(-1)^d`. This is the *candidate* even-N analogue.
- **palindrome** (mirror_pos): constant `+1` sign, i.e. `s_i = s_{N-1-i}`.
- **antipalindrome** (mirror_neg): constant `-1` sign, i.e. `s_i = -s_{N-1-i}`.

For the two ODD misses (61, 63) the **exact classical skew-symmetric restriction** (copied
faithfully, not reinvented) is used instead, enriched with the same pair/triple
neighborhoods, so the odd-N arm gets the proven-good mechanism plus richer moves on top.

A literal "period-2 tiling" hypothesis (`s_i = s_{i+2}`) was considered and **not run**: it
would pin lag-2 correlation to its maximum possible magnitude by construction, which is
straightforwardly bad for an energy that includes `C_2²` in the sum — this is a judgment
call to not spend eval budget on an ansatz with an obvious pathology, not a measured result.

### (a) Memetic layer

Population of 10 sequences in **plain** (unrestricted) space — crossover doesn't obviously
respect a structural constraint, so this arm is kept separate from (c). Each generation: every
individual gets a short single_pass tabu burst (`60·N` evals, single+pair neighborhood,
seeded from its own current state); tournament selection (size 3) picks parents; two-point
crossover produces children; ~25% mutation flips one random bit; elitism keeps the incumbent
best; every 8th generation the worst 2 individuals (excluding the elite) are replaced with
fresh random restarts. Half the initial population is warm-started from the best sequence
found by the earlier arms (lightly perturbed for diversity); half is fresh random.

## Budgets (fixed seeds, reproducible)

Total per N is the same **order of magnitude** as yesterday's (tens of millions), split
across arms rather than concentrated in one, per N:

| arm | mode | neighborhood | budget (evals) |
|---|---|---|--:|
| plain_single_ctrl | plain | single | 5 M |
| plain_pair | plain | pair | 35 M |
| plain_triple | plain | triple (window 6) | 25 M |
| skew_pair (odd N only) | skew_odd | pair | 35 M |
| skew_triple (odd N only) | skew_odd | triple | 20 M |
| mirror_altern_pair (even N only) | mirror_altern | pair | 35 M |
| mirror_altern_triple (even N only) | mirror_altern | triple | 15 M |
| palindrome_pair (even N only) | mirror_pos | pair | 15 M |
| antipalindrome_pair (even N only) | mirror_neg | pair | 15 M |
| memetic | plain | single+pair bursts | 40 M |

**Totals: 185 M evals/N for even N, 160 M evals/N for odd N** — roughly 2.3–3x yesterday's
per-N budget (60–78 M), but thinned across 7–8 arms instead of concentrated in 1–2. This
matters for interpreting the regressions below (see "Honest accounting").

Seeds: `0xA1..0xD00D XOR n` per arm (deterministic, listed in the source). Internal soundness
guard (incremental E vs from-scratch E) re-checked after every restart in every arm across
every run — **never fired** (no `INTERNAL ERROR` in any of the three sub-runs' logs).

## Reproduce

```bash
zig build-exe boundary_crossing/labs_even_n.zig -O ReleaseFast -femit-bin=/tmp/claude-1000/labs_even_n
# single-threaded; full 12-length budget is ~17 min end to end, so split by --ns= into
# groups that each finish well under the 15-min/run cap (measured: ~5.4-6.1 min each):
/tmp/claude-1000/labs_even_n --div=1 --ns=44,48,50,52 --csv=/tmp/g1.csv --json=/tmp/g1.json
/tmp/claude-1000/labs_even_n --div=1 --ns=54,56,58,60 --csv=/tmp/g2.csv --json=/tmp/g2.json
/tmp/claude-1000/labs_even_n --div=1 --ns=61,62,63,64 --csv=/tmp/g3.csv --json=/tmp/g3.json
# (merge the 3 CSVs/JSONs -> results/labs_even_n_2026_07_10.{csv,json}; done for this run)
zig build-exe scripts/zig/labs_check.zig -O ReleaseFast -femit-bin=/tmp/claude-1000/labs_check
/tmp/claude-1000/labs_check results/labs_even_n_claims_2026_07_10.json   # exit 0 = all verified
```
`--quick` (budgets /200) gives a ~5 s smoke run; `--div=N` scales all budgets by `1/N` for
timing experiments; `--isolate-mode=MODE --isolate-n=N --isolate-budget=B` runs one
structural mode standalone with a *fresh* global-best (used for the order-independence check
below, not part of the main campaign).

Measured wall times (single-threaded, this machine): N=44 alone = 72.0 s, N=64 alone = 100.7 s
at full (div=1) budget — consistent with ~1.6 s/unit-N for the (larger) even-N budget and
~1.4 s/unit-N for the (smaller) odd-N budget. The three `--ns=` groups above (run as two
processes concurrently for the first two, ≤2 threads total, then the third sequentially)
took 322 s, 368 s, and 347 s respectively — all comfortably inside the 15-minute cap.

## Results — the 12-length table

Status legend: **FULLY CLOSED** = new E equals recalled best-known E. **PARTIAL** = new E
strictly between yesterday's E and best-known E. **NONE** = new E equals yesterday's E
(no change). **REGRESSED** = new E is *worse* than yesterday's (still ≤ best-known, so not
extraordinary, just a worse heuristic result this round) — reported honestly, not hidden.

| N | yest. E/F | new E/F | known E/F | gap status | won by |
|--:|---|---|---|:--|:--|
| 44 | 126 / 7.6825 | **122 / 7.9344** | 122 / 7.9344 | **FULLY CLOSED** | plain_pair |
| 48 | 160 / 7.2000 | 160 / 7.2000 | 140 / 8.2286 | NONE (unchanged) | plain_pair |
| 50 | 161 / 7.7640 | **153 / 8.1699** | 153 / 8.1699 | **FULLY CLOSED** | plain_triple |
| 52 | 174 / 7.7701 | 178 / 7.5955 | 166 / 8.1446 | **REGRESSED** (gap widened 8→12) | plain_triple |
| 54 | 199 / 7.3266 | 207 / 7.0435 | 175 / 8.3314 | **REGRESSED** (gap widened 24→32) | plain_pair |
| 56 | 208 / 7.5385 | **196 / 8.0000** | 192 / 8.1667 | **PARTIAL** (E-gap 16→4, 75% closed) | plain_pair |
| 58 | 229 / 7.3450 | 245 / 6.8653 | 197 / 8.5381 | **REGRESSED** (gap widened 32→48) | plain_pair |
| 60 | 254 / 7.0866 | **246 / 7.3171** | 218 / 8.2569 | **PARTIAL** (E-gap 36→28, 22% closed) | memetic |
| 61 | 230 / 8.0891 | 230 / 8.0891 | 226 / 8.2323 | NONE (unchanged) | skew_pair |
| 62 | 283 / 6.7915 | 307 / 6.2606 | 235 / 8.1787 | **REGRESSED** (gap widened 48→72) | plain_pair |
| 63 | 271 / 7.3229 | **259 / 7.6622** | 207 / 9.5870 | **PARTIAL** (E-gap 64→52, 19% closed) | plain_single_ctrl |
| 64 | 312 / 6.5641 | 312 / 6.5641 | 208 / 9.8462 | NONE (unchanged) | plain_pair |

**Scorecard: 2/12 fully closed, 3/12 partial, 3/12 unchanged, 4/12 regressed.** No claim ever
exceeded best-known (`EXTRAORDINARY-NEEDS-SCRUTINY` never printed in any of the three
sub-run logs).

Move-class win tally: **plain_pair 7/12** (44,48,54,56,58,62,64), **plain_triple 2/12**
(50,52), **memetic 1/12** (60), **skew_pair 1/12** (61 — no gain over yesterday, but held
the line), **plain_single_ctrl 1/12** (63 — see caveat below). **Structural even-N
hypotheses (mirror_altern/palindrome/antipalindrome): 0/12 wins.**

N=63's win by `plain_single_ctrl` — the smallest-budget (5 M eval) control arm — beating
every richer/bigger-budget arm is a **seed-luck flag**, not a systematic finding; it means
one lucky restart in the cheap control basin beat all the expensive arms this run. Reported
as-is, not smoothed over.

## Which even-N hypothesis is the skew-symmetry analogue? Honest answer: none of them

The task asked which even-N structural restriction (if any) is the analogue of skew-symmetry.
We tested three (mirror_altern, palindrome, antipalindrome) inside the main campaign, and
**none of them ever won at any of the 10 even lengths** — worse, grepping the yield CSV shows
they never even logged a single improving move at any length; every yield event credited to
`plain_pair`/`plain_triple`/`memetic`/`skew_pair`. That could be explained away as an
ordering artifact (they run after `plain_pair`/`plain_triple` in the arm sequence, inheriting
an already-strong shared best, so they only had to beat a tough incumbent) — so we ran a
**fair, order-independent isolation check**: each mode run standalone at N=48, fresh
`gbestE = +infinity`, identical 35 M-eval budget, no inherited head start:

| mode | isolated best E | isolated best F |
|---|--:|--:|
| plain (unrestricted, pair neighborhood) | **168** | **6.857** |
| mirror_altern (skew analogue, alternating sign) | 272 | 4.235 |
| palindrome (mirror_pos, constant +1) | 608 | 1.895 |
| antipalindrome (mirror_neg, constant −1) | 608 | 1.895 |

Unrestricted search beats every structural hypothesis by a wide margin at equal budget —
this is not an ordering artifact, the mirror-pair restrictions are **intrinsically much
worse** search spaces for LABS at even N. Palindrome/antipalindrome are especially bad
(F≈1.9, barely above random ~F=1): forcing `s_i = ±s_{N-1-i}` with a *constant* sign
creates strong self-similarity between the sequence and its own reversal, which pushes many
`C_k` values to large magnitude — the opposite of what LABS wants. `mirror_altern` is the
least-bad of the three (the alternating sign is structurally closer to skew's mechanism) but
still far behind plain search. **Unlike odd N, we did not find an even-N restriction that
reproduces skew-symmetry's benefit.** The most defensible reading of the odd/even asymmetry:
skew-symmetry's power for odd N comes from forcing *all* odd-lag correlations to *exactly*
zero via an algebraic identity tied to the integer center; the even-N mirror pairing looks
structurally similar but does not carry the same zero-forcing property (we did not
attempt to prove or disprove this algebraically — it is offered as a plausible explanation,
not a proven one), and empirically it just imposes a bad structural bias instead.

## Honest accounting: why did 4 lengths get worse than yesterday?

Total eval budget this round (160–185 M/N) is 2.3–3x yesterday's (60–78 M/N) — but it is
split across 7–8 arms instead of yesterday's 1 (even N) or 2 (odd N). For the 4 regressed
lengths (52, 54, 58, 62), *every* arm this round — including `plain_single_ctrl`, which runs
the identical single-flip-only search yesterday used, just with a 5 M budget instead of
60 M — came in worse than yesterday's dedicated 60 M-budget run. Richer neighborhoods
(pair/triple) cost more O(N) passes per candidate, so for a fixed eval budget they complete
*fewer outer tabu iterations / restarts* than a same-budget single-flip search would. Put
together: thinner per-arm budget + more expensive per-iteration moves can mean *less
effective search depth* than yesterday's simpler, fully-concentrated approach, even though
the *aggregate* eval count is higher. This is a genuine, reproducible finding (not a bug —
the internal soundness checks never fired, and independent re-verification confirms the
claimed E values), and the honest lesson for a follow-up round is: **concentrate budget in
whichever arm is winning rather than spreading it evenly across many hypotheses**, or run
each candidate hypothesis to convergence before moving to the next instead of a fixed
eval-based arm rotation.

## Independent verification

`scripts/zig/labs_check.zig` (unmodified, reused as-is) re-verifies all 12 new claims from
scratch (O(N²) direct energy, no incremental tricks, no shared code):

```
=== summary: verified=12 refuted=0 (of which optimality-not-reproven=0) ===
VERDICT: all claims independently re-verified (E/F from scratch; optimality re-proven where n <= 22)
```

Yesterday's claims file (`results/labs_claims_2026_07_10.json`) was also re-run through the
same verifier binary as a continuity check and still passes in full: `verified=63 refuted=0`.

**Refutation test** (the verifier must still say no): planted (a) a real N=44 sequence with a
false lower E (117 instead of the true 122), (b) a real N=50 sequence with one entry corrupted
to `2` (not ±1):

```
n=44: REFUTED (claimed E=117, recomputed E=122)
n=50: REFUTED (seq entry not +/-1)
=== summary: verified=0 refuted=2 (of which optimality-not-reproven=0) ===
VERDICT: REFUTED — at least one claim failed independent re-check
```

Both planted lies caught, exit code 1 confirmed. No claim in this round was ever `PROVEN`
(all 12 are `HEURISTIC` — no exhaustive tier at these lengths), so the brute-force
optimality-reproof path isn't exercised here; that's an honest scope note, not a gap in the
verifier (which still checks structural validity + E/F recomputation on every claim
regardless of status).

## Remaining distance to best-known (frank)

- 10 of 12 lengths (48, 52, 54, 56, 58, 60, 61, 62, 63, 64) remain above best-known after this
  round; only 44 and 50 are now fully closed. The worst remaining gaps by relative size are
  N=64 (E 312 vs 208, 50% above best-known) and N=63 (E 259 vs 207, 25% above) — N=64 was
  untouched by every arm tried here, N=63 only partially improved.
- The mechanism that worked for odd N (skew-symmetry) has **no even-N analogue we found**
  that reproduces its benefit; three tried, all worse than unrestricted search. This is the
  headline negative result of the round.
- Pair/triple neighborhoods on **unrestricted** search were the most reliable move class
  (won 9/12 lengths combined: plain_pair 7 + plain_triple 2), but even they only closed 2 lengths fully
  and regressed 4 relative to yesterday's simpler, budget-concentrated single-flip search —
  richness is not free, and this round's arm-splitting design diluted it.
- The honest path forward (unchanged from yesterday's frank verdict): matching the literature
  at these lengths needs a genuinely stronger and better-tuned local search (self-avoiding
  walk / lssOrel-class memetic implementations with orders of magnitude more budget and
  tuned parameters, not just added move types on the same eval budget) or the branch-and-bound
  machinery for a proven tier past N=24 — neither is a new idea, both are compute/engineering
  investments, consistent with `dial_three.md` and `addition_frontier.md`'s conclusion for
  this whole campaign line.

Files: `boundary_crossing/labs_even_n.zig` (new, standalone) ·
`results/labs_even_n_2026_07_10.csv` (yield curves, 65,798 rows) ·
`results/labs_even_n_claims_2026_07_10.json` (12 claims, independently verified) ·
reused read-only: `boundary_crossing/labs_campaign.zig`, `scripts/zig/labs_check.zig`,
`results/labs_claims_2026_07_10.json`.
See also: `docs/research/labs_campaign.md` (round a, base campaign), `dial_three.md`,
`addition_frontier.md`, repo-root `CLOSURE_PRINCIPLE.md`.
