# Breadth vs depth — does "pump more out at once" escape the H50 ceiling?
> **Belongs to: Round 2026-07-10d · experiment 1 of 6 (breadth vs depth, headline)** — [round index](research_round_2026_07_10d.md).

**Round:** 2026-07-10d, experiment D1 (headline).
**Harness:** `sparse_poly_discovery/breadth_vs_depth.zig` (new file; no existing
file modified; single-threaded, ≤2 threads honored — "parallel" proposers are
simulated sequentially in one process).
**Seeds:** the 3 standard — `0xF0235A11CE0FF1CE`, `0xC1B10D20260706`,
`0xC2B10D20260707`.
**Data:** `results/breadth_vs_depth_2026_07_10.csv` (435 data rows + header:
15 arm-summary `run` rows, 180 `proposer` rows, 240 per-target `target` rows).
**Wall clock:** ~13 min per seed on a heavily-loaded box (load 9–17); the
sweep was run one seed per invocation, each under the 15-min bound.

**Verdict in one line:** At **equal total budget**, spreading the budget across
many diverse proposers **does not reach a single target one deep proposer
cannot** — the proven out-of-closure target (C09) falls to *no one*, and
breadth's total solve count **never exceeds depth's** (12/12/12 vs 13/12/13
across three seeds). Breadth re-exhausts the same closure at lower per-target
resolution and additionally forfeits the one budget-concentration-dependent
in-closure target (B11). "Pump more diverse at once" **re-confirms the H50
ceiling; it does not escape it.** The ceiling is the grammar, not the quantity.

---

## 1. The hypothesis, made falsifiable

Micah's hypothesis: *"maybe if we pump more out at once it will go further."*
H50 (`docs/research/scaling_laws_h50.md`) already refuted the **depth** reading:
more evals on one closure buy nothing past a 372-eval hard plateau. This
experiment tests the **breadth** reading H50 never touched: at a *fixed total
eval budget B*, does a pool of **N diverse proposers each spending B/N** reach
targets a **single deep proposer spending all of B** cannot?

The falsifiable claim: *if breadth is real, at least one out-of-closure target
that depth plateaus on is reached by the diverse pool at equal total budget.*
The null (and the Closure-Principle prediction): *breadth just re-exhausts the
same closure — no better than depth, because the ceiling is the closure the
generators span, not how many generators you run.*

**The crux is equal TOTAL budget.** If breadth spends more total compute the
comparison is meaningless ("more compute helps" is trivial). This harness holds
total consumed compute equal to within **0.23%** (table §3).

---

## 2. Design

### Battery (16 targets)

