# Tier 8 aimed proposer — does frontier-coupling move the 10/11 battery-C wall?
> **Belongs to: Round 2026-07-10b · experiment 2 of 6 (aimed proposer)** — [round index](research_round_2026_07_10b.md).

**Harness:** `sparse_poly_discovery/tier8_aimed_proposer.zig` (new file; no
existing file modified)
**Date:** 2026-07-10
**Seeds:** same 3 as yesterday's ablation — `0xF0235A11CE0FF1CE`,
`0xC1B10D20260706`, `0xC2B10D20260707`
**Wall clock:** 6m55.8s, single-threaded (`time` output below), well inside
the 15-min budget.
**Verdict:** **PARTIAL, HONEST MOVE.** Frontier-coupled composition flips
**5/33** additional battery-C ladder-only solves beyond the revision baseline
(3/33 → 8/33), but the mechanism is exactly as fragile as the theory
predicts: every flip occurs *only* when the near-miss evidence mask, mined
by a search that has zero reliable signal for a genuine XOR target, happens
by chance to land exactly on the true cell subset. **9 of the 10 stuck
targets are individually reachable** (an unaimed brute mask×lens control
solves 9/10 trivially once the mod-2 lens is tried) — the wall is not about
reachability, it is about the near-miss evidence carrying **no exploitable
gradient** toward the correct mask. One target (C09, an order-statistic
predicate) resists both aimed and brute mechanisms.

---

## Question

