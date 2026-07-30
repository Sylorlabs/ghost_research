# Breadth scaling — out-of-closure reach vs the NUMBER of diverse parallel proposers (2026-07-10d)
> **Belongs to: Round 2026-07-10d · experiment 2 of 6 (breadth scaling law)** — [round index](research_round_2026_07_10d.md).

**Question:** H50 (`docs/research/scaling_laws_h50.md`) measured the DEPTH
axis — reach vs eval budget for ONE escalating engine — and found a hard
plateau (10/11 by ~50 evals, the 11th at 372, then exactly zero beyond).
This is its BREADTH counterpart: does out-of-closure reach grow with the
NUMBER `N` of diverse parallel proposers, at a FIXED per-proposer budget (so
total budget = N × per-proposer, i.e. literally "pump more parallel width"),
and does it plateau? A hard control (N identical copies, RNG-only diversity)
isolates whether any growth comes from mechanism DIVERSITY or merely from
QUANTITY of independent draws.

**Verdict in one line:** On the genuinely out-of-closure Battery-C set,
breadth barely pays and diversity is **not** the lever: reach rises only via
**rare stochastic needle-hits** on the handful of targets that are
*exactly representable* by the proposer's own hypothesis family, and the
**identical-copies control reached as many or more** cells than the diverse
pool (2 vs 1 at N=32). Reach is bounded by **representability, not budget** —
4 of 15 out-of-closure cells are in-family needles, 1 (C09) is provably
out-of-family (Bayes ceiling 0.534 over the entire 255×6 hypothesis space)
and returns exactly zero in every arm. Pumping `N` harvests the two
lowest-Hamming needles stochastically and then must plateau at ≤4 by
construction. This is the breadth mirror of H50's depth plateau: **quantity
is not the lever, and neither is diversity** — on this out-of-closure family.

---

## 1. Design

- **Harness:** `sparse_poly_discovery/breadth_scaling.zig` — a NEW file. No
  existing file modified. `tier8_aimed_proposer.zig` and `scaling_laws.zig`
  are reused **read-only** (imported plumbing / duplicated numeric glue for
  the same reason they each state: `certifyPublic`'s signature couples a
  single `ui.Feature` to the library, which a lens-transformed composite is
  not).
- **Reach set (the "H50-plateau set" for this round):** Battery C
  (`open_invention_tier8_battery_c.zig`), 6 targets × 3 seeds. Prior
  2026-07-10 rounds (`tier8_ablation.md`, `tier8_aimed_proposer.md`,
  `tier8_reach_gap.md`) established Battery C as the out-of-closure wall: the
  production ladder + revision-tax baseline solves only the `mod_synthesis`
  target (C08) and leaves the XOR/parity targets stuck at ~0.50 coverage.
  Confirmed here: baseline solves **C08 in all 3 seeds** and **nothing else**
  → **15 out-of-closure (seed,target) cells** are the reach denominator.
  Targets used: C01/C03 (XOR deg-4), C08 (`mod_synthesis`, in-closure
  control), C09 (inversion-parity — the proven-impossible structural
  control), C10 (parity-XOR), C11 (XOR deg-5).
- **Proposer mechanism (reused, budget-capped):** each proposer is one
  evidence-mine → per-cell-lens → greedy-mask-grow → certify pipeline from
  the aimed-proposer round: sample monomial masks (popcount 1..4) and/or
  Walsh patterns for near-miss correlation, scan 6 per-cell lenses
  {th1..th5, mod2}, greedily grow the mask under the winning lens, then
  certify against the SAME fresh trained library the production ladder uses
  (escape ≥0.90 held-out from below, R²<0.40 vs the library — identical
  thresholds/splits to `unified_invention.certify`). Per-proposer search
  budget is fixed at 40 evals (+2 unavoidable certify fits).
- **Diversity axes (by construction, documented in the harness header):**
  A. **family subset** {mono_focus, walsh_focus, balanced, dual_anchor} —
  which evidence family the proposer mines and anchors on; B. **mutation op**
  {hill_climb, first_improvement, random_restart} for the grow phase;
  C. **seed/RNG** — an independent splitMix64 stream per
  (pool_seed,target,arm,proposer_index); D. **escalation/anchor order**
  {mono_then_walsh, walsh_then_mono} (also the lens tie-break). Proposer
  `i`'s (family,mutop,order) is assigned **deterministically** by cycling
  `i % {4,3,2}` — so the N-ladder is an exact reproducible **prefix union**:
  the first `N` proposers are the same across all rungs, and every
  `N ∈ {1,2,4,8,16,32}` is a prefix-read of ONE 32-proposer pass (no
  resampling, no extra cost — the standard way to build a pass@N curve).