- **11 standard blind-battery-B targets** (`rq1.generateBatteryB` via
  `ie.prepareBlindBatterySeed`) — the H50 in-closure battery. 10 are cheap
  in-closure solves (1–8 evals, base/forge/pair/Walsh ladder); **B11
  (inversion parity)** is the one expensive in-closure target, needing the
  ~330-eval mod/pipeline escalation (H50: 322 of the battery's 372 evals).
- **5 reach-gap targets** lifted read-only from Battery C
  (`open_invention_tier8_battery_c.zig`):
  - **C02, C04, C05, C06** — XOR-family targets *outside the base ladder's
    closure* but **probabilistically reachable** via the
    `tier8_aimed_proposer`-style evidence-mined per-cell-lens composition
    (round b measured ~17%/attempt at degree 4). These are where breadth
    *could* matter: the reach depends on which evidence mask seeds the greedy
    grow, so more independent attempts sample more of the reachable set.
  - **C09 (inversion-count parity)** — the **negative control**: proven
    *family-level* unreachable by every ladder family
    (`docs/research/tier8_reach_gap.md`, Bayes-ceiling ≈ 0.50 for all bases;
    it needs a comparison-aggregate primitive this file deliberately does not
    implement). If any arm "solves" C09, that is a bug, not an escape.

### Arms (all at equal total budget B)

- **DEPTH** — one proposer, canonical/production configuration: full 6-lens
  set, full 162-mask monomial + 256-pattern Walsh sweeps, production stage
  order, standard target order. Spends **all of B**. This is the best single
  deep tool the arc has built (H50 ladder + `tier8_aimed_proposer` composition),
  at full strength.
- **BREADTH(N), N ∈ {4, 8, 16, 32}** — N proposers, each capped at **B/N**,
  run round-robin in one process. **Union + dedup** their certified results.
  Diversity is by construction along five documented axes:
  1. **target order** — per-proposer random permutation of the 11 B-targets
     and the 5 reach-gap targets, plus a coin-flip for which block runs first
     (the dominant lever: B11 alone is ~87% of the ladder's spend, so order
     decides what gets attempted before the per-proposer cap bites);
  2. **lens subset** — which of `{th1..th5, mod2}` the composed stage searches
     (8 named subsets cycled by proposer index; `mod2` is the natural
     XOR-detecting lens, `th3` matches the base ladder's own split);
  3. **random mask/Walsh subsampling** — when the cap can't afford the full
     sweep, examine a per-proposer-seeded random subset sized to fit (a hard
     necessity at N=32, and a genuine "different random-family seeds" axis);
  4. **mutation operator** — greedy mask growth uses single-bit-flip (`flip1`)
     or adjacent-pair-flip (`flip2`) neighborhoods;
  5. **escalation order** — mod-stage before/after pair-Walsh for the
     mod-eligible B-targets.

### Equal-budget enforcement (the crux, done exactly)

DEPTH plateaus **below** its cap (consumes 2587–2635 of 3000, reproducing
H50's "can't spend more"). The fair "same total compute" is therefore depth's
**actually-consumed** evals, `B_eff`. Each breadth arm's pool budget is set to
`B_eff`; each proposer gets `B_eff/N`; a global pool counter makes the **sum
across proposers ≤ B_eff**. Atomic escalation stages (the ~330-eval
mod/pipeline) are **affordability-guarded** — a proposer fires a stage only if
its whole cost fits under the proposer's cap — so per-proposer overshoot is ≈ 0
and the arm totals land within **+6/−1 evals** of depth's consumed (§3). This
is a genuinely equal-consumed-budget comparison, not a nominal-cap one.

### Reproduce

```bash
cd sparse_poly_discovery
zig build-exe breadth_vs_depth.zig -O ReleaseFast      # zig 0.14.1
./breadth_vs_depth --pilot --seed=0                    # uncapped calibration
./breadth_vs_depth --seed=0 --budget=3000 --label=full  >  ../results/breadth_vs_depth_2026_07_10.csv
./breadth_vs_depth --seed=1 --budget=3000 --label=full --no-header >> ../results/breadth_vs_depth_2026_07_10.csv
./breadth_vs_depth --seed=2 --budget=3000 --label=full --no-header >> ../results/breadth_vs_depth_2026_07_10.csv
```

Budget B=3000 was chosen from the pilot: the uncapped canonical proposer
consumes ~2587–2635 evals and plateaus (identical to depth at cap 3000), so
3000 lets depth reach its full natural plateau while the breadth pool is held
to depth's exact consumed total.

---

## 3. Equal-budget discipline (verified)

| seed | depth consumed (B_eff) | breadth total, N=4 / 8 / 16 / 32 | max deviation |
|-----:|----------------------:|:--------------------------------:|:-------------:|
| 0 | 2587 | 2592 / 2587 / 2587 / 2593 | +6 (0.23%) |
| 1 | 2635 | 2634 / 2635 / 2635 / 2638 | +3 (0.11%) |
| 2 | 2588 | 2594 / 2593 / 2591 / 2588 | +6 (0.23%) |

Every breadth arm consumed within a quarter of a percent of what depth
consumed. The comparison is equal-total-budget by construction.

---

## 4. Headline: solves per arm at equal total budget

Total certified solves / 16 (battery-B part `B=`, reach-gap part `C=`, with the
reach-gap targets named). **Depth is the reference; breadth never exceeds it.**

| seed | DEPTH | BREADTH(4) | BREADTH(8) | BREADTH(16) | BREADTH(32) |
|-----:|:-----:|:----------:|:----------:|:-----------:|:-----------:|
| 0 | **13** (B11, C02,C06) | 11 (B11, —) | 12 (—, C02,C06) | 11 (—, C02) | 11 (—, C06) |
| 1 | **12** (B11, C05) | 11 (B11, —) | 9 (—, —) | 10 (—, —) | 12 (—, C02,C05) |
| 2 | **13** (B11, C04,C06) | 12 (B11, C06) | 10 (—, —) | 12 (—, C02,C04) | 11 (—, C04) |

(In each cell, the parenthetical lists whether **B11** — the expensive
in-closure target — was solved, and which reach-gap **C** targets were reached.
"—" for B11 means it was lost.)

**Every breadth number is ≤ the depth number for that seed.** The single tie
(seed 1, BREADTH(32) = 12 = depth) is breadth *trading* the lost B11 for two
probabilistic XOR hits (C02+C05), not exceeding depth.

### The out-of-closure question (the falsifiable core)

- **C09 (proven family-level out-of-closure): reached by NO arm, NO seed —
  0/0/0 across depth and all 12 breadth runs.** The negative control holds
  exactly. No amount of generator diversity manufactured the missing
  comparison-aggregate primitive. This is the clean confirmation that the
  ceiling is the closure the generators span.
- The reach-gap targets any arm *did* solve are **always** the
  probabilistically-reachable XOR members {C02, C04, C05, C06} — never C09.

### Does breadth reach *any* target depth doesn't?

Only in a variance sense, and only within the already-reachable closure:

- **Seed 0:** depth {C02,C06}; breadth over all arms ⊆ {C02,C06}. **Nothing
  new.**
- **Seed 1:** depth {C05}; breadth(32) reached {C02,C05}. **C02 is "new" vs
  depth** — but C02 is an in-closure XOR target (depth reaches it on seed 0);
  depth's single deterministic pass simply missed it on seed 1, and breadth's
  32 independent draws caught it.
- **Seed 2:** depth {C04,C06}; breadth(16) reached {C02,C04}. **C02 is "new"
  vs depth** — same story.

So breadth's *only* edge is a **portfolio/variance effect on the ~17%-per-attempt
probabilistic layer**: N independent, differently-seeded composition attempts
sample a different subset of the *same reachable XOR set* than depth's one
attempt. It is **not** a closure escape — the genuinely out-of-closure target
(C09) never falls, and breadth's total never beats depth because the extra
probabilistic hit is paid for by losing B11 (below).

---

## 5. Why breadth loses at equal budget — two independent mechanisms

1. **Budget fragmentation kills the expensive in-closure target (B11).** B11
   needs the ~330-eval mod/pipeline escalation in one concentrated block. Only
   BREADTH(4) (per-proposer cap 646–658 ≥ 330) can afford it; **every N ≥ 8
   loses B11** (per-cap ≤ 329 < 330). Depth wins by *concentration*: it spends
   its whole budget where the target needs it. This is a pure
   budget-distribution effect, orthogonal to closure — and it favors depth.
2. **Fragmentation also costs cheap in-closure targets when a proposer spends
   its slice on the wrong block.** Seed 1, BREADTH(8): six of eight proposers
   drew `b_first=false`, spent their ~329 evals on the expensive reach-gap
   composition block first, and had nothing left for the (nearly free)
   battery-B block — so BREADTH(8) solved only **9** battery-B targets (also
   losing B10, whose seed-1 solve needs the mod stage). The diversity axis
   itself (block order) becomes a *liability* under a tight per-proposer cap.
3. **Lower per-target resolution on the probabilistic layer.** Depth searches
   the full 162-mask + 256-Walsh sweep with all 6 lenses per reach-gap target;
   a breadth proposer subsamples masks and searches a 1–2 lens subset. Depth
   reliably reaches ~2 of the 4 XOR targets every seed; breadth's individual
   proposers reach them flakily, and the union only sometimes matches depth's
   count.

---

## 6. Honesty: is the union genuinely from diverse proposers, or one worker?

**One proposer does nearly all the work; breadth adds at most one probabilistic
target over its single best member.** Measured dominant-proposer share of the
union (max single-proposer solve-set ÷ union size):

| seed | N=4 | N=8 | N=16 | N=32 |
|-----:|:---:|:---:|:----:|:----:|
| 0 | 100% | 91.7% | 100% | 90.9% |
| 1 | 100% | 100% | 100% | 83.3% |
| 2 | 91.7% | 100% | 91.7% | 90.9% |

Ten of twelve breadth runs have a **single proposer covering ≥90%** of the
union; five are at **100%** (the union *equals* one proposer's solve-set — the
pool added nothing over its best member). Concretely (seed 0, N=8): proposer
p5 alone solved 11 of the 12-target union; the pool's total contribution beyond
p5 was exactly **one** reach-gap target (C06, from p7) — and C06 is one depth
already solves. Breadth is **not** synergistically composing complementary
diverse proposers into a larger reach; it is one proposer doing the job, plus
the occasional lucky duplicate of a target depth also reaches.

### Diversity actually achieved

The pool genuinely spanned distinct behaviors: **distinct lens-subsets that
produced a solve** ranged 1–8 of 8 (mean ~5.5; N=32 hit 7–8/8 on all seeds),
and the proposers varied across all five axes (order, lens, mask-seed, mutation
op, escalation order) as designed. **The diversity was real and it bought
nothing** — the pool spanned many *configurations of the same two closures*
(the ladder closure and the composed-lens closure), not more closures. Spanning
more configurations of a fixed closure set is exactly what the Closure
Principle says cannot reach out of it.

---

## 7. Verdict

At **equal total budget**, breadth of N diverse proposers:

- reaches **no out-of-closure target** depth cannot — the proven family-level
  target C09 falls to nobody (0/0/0), across depth and all 12 breadth runs;
- **never exceeds depth's total solve count** (12/12/12 vs 13/12/13);
- **loses** the one budget-concentration-dependent in-closure target (B11) at
  every N ≥ 8, and loses cheap targets to block-order fragmentation;
- shows its *only* edge as a variance/portfolio effect **within** the
  already-reachable probabilistic XOR layer (catching a different member depth's
  single pass missed), which is dominated by the losses above;
- is, by the dominant-share audit, **one proposer doing ~90–100% of the work** —
  no diverse-pool synergy.

**"Pump more diverse at once" re-confirms the H50 ceiling; it does not escape
it.** Breadth just re-exhausts the same closure at lower per-target resolution.
This is the important negative the round anticipated: the binding resource is
*aimed out-of-closure generators* (round b) — a genuinely new primitive family
(the round-c comparison-aggregate that alone cracks C09) — **not** the quantity
or diversity of generators over a fixed closure. The one honest asterisk: on a
*probabilistic* reach layer (targets reachable ~p per attempt), more independent
draws is a real variance play — but it samples the same reachable set, never
enlarges it, and here it is strictly dominated by the budget-concentration cost
of splitting.

---

## 8. Limitations

1. **The reach-gap layer is probabilistic, not cleanly out-of-closure.** C02/
   C04/C05/C06 are reachable by the composed-lens mechanism at ~17%/attempt, so
   depth-vs-breadth on them is partly a variance comparison. The clean
   out-of-closure signal is C09 (0/0/0). A sharper future battery would use
   several *proven* family-level targets (C09-like) rather than one, to make the
   out-of-closure count more than a single control.
2. **Eval unit is the engine's stage-granular `EvalCounter`** (same unit as
   H50); the affordability guards mean caps are respected to ≈0 overshoot, but
   the unit is coarse. Budget totals are reported as *consumed*, the honest axis.
3. **Diversity is by construction, not learned.** The five axes are
   hand-specified; a pool of *learned* diverse generators is untested here (and
   would still be bounded by the closures those generators span — the same
   argument applies).
4. **Battery template is fixed across seeds** (the round-inherited caveat): seed
   varies grid data + two monomial masks, not the target family. These are
   yield curves of this battery family.
5. **B11's loss is a budget-concentration effect, not a closure effect** — kept
   distinct in §5 so the closure verdict (C09) is not conflated with the
   fragmentation verdict (B11). Both independently favor depth.
6. **Single-machine, single-thread** ("parallel" simulated round-robin, per the
   ≤2-thread constraint). Genuinely parallel hardware changes wall-clock, not
   the equal-*total-eval-budget* result, which is hardware-independent.

## 9. Files

- Harness: `sparse_poly_discovery/breadth_vs_depth.zig` (new; `--pilot` for
  budget calibration, `--seed=N --budget=B` for the sweep)
- Data: `results/breadth_vs_depth_2026_07_10.csv`
- Read-only reuse (unchanged): `invention_engine.zig`, `open_invention_rq1.zig`,
  `unified_invention.zig`, `equivalence_tax.zig`,
  `open_invention_tier8_battery_c.zig`
- Related: `docs/research/scaling_laws_h50.md` (the depth plateau this contrasts
  against), `docs/research/tier8_aimed_proposer.md` (the composed-lens
  mechanism), `docs/research/tier8_reach_gap.md` (C09's family-level proof),
  `docs/research/research_round_2026_07_10d.md` (round index)