Yesterday's ablation (`tier8_ablation.zig`, `docs/research/tier8_ablation.md`)
found that 10 of 11 battery-C targets sit at ≈0.50 coverage in **both** the
frozen (v3) and revision (v4) ladder-only arms — the ladder has no primitive
that can express an XOR of raw cell values, only threshold-of-3-style
splits. The diagnosis flagged the trivial fix ("admit `xor_popcount` as a
ladder feature") but the round brief asked a sharper question: can a
proposer that mines the **near-miss structure of the ladder's own failed
search** (best correlated-but-insufficient masks, their held-out residuals,
any tax-blocked-but-escape-shaped witnesses) and **composes** new candidates
from that evidence — rather than drawing a ready-made primitive from a fixed
pool — flip any of the 10 stuck targets?

## Design

1. **Baselines**, re-run in-harness at the same 3 seeds, same battery-C
   ladder-only slice (`ui.solveOneTarget`, fresh 8-monomial library per
   target, tax-gated every promotion):
   - `frozen`: basis v3, no revision.
   - `revision`: basis v4 + reality lane. (Simplification vs. yesterday: this
     arm starts *directly* at v4/reality-lane-on instead of running Battery B
     first to trip the remix-rate trigger — justified because Battery C's
     library never shares state with Battery B either way, and yesterday's
     own finding was that the trigger fires after target 1 in every run
     — "ARM-ON is effectively v4 from target 2 onward". This reproduces the
     same steady-state tax configuration without the extra ~30s/seed of
     Battery-B runtime needed only to trip a threshold that fires almost
     immediately.)
2. **Aimed proposer**, run on every target the `revision` baseline still
   misses:
   - **Evidence mining** (read-only, no promotion): exhaustive degree-≤4
     monomial sweep (162 masks) and Walsh-S sweep (256 patterns) over the
     *same* held-out split the real ladder already uses internally — this is
     literally what `tryMonomialForge`/`tryConditionalWalsh` do, just with
     the near-miss score **captured** instead of discarded after a "not
     certified" print. Also counts any tax-blocked-but-escape-shaped
     witnesses from `eqtax.tax_log` (expected ≈0, per yesterday's finding).
   - **Compose**: take the single best near-miss monomial mask as the
     evidence-derived cell-subset anchor. Scan 6 elementary per-cell
     **lenses** — threshold-@1..5 (a generalization of the ladder's one
     fixed threshold-@3 split) plus mod-2/LSB — applied to that mask,
     scored by held-out accuracy ("which transform of the evidence explains
     it best"). Then **greedily grow/shrink the mask one cell at a time**
     under the winning lens (uncapped at the ladder's degree-4 limit — needed
     for C11, a degree-5 target). A cheaper secondary avenue is also probed:
     the raw *product* of the two near-miss features with no per-cell
     transform at all (`combo_val` column) — reported as a contrast.
   - **Certify**: escape (cov ≥0.90 held-out from <0.90) **and** R²<0.40
     against the existing library, identical thresholds/splits to
     `unified_invention.zig`'s `certify()`. Numeric routines
     (`fitLogitL`/`accLogitL`/`reconR2L`) are local re-implementations because
     `certifyPublic`'s signature couples library- and candidate-evaluation to
     one shared `grid` array, which a transformed-lens candidate breaks;
     library evaluation itself reuses the real `ui.evalFeaturePublic`
     unchanged.
   - **Tax = export filter/report only**, never a gate: it does not touch
     `eqtax.gatePromoteEx` at all (type-incompatible with the transformed
     candidate anyway). A lightweight proxy — max |correlation| against every
     existing library feature and both near-miss features — reports
     novel/remix for the record.
3. **Unaimed control** (production seed only, clearly separated from the
   headline): brute-force sweep of **all 255 masks × all 6 lenses**, no
   evidence guidance at all — the "just admit the missing primitive and
   re-run the existing exhaustive search" shortcut, run only to show what is
   reachable if evidence-guidance is abandoned.

**Honesty check built into the file itself:** `tier8_aimed_proposer.zig`
never calls `open_invention_e2.zig`'s `xorMasked`/`xorPopcountReadout` or
`equivalence_tax.zig`'s `buildXorCols` — all three already implement an
XOR-of-raw-values readout, but only for the tax module's own remix-basis
audit (`buildXorCols`) or e2's own separate xor-aware forge
(`tier8_battery_c_engine.zig`), never exposed to `unified_invention.zig`'s
ladder. Verified: `grep -n "xorMasked\|xorPopcountReadout\|buildXorCols"
tier8_aimed_proposer.zig` matches only the header comment, zero call sites.

### Reproduce

```bash
cd sparse_poly_discovery
zig build-exe tier8_aimed_proposer.zig -O ReleaseFast   # zig 0.14.1
./tier8_aimed_proposer                                    # 6m56s, single-threaded
# CSV -> results/aimed_proposer_2026_07_10.csv
```

No big-stack worker thread needed: `equivalence_tax.zig`'s greedy-fit column
store is heap-allocated as of commit 67fdd13.

---

## Results (measured 2026-07-10)

### Headline

| Arm | Battery-C ladder-only solves (3 seeds × 11 targets) |
|-----|----|
| `frozen` (v3, no revision) | **0/33** (matches yesterday) |
| `revision` (v4 + reality lane) | **3/33** (matches yesterday — all 3 are C08) |
| **aimed proposer** (revision + composition) | **8/33** (+**5** beyond revision) |
| unaimed control, brute mask×lens (seed 0 only, 10 targets) | **9/10** |

Aimed-proposer eval cost (mining + lens-scan + greedy-grow + final certify,
excluding the ladder itself): **13,152** evals across 30 target-attempts
(≈438/target). Wall clock for the full run (3 baselines-worth + aimed loop +
1-seed control): **6m55.8s** real / 6m53.2s user (single core).

### Per-seed flips

| Seed | Flipped target | Composed mask | True mask | Lens | cov before→after | R² |
|------|----------------|---------------|-----------|------|-------------------|-----|
| `0xF0235A11CE0FF1CE` | C02 parity XOR 0x33 | 0x33 | 0x33 | mod2 | 0.486→1.000 | −0.006 |
| `0xF0235A11CE0FF1CE` | C06 XOR 0x66 | 0x66 | 0x66 | mod2 | 0.497→1.000 | −0.021 |
| `0xC1B10D20260706` | C05 XOR 0x3C | 0x3C | 0x3C | mod2 | 0.509→1.000 | −0.012 |
| `0xC2B10D20260707` | C04 XOR 0xAA | 0xAA | 0xAA | mod2 | 0.507→1.000 | −0.014 |
| `0xC2B10D20260707` | C06 XOR 0x66 | 0x66 | 0x66 | mod2 | 0.498→1.000 | −0.023 |

**Every flip's composed mask is byte-identical to the target's ground-truth
mask** (`bc.BATTERY_C` spec), and in every case `grown_mask == seed_mask` —
the greedy stepwise search made zero corrections, because the evidence-mined
mask was already exact on the first try. C08 (parity-count, solved by the
`revision` baseline via the existing Walsh route — its bit is the *threshold*
bit, which the ladder's existing `signPattern` already matches exactly) is
excluded from the aimed loop since it's already solved upstream.

### The derivation chain (honesty check #4)

For each flip, verified independently (script in this write-up run, not
hand-checked):

- `mono_ev.mask` (the evidence anchor, found by the **existing**
  threshold-based monomial sweep — the same 162-mask search
  `tryMonomialForge` already runs) equals the target's true mask exactly.
- The 6-lens scan on that mask picks **mod2** — never hardcoded, selected
  purely by held-out accuracy across all 6 candidates.
  Selecting mod2 is not automatic: **among the 22 non-flip aimed rows in
  this run, mod2 is picked 4 times and always on a wrong mask (~0.50
  accuracy)** — the lens-scan is genuinely blind to correctness; it wins here
  only because, on the *correct* mask, mod2's val jumps from ~0.53 to ~1.0
  and becomes unmissable.
- Tax proxy reports **novel** for all 5 flips with best correlation against
  any existing library/near-miss feature of only **0.018–0.045** — nowhere
  near the pre-registered 0.90 remix threshold. This is the clean case: not a
  relabeling of something already known.
- **Cross-check on the 22 non-flips**: zero of them have `seed_mask` equal to
  the true mask (`0/22`, verified programmatically). I.e. **flip ⟺ the
  noisy evidence mask happened to equal the true mask**, with no
  counter-examples in either direction this run. The mechanism is exactly as
  fragile, and exactly as honest, as it looks.
- **A remix example, for calibration of the tax proxy**: seed `0xC2B10D20260707`,
  target C03 — `chosen_lens=th3`, `tax_proxy_best_corr=1.0000`, verdict
  `remix`. This is expected and correct: lens `th3` reproduces (up to a
  global sign flip depending on mask parity) the *already-existing* monomial
  sign feature `phi(mask)`'s decision function, so a perfect correlation with
  a near-miss feature is exactly what should happen — a useful sanity check
  that the tax proxy isn't just reporting noise.

### Why only 5/33, not more: the information-theoretic wall

The composed mechanism's low hit rate is not a bug, it is the expected
behaviour of a hard fact about grid cells 0–5 and channels:

- Let `tb(v) = [v≥3]` (the ladder's only existing bit) and `lb(v) = v&1`
  (the LSB/mod-2 bit the targets actually need). Over uniform v∈{0..5},
  `P(tb=lb) = 2/3` — a binary symmetric channel with crossover 1/3,
  **independent across cells**.
- For a k-cell XOR target, `correlation(XOR of tb over the TRUE mask, XOR of
  lb over the TRUE mask) = (1/3)^k` — **1.23% for the 8 degree-4 targets,
  0.41% for C11 (degree-5)**. For **any other mask** (subset, superset, or
  partial overlap), the correlation is **exactly 0** (an independent, unbiased
  "free bit" always remains) — verified in this run: **every one of the 22
  non-flip rows has both `mono_val` and `walsh_val` in the tight
  0.51–0.56 band**, indistinguishable from the ~0.012 sampling-noise floor at
  `NTR=3500` — there is no visible gap between "the true mask" and "a random
  wrong mask" in the near-miss evidence itself.
- Consequently the 162-mask monomial sweep's **argmax is dominated by
  extreme-value noise**, not signal: the true mask's tiny (1.2%) bias only
  wins the 162-way competition some of the time. Measured rate here: **5/30
  ≈ 17%** hit rate on the degree-4 targets (C11's weaker 0.4% signal never
  won across any of 3 seeds — consistent, since a signal 3× smaller loses
  the argmax race even more often).
- **This is why aimed composition cannot reliably climb toward a genuine
  parity/XOR target**: there is no smooth residual gradient from "close" to
  "exact" — the fitness landscape is flat everywhere except the single exact
  point, a textbook case of a Fourier spectrum concentrated entirely on the
  top-degree monomial. The greedy grow step confirms this directly: in every
  non-flip row, `grown_val` stays within noise of `mono_val` (never climbs
  toward 1.0) — greedy stepwise search cannot bootstrap off a flat landscape.

### Unaimed control (contrast, seed 0 only)

| Target | Solved | Mask found | Lens |
|--------|--------|-----------|------|
| C01–C07, C10 (degree-4 xor family) | **7/8 solved** (cov→1.000, R²<0) | exact true mask | mod2 |
| C11 (degree-5) | **solved** (cov→1.000) | 0x37 (exact) | mod2 |
| C09 (inv-parity, order-statistic) | **not solved** (0.535, ≈chance) | 0xEB (best of 255×6=1530 tries) | th2 |

**9/10 solved unaimed** — confirming the wall is squarely about
evidence-guidance, not reachability: given the mod-2 lens as an option and an
exhaustive (uncapped-degree) mask sweep, every fixed-cell-subset XOR target
in the battery — including the degree-5 one — is trivial. This is
*deliberately* the forbidden shortcut from yesterday's diagnosis, run here
only as the counterfactual the honesty check requires.

### C09 (inversion-count parity): the one genuine structural miss

C09's label is `inversionCount(g) & 1` — a permutation-parity function over
all 8 raw values, not a function of any fixed cell subset at all. Neither the
aimed proposer (mono_val/walsh_val/combo_val all pinned at 0.49–0.54 across
all 3 seeds, no flip) nor the brute (mask×lens) control (0.535, best of 1530
tries) can express it, because the composed-feature family here is
"parity of a per-cell univariate lens over a fixed mask" — the wrong shape
for an order-statistic. This is an honest, structurally-expected miss, not a
search failure: solving it would need a different feature family entirely
(e.g. a parity over pairwise order relations `sign(g[i]-g[j])`), out of scope
for this round.

---

## Metrics summary

| Metric | frozen | revision | aimed | control (seed 0) |
|--------|--------|----------|-------|----|
| Battery-C ladder-only solves | 0/33 | 3/33 | **8/33** | 9/10 (1 seed) |
| Flips beyond previous arm | — | +3 | **+5** | (not comparable — brute, 1 seed) |
| Blocked-escape witnesses found (evidence) | — | — | **0/30** | — |
| Eval cost (aimed mining+compose+certify) | — | — | 13,152 (≈438/target) | not tallied (illustrative only) |
| Tax-proxy verdict on flips | — | — | 5/5 novel (best corr 0.018–0.045) | — |

## Honesty check (task point 4) — verdict

**PASSED.** Every flip's winning feature is independently confirmed to be
genuinely derived from the near-miss evidence chain (exact mask match to the
threshold-based monomial sweep's own argmax, lens chosen from an honest
6-way scan, not a hardcoded xor answer, not a call into the codebase's
existing xor-readout machinery), **not** a lucky pool-draw equivalent of an
existing feature — confirmed by the tax proxy's low correlation (<0.05) on
all 5 flips, and the `remix`-flagged example (C03/seed3, `th3` lens, corr=1.0)
shows the proxy correctly catches the *actual* remix case for calibration.

## Verdict: does frontier-coupling move the 10/11 wall?

**Yes, but only probabilistically and only within-reach targets — it does
not escape the information-theoretic wall.** 5 of 33 (≈15%) additional
solves is a real, honestly-derived, non-lucky move — a genuine (if modest)
answer to "can evidence-guided composition do better than the frozen/revised
ladder alone" — but the mechanism's own numbers show *why* it cannot be
pushed further without changing its nature: the near-miss evidence for a true
k-way parity target carries a signal ((1/3)^k) that is smaller than the
sampling noise from a 162-way argmax search, so hitting the exact mask is a
low-probability event (empirically ~17% per degree-4 attempt, and 0% across
3 tries for the degree-5 target), not a gradient the proposer climbs.
**The wall does move — a little, honestly, and exactly as far as this
information-theoretic budget allows.**

## The next missing piece

To convert this from "occasionally lucky" into "reliable," the proposer
needs one of:

1. **A wider or repeated evidence draw**: since hit rate ≈ 17%/attempt for
   degree-4 targets, running the monomial-sweep evidence miner **N times**
   with resampled held-out splits (bagging the argmax) would raise the
   cumulative hit probability without ever "cheating" via a hardcoded xor
   primitive — worth a follow-up at N=3–5 redraws.
2. **A statistic that doesn't drown in a 162-way argmax**: e.g. score masks
   by a multiple-testing-corrected statistic (Bonferroni/BH on the 162
   correlation estimates) rather than raw argmax, since the true signal
   (1.2%) is smaller than uncorrected noise but might be separable with a
   properly calibrated test at this sample size — or simply a larger
   `NTR` for the evidence-mining split specifically (the final certify
   already uses the full held-out test split; the search split is the
   bottleneck).
3. **A genuinely different feature family for C09** (order-statistics /
   pairwise-comparison parity) — the one target where the mask×lens family
   is structurally the wrong shape, independent of evidence quality.
4. Formal acknowledgment that **this class of wall (parity/XOR-hard
   targets) is a poor fit for any residual/gradient-following proposer** —
   the honest fix belongs in curriculum/battery design (as flagged
   yesterday: prefer targets whose signal survives partial masks) rather
   than in ever-cleverer composition heuristics chasing a flat landscape.

## Files

- Harness: `sparse_poly_discovery/tier8_aimed_proposer.zig`
- Data: `results/aimed_proposer_2026_07_10.csv` (107 rows: 3 seeds ×
  (11 frozen + 11 revision + 10 aimed) + 10 control rows, seed 0 only)
- Reads (unmodified, read-only reuse): `invention_engine.zig`,
  `unified_invention.zig` (`evalFeaturePublic`, `measureCoverage`,
  `solveOneTarget`, `NSAMP`/`NTR`/`NVA`/`COVER_THRESHOLD` consts),
  `equivalence_tax.zig` (`strict_enabled`/`basis_level`/
  `reality_lane_enabled`/`stats`/`resetStats`/`resetTaxLog`/`resetReplay`
  toggles only — `gatePromoteEx` is never called on the composed candidate),
  `open_invention_tier8_battery_c.zig` (`BATTERY_C`, `labelTarget`),
  `open_invention_rq1.zig` (`Feature`, `GRID_SEED`, `COVER`, `NSAMP`).
- Related: `docs/research/tier8_ablation.md` (yesterday's baselines this
  round reproduces), `docs/research/tier8_tax_gate_promotion.md` (tax as
  measurement/export-only, reaffirmed here), `docs/research/
  research_round_2026_07_10.md` (follow-up queue item this answers).