- **The identical control** uses the SAME RNG-seed formula (RNG-diversity
  magnitude held equal) but **pins family/mutop/order to entry 0** for every
  proposer. Because proposer index 0 is (mono_focus, hill_climb,
  mono_then_walsh) in *both* arms, the two arms are **mechanism-identical at
  N=1** and diverge only in mechanism composition as N grows — a clean
  isolation of "mechanism diversity" at fixed per-proposer budget and fixed
  RNG-diversity.
- **Depth reference (same file, same battery):** a single `exhaustive_depth`
  proposer per cell that enumerates the FULL hypothesis space — all 162
  monomial masks + all 256 Walsh patterns + all 6 lenses + a generous
  48-eval grow (475 evals in one attempt) — the "spend the budget as ONE big
  attempt" contrast to "spread it over many small ones".
- **Seeds:** the 3 standard Battery-C seeds
  (`0xF0235A11CE0FF1CE`, `0xC1B10D20260706`, `0xC2B10D20260707`).
- **Threads:** single-threaded (greedyFit heap-backed since 67fdd13).
  `N` proposers are simulated in-process, sequentially — not `N` OS threads.
- **Cost:** 427.5 s wall for the full sweep (well under the 15-min bound),
  Zig 0.14.1, `zig build-exe breadth_scaling.zig -O ReleaseFast`, CPU-only.
- **Data:** `results/breadth_scaling_2026_07_10.csv` (249 data rows).

---

## 2. The breadth curve

Union reach = number of the **15 out-of-closure cells** where **at least one**
of the `N` proposers produced a certified escape. `sum_cert` / `sum_novel`
count certifying proposer instances (multiplicity); `sum_evals` is the
battery total across all 15 cells (= N × per-proposer × 15).

### Diverse pool (4 families × 3 mutops × 2 orders, cycled)

| N | union reach /15 | Σ certified | Σ novel | Σ evals |
|--:|----------------:|------------:|--------:|--------:|
| 1  | **1** | 1 | 1 | 630    |
| 2  | **1** | 1 | 1 | 1,260  |
| 4  | **1** | 1 | 1 | 2,520  |
| 8  | **1** | 1 | 1 | 5,040  |
| 16 | **1** | 1 | 1 | 10,080 |
| 32 | **1** | 1 | 1 | 20,160 |

### Identical control (all proposers pinned to mechanism 0; RNG-only diversity)

| N | union reach /15 | Σ certified | Σ novel | Σ evals |
|--:|----------------:|------------:|--------:|--------:|
| 1  | **0** | 0 | 0 | 630    |
| 2  | **0** | 0 | 0 | 1,260  |
| 4  | **0** | 0 | 0 | 2,520  |
| 8  | **0** | 0 | 0 | 5,040  |
| 16 | **1** | 1 | 1 | 10,080 |
| 32 | **2** | 3 | 3 | 20,160 |

### Distinct closures spanned

Certifying proposers were clustered by (family, chosen-lens). Because total
certifications are ≤3 in every arm, `distinct_closures` is degenerate: 1 for
diverse (all certs share the mono_focus+mod2 cluster) and 1 for identical
(mono_focus+mod2 only, by pinning). No arm spanned more than one behavioral
closure — there is not enough certified reach here to cluster.

### Which cells, and at what N (per-cell first-reach)

| arm | cell reached | first N | representable? |
|-----|--------------|--------:|----------------|
| diverse   | seed …707 / C10 parity-XOR 0x0F | **1**  | exact (mask 0x0F, mod2) |
| identical | seed …707 / C01 XOR 0x0F         | **16** | exact (mask 0x0F, mod2) |
| identical | seed …707 / C10 parity-XOR 0x0F  | **32** | exact (mask 0x0F, mod2) |
| exhaustive_depth | — (0 cells) | — | — |

Every reach is a genuine solve on an **exactly-representable** target
(verified §4), not a certifier artifact. No arm ever reached C03, C09, or
C11.

### Marginal reach per doubling of N

| doubling | diverse Δreach | identical Δreach |
|----------|---------------:|-----------------:|
| 1→2   | 0 | 0 |
| 2→4   | 0 | 0 |
| 4→8   | 0 | 0 |
| 8→16  | 0 | **+1** |
| 16→32 | 0 | **+1** |

Diverse is **flat** (it caught its single needle at N=1 by RNG luck and
never grew). Identical rises **+1 per doubling at the top** — but each
additional cell costs ~5,000–10,000 evals (Σevals 5,040→10,080→20,160 for
0→1→2 cells), i.e. **~10⁴ evals per additional out-of-closure cell**.

---

## 3. Diverse-vs-identical control — the key result

**Diversity did not beat quantity. If anything, quantity won.** At N=32 the
**identical** pool reached **2** cells (3 certifications) versus the diverse
pool's **1** cell (1 certification). The two arms each caught one needle the
other missed (identical got seed-707/C01; diverse got seed-707/C10 earlier),
so the ordering is within the noise of 1–3 total needle-hits — but the honest
reading is unambiguous: **spreading 32 proposers across 4 families × 3
mutation ops × 2 orders did not out-reach pinning all 32 to the single
best-matched mechanism.**

Why quantity ≥ diversity here: the reachable targets are pure XOR/parity, for
which **only** a monomial-seeded, mod2-lens proposer can win; the other
diversity axes (walsh_focus, the threshold lenses th1..th5, dual-anchor's
Walsh grow) are structurally wasted on parity, so diversity *dilutes* the
count of effective draws. Identical, by pinning to mono_focus + full lens
scan (which includes mod2), spends every one of its 32 draws on the only
mechanism that can hit the needle — and RNG diversity alone (a coupon-
collector over independent evidence-argmax + grow trajectories) is what
accumulates the hits. **On this out-of-closure family, neither diversity nor
quantity is a structural lever; both merely harvest low-probability exact-mask
coincidences, and the un-diversified pool harvests them at least as
efficiently.**

(The control is clean because the arms are mechanism-identical at N=1 — the
N=1 diverse-vs-identical difference is *pure RNG*: diverse's proposer-0 draw
happened to land on seed-707/C10, identical's did not. Everything above N=1
isolates mechanism composition at fixed per-proposer budget.)

---

## 4. Plateau analysis — reach is bounded by representability, not budget

The 15 out-of-closure cells decompose structurally (verified by exhaustive
brute check over the entire 255-mask × 6-lens hypothesis space, 3,000-grid
sample):

- **Exactly representable needles (C01, C03, C10, C11):** `composed(mask,
  mod2)` reproduces the target with **1.000 accuracy** at the true mask
  (0x0F / 0x55 / 0x0F / 0x37). These are *in-family* — reachable in
  principle, but the proposer must **locate the exact true mask** under the
  mod2 lens. For a pure parity target every non-true mask scores ~0.50 on the
  noisy val split, so the evidence argmax is at chance and the mask landscape
  is **flat with a single spike**: greedy grow only finds the spike from
  Hamming-distance 1. Hitting it is a low-probability stochastic event per
  proposer — hence the coupon-collector reach curve.
- **Provably out-of-family (C09, inversion-parity):** the BEST accuracy over
  **all 255 masks × 6 lenses** is **0.5343** ≈ chance. No present or future
  member of the mask+lens family can separate it (the Bayes-ceiling
  impossibility from `tier8_reach_gap.md`, re-derived here). C09 returns
  **exactly 0 in every arm and every N**, including the 475-eval exhaustive
  attempt — the built-in **certifier-soundness control**: the certifier is
  not rubber-stamping noise, it correctly never certifies the impossible
  target.

Therefore reach is **capped at ≤4 of 15 cells by construction**, independent
of `N`. The measured curves confirm it: diverse plateaus immediately at 1;
identical is still climbing at the top doubling (1→2) but toward the same
≤4 ceiling, at ~10⁴ evals per cell. **More parallel width cannot open C09,
C03, or C11 in the measured draws** — the reachable-in-principle gains are
confined to the two lowest-Hamming needles (the 0x0F mask), harvested
stochastically, then the curve must flatten. This is the breadth-axis
statement of the Closure Principle: quantity buys the cheap in-family
coincidences and nothing outside the family.

---

## 5. Depth vs breadth — head-to-head at equal budget

Two ways to spend the same evals on a stuck out-of-closure target:

| strategy | evals | cells reached /15 |
|----------|------:|------------------:|
| **Depth** — one exhaustive attempt (all 162 mono + 256 Walsh + 6 lenses + 48-grow) | 475/cell | **0** |
| **Breadth** — N=8 small proposers | 336/cell | diverse **1**, identical 0 |
| **Breadth** — N=16 small proposers | 672/cell | diverse **1**, identical **1** |

**In the needle regime, breadth (many small attempts) beats depth (one big
attempt).** The exhaustive attempt *covers the whole hypothesis space* yet
reaches 0, because the bottleneck is not coverage — it is **selection noise**:
on a parity target the held-out-accuracy signal that picks the mask is at
chance for every candidate until you land the exact needle, so one big
enumerating attempt makes ONE chance-level selection and commits to it. `N`
independent small attempts make `N` independent selections, and **independent
re-selection is exactly what beats a chance-level selection signal**
(coupon-collector). This is the crisp complement to H50: H50 showed one
engine's *depth* escalation plateaus hard on Battery B; here the *depth-style
single-shot* underperforms *breadth* on Battery C precisely because the
Battery-C wall is a selection-noise wall, not an escalation-stage wall.

**But both are dominated by H50's in-closure escalation.** Cross-referencing
`scaling_laws_h50.md`:

| | H50 depth (Battery B) | this breadth (Battery C) |
|---|---|---|
| in-closure solves | 10/11 at ~50 evals (~5 evals/solve) | C08 solved by baseline, 0 proposer evals |
| the ONE hard out-of-closure solve | B11 at 322 evals (mod/pipeline stage) | — needle reach only |
| out-of-family reach | (N/A — Battery B is all reachable) | 0 (C09 provably impossible) |
| cost of an out-of-closure gain | 322 evals (one escalation) | ~10⁴ evals per needle cell (breadth) |
| ceiling | hard: 372 evals, then exactly 0 | structural: ≤4/15 cells, then flat |

At equal total budget the ranking is: **in-closure escalation (≈5 evals/solve)
≫ breadth needle-search (≈10⁴ evals/cell) > single-shot depth (0)**. Breadth
buys reach that depth-single-shot cannot, but ~3 orders of magnitude less
eval-efficiently than staying inside the closure — and neither axis reaches
the out-of-family target. **Pumping width goes *slightly* further than
pumping a single deep attempt, and then plateaus for the same reason depth
does: the closure boundary is a representability boundary, and no amount of
budget on either axis crosses it.**

---

## 6. Honest limitations

1. **Tiny flip counts.** Total certified out-of-closure reach across the whole
   experiment is 1 (diverse) / 3 (identical) instances over 15 cells × 6
   rungs. The diverse-vs-identical *ordering* (2 vs 1 at N=32) should be read
   as "diversity did not help", not as "quantity provably wins" — the
   magnitudes are too small to rank the two arms beyond a wash.
2. **Reachable set is small by construction.** Only 4 of 15 out-of-closure
   cells are in the proposer's hypothesis family; 1 is provably outside it.
   This bounds reach at ≤4 independent of N — the plateau is partly *designed
   in* by choosing an out-of-closure battery. That is deliberate: the
   question is whether width crosses a *known* closure boundary, and it does
   not.
3. **Per-proposer budget = 40 search evals** is small; a larger per-proposer
   budget would raise per-draw hit probability (fewer, deeper draws — the
   depth axis) and is exactly the trade H50 already measured on Battery B.
   This run holds per-proposer budget fixed *by design* so that total = N ×
   fixed isolates the width axis.
4. **The certifier is the harness-local numeric mirror** (same
   hyperparameters/splits as `unified_invention.certify`), as in
   `tier8_aimed_proposer.zig`, because a lens-transformed composite is not a
   `ui.Feature`. Composites are export artifacts; they are never inserted
   into the live library. The `novel` flag is the aimed round's correlation-
   proxy tax signal, not the full `eqtax.gatePromoteEx` gate.
5. **Determinism.** All PRNGs are locally seeded; the run is reproducible bit
   for bit. The `--smoke` mode (1 seed, 2 targets, N≤4) reproduces the same
   zero-reach behaviour on C01/C03.
6. **3 seeds** vary grid data and the fresh trained library; the Battery-C
   target *templates* are fixed (as in every Tier-8 harness this round). The
   curve is "the breadth curve of this out-of-closure family", not of a broad
   task distribution.

---

## 7. Reproduce

```bash
cd sparse_poly_discovery
zig build-exe breadth_scaling.zig -O ReleaseFast   # zig 0.14.1
./breadth_scaling            # full sweep, ~7 min single-threaded
./breadth_scaling --smoke    # 1 seed, 2 targets, N<=4 — ~1 min timing check
# CSV -> results/breadth_scaling_2026_07_10.csv  (249 data rows)
```

Cross-references: `docs/research/scaling_laws_h50.md` (the depth curve this
mirrors), `docs/research/tier8_aimed_proposer.md` (the proposer mechanism and
the 15%/attempt needle-hit rate), `docs/research/tier8_reach_gap.md` (the C09
family-level impossibility / Bayes ceiling), `docs/research/tier8_assembled.md`
(the production ladder + revision baseline reproduced here).
