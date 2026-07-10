# H50-adjacent — Scaling laws: invention yield vs eval budget (2026-07-10)

**Question:** How do battery solves and genuinely-novel (tax-surviving) promotions
scale with eval budget on the production invention engine — and where is the
plateau? This is the measured basis for any efficiency comparison against
AlphaEvolve-style LLM-sample-driven discovery systems.

**Verdict in one line:** The yield curve is steep then **hard-saturated**: 10/11
solves by ~50 engine-evals (~19 CPU-s), the 11th solve costs a further ~322 evals,
and beyond 372 evals additional budget consumes **nothing** and yields **zero** —
the ladder is exhausted, not merely diminishing. Novel-promotion yield saturates
even earlier (by ~50 evals).

---

## 1. Design

- **Engine:** the production 11/11 blind-battery invention engine
  (`sparse_poly_discovery/invention_engine.zig` ladder: frozen monomials →
  unified escalation (forge/pair/Walsh/menu/world) → mod/pipeline → pair/Walsh),
  run with the **strict equivalence tax enabled** (basis v4,
  `equivalence_tax.zig`).
- **Harness:** `sparse_poly_discovery/scaling_laws.zig` — a NEW file; no
  existing file was modified. It ports `prepareBlindBatterySeed` (battery seed
  parameterized) and `solveBlindTarget` (hard budget gate added before each
  ladder stage) and imports everything else unchanged.
- **Budget cap ladder:** {6, 12, 24, 48, 96, 384, 1536} engine-eval units,
  log-spaced (×2, ×4 at the top), straddling the observed full-battery
  consumption of 372 units.
- **Seeds:** 4 seed pairs (grid seed, battery seed); seed 0 is the canonical
  production pair `(0xF0235A11CE0FF1CE, 0x0E1B10D20A11CE01)`.
- **Threads:** 1 worker thread (256 MB stack) + idle main = 2 total.
  Single-threaded compute.
- **Build:** `zig build-exe scaling_laws.zig -O ReleaseFast`, Zig 0.14.1.
- **Machine:** AMD Ryzen 5 5600X (6C/12T), 16 GB RAM, CPU-only.
- **Timing:** both wall seconds and **process CPU seconds via getrusage** are
  recorded. The box was heavily loaded by unrelated jobs during the sweep
  (load 11–17 on 12 threads), so CPU seconds are the trustworthy cost axis;
  per-run wall ≈ CPU anyway (the process stayed scheduled).
- **Data:** `results/scaling_h50_2026_07_10.csv` — 28 run rows
  (7 caps × 4 seeds) + 308 per-target rows.

### What one "eval" is (be honest about the unit)

One eval unit is the engine's **own** `EvalCounter` unit (fit / certify / probe
events), the same number `invention_engine.zig` prints as "battery evals".
It is a *ladder-stage-level* unit, not a raw sample evaluation: one unit spans
anywhere from a single ridge-fit/coverage measurement (7,000 samples) up to one
256-program bank probe. This unit is the engine's native accounting and is kept
so numbers here are directly comparable to every prior doc that quotes "battery
evals: 372". CPU-seconds are reported alongside as the unit-free cost axis.
Budget enforcement is at stage boundaries (4 gates per target), so a started
stage can overshoot its cap; the CSV and all tables below use evals **actually
consumed** as the x-axis.

### What "novel" is

Every library promotion passes `equivalence_tax.gatePromoteEx`:

- `promos_checked` — certified promotions reaching the tax gate.
- `novel_strict` — promotions whose remix witness verdict is `novel`
  (the strict v3-style witness: a greedy fit over a ~500-column static basis
  fails to reach 0.90 without the candidate).
- `survivors_v4` — promotions kept under the current basis-v4 rules
  (escape-authentic certified promotions survive even when the greedy remix
  basis reaches coverage — the T8-AG-22f framework revision).

`novel_strict` is the conservative "genuinely novel" count; `survivors_v4` is
what production actually keeps. `remix_blocked` was 0 in every run (the v4
lane admits all escape-authentic promotions).

**Limitation:** the tax gate covers the growable-library (ui-side) promotions.
The rq1-side mod/pipeline solutions (e.g. B11's `inversion→half_p` pipeline)
solve their target directly without library promotion and are therefore not
tax-checked. This matches the production engine's own accounting.

---

## 2. Measured yield curve

Identical solve counts across **all 4 seeds at every budget** (per-seed values
in brackets where they differ). Evals = actually consumed, mean over seeds.

| cap | evals consumed | solves /11 | promos checked | novel_strict | survivors_v4 | library size | battery CPU-s (mean) |
|----:|---------------:|-----------:|---------------:|-------------:|-------------:|-------------:|---------------------:|
| 6    | 6   | **1**  | 1 | 0 | 1 | 12 | 1.6 |
| 12   | 18  | **3**  | 3 | 1 | 3 | 14 | 9.7 |
| 24   | 24  | **5**  | 4 | 1 | 4 | 15 | 10.5 |
| 48   | 50  | **10** | 8 | 2.25 [2,3,2,2] | 8 | 19 | 18.7 |
| 96   | 372 | **11** | 8 | 2.25 [2,3,2,2] | 8 | 19 | 23.0 |
| 384  | 372 | **11** | 8 | 2.25 [2,3,2,2] | 8 | 19 | 23.0 |
| 1536 | 372 | **11** | 8 | 2.25 [2,3,2,2] | 8 | 19 | 22.9 |

Prep (zoo-A training, prog bank, battery generation) is a fixed ~3.1 CPU-s per
run, excluded from battery evals by the engine's convention but included in the
efficiency numbers of §5.

### Marginal yield (solves per additional evals)

The task brief asked for solves-per-additional-1e4-evals; the engine's entire
consumption is 372 units, so 1e4 is beyond the measured range — quoting that
unit would be extrapolation. Per **additional 100 evals** (measured):

| segment (evals) | Δsolves | Δevals | solves / +100 evals | Δ battery CPU-s | solves / CPU-s (marginal) |
|----------------:|--------:|-------:|--------------------:|----------------:|--------------------------:|
| 6 → 18   | +2 | 12  | 16.7 | 8.1 | 0.25 |
| 18 → 24  | +2 | 6   | 33.3 | 0.7 | 2.8  |
| 24 → 50  | +5 | 26  | 19.2 | 8.3 | 0.60 |
| 50 → 372 | +1 | 322 | **0.31** | 4.3 | 0.23 |
| 372 → ∞  | 0  | 0   | **0** — no further evals are consumable | 0 | 0 |

Marginal efficiency collapses by ~60× between the 24→50 segment and the 50→372
segment, then goes to exactly zero.

---

## 3. Plateau analysis

**Plateau onset: ~50 consumed evals (10/11 solves); hard ceiling at 372 evals
(11/11).** Two distinct phenomena, both expected under the Closure Principle:

1. **Cheap in-closure solves.** 10 of 11 targets are solved within 1–8 evals
   each: frozen/grown monomials (1), monomial forge (5), pair/Walsh (5–6),
   world pool (8). These are reachable by the growable library's escalation
   ladder at trivial cost.
2. **One expensive out-of-closure solve.** B11 (inversion parity) consumes
   **322 of the 372 units (87%)** — it defeats every library-side stage and is
   only solved by the mod/pipeline escalation, whose 256-program bank probe
   dominates the entire battery budget. Per-target evals-to-solve, by kind
   (identical across seeds):

   | target kind | evals to solve | solving stage |
   |---|---:|---|
   | sign_mod, oriented | 1 | frozen library |
   | random_monomial (×2) | 5 | monomial forge |
   | walsh_subset (×3) | 5–6 | pair router / Walsh |
   | parity_of_count | 6 | Walsh |
   | sum_mod, composed_parity_and_sum | 8 | world pool |
   | **inversion_parity** | **322** | **mod/pipeline (inversion→half_p)** |

   The cost ordering tracks how far outside the frozen closure the target
   lies — a ~2-orders-of-magnitude jump at the boundary, which is the
   Claim-C-style cost signature (steep escalation with required generator
   depth), measured here on 11 fixed targets rather than a parameterized
   depth axis.

3. **After 372: zero consumption, zero yield.** Caps of 96, 384 and 1536 all
   consume exactly 372 units. The engine is not grinding with diminishing
   returns — its ladder terminates. More budget cannot be spent. Any claim
   that "more evals would eventually find more" is unsupported by this
   engine's design: within-closure grinding is exactly what the Closure
   Principle (and the repo's budget-scan results) says cannot help.

**Novel promotions plateau earlier.** All 8 promotions (and both-to-three
strict-novel survivors) occur by cap 48. The strict-novel rate is 2–3 of 8
checked (28%); it does not increase with budget at all in the measured range.

**Determinism / seed caveat.** Solve counts are bit-identical across the 4
seeds; only `novel_strict` wiggles (seed 1: 3 vs 2). This is partly real
robustness and partly weak seed diversity: `generateBatteryB` fixes the
11-target *template* — the battery seed only varies the two random-monomial
masks, while the grid seed varies the 7,000-sample data and zoo-A training.
These curves are therefore "the yield curve of this battery family", not of a
broad task distribution.

---

## 4. Cross-checks

- **Reproduction of production numbers:** at uncapped budget the harness
  reproduces the stock engine exactly — 11/11, 372 battery evals, library 19 —
  matching `zig build invention-engine` output.
- **Determinism:** an earlier pilot sweep (same seeds, pre-CPU-column binary)
  produced identical solves/evals/novel counts row for row.
- **Pre-existing segfault, worked around not fixed:** the stock
  `invention_engine --strict-tax` binary segfaults at the default 8 MB stack
  (`equivalence_tax.greedyFit` places a ~31 MB `col_store` on the stack —
  ~561 columns × 7,000 × f64). Confirmed with the untouched binary; it runs
  fine at `ulimit -s 131072`. The harness runs its sweep on a thread with a
  256 MB stack. No existing file was edited; flagging for a future fix.

---

## 5. Invention per CPU-second — the efficiency number, with its caveats

Full-budget (cap 1536) per-seed totals, **prep included**, CPU seconds via
getrusage:

| seed | solves | total CPU-s (prep+battery) | solves / CPU-s | novel_strict / CPU-s |
|-----:|-------:|---------------------------:|---------------:|---------------------:|
| 0 | 11/11 | 25.0 | 0.441 | 0.080 |
| 1 | 11/11 | 28.9 | 0.380 | 0.104 |
| 2 | 11/11 | 24.7 | 0.446 | 0.081 |
| 3 | 11/11 | 25.0 | 0.439 | 0.080 |

**Headline (measured): ≈ 0.42 certified solves per CPU-second, and
≈ 0.09 strict-tax-novel promotions per CPU-second, on one desktop core.**
Equivalently: a certified solve every ~2.4 CPU-s; a strict-novel, ~11 CPU-s.
At the efficient operating point (cap 48: 10 solves, 2–3 novel, ~22 CPU-s
total) the numbers are essentially the same (~0.46 solves/CPU-s).

### AlphaEvolve-class comparison — read the caveats before quoting this

Published AlphaEvolve-style systems spend on the order of 1e4–1e6 LLM samples
per result, each sample being a data-center LLM inference plus a candidate
evaluation. This engine produces a certified battery solve for ~2.4 CPU-s and
a strict-novel promotion for ~11 CPU-s on one commodity core, with a sound
verifier in the loop.

**The domains are not comparable in significance.** AlphaEvolve-class results
target open problems in mathematics and production systems (matrix
multiplication algorithms, scheduling heuristics); this battery is 11
synthetic predicates over a 6-ary 8-cell grid world, designed to span a known
closure ladder. A fair statement is only this:

> *Per unit of compute, on its own bounded domain, this CPU pipeline's
> measured yield is ~0.4 certified solves and ~0.09 strictly-novel certified
> feature inventions per CPU-second — a cost regime roughly 6–9 orders of
> magnitude below data-center LLM-sample loops. Whether the methodology holds
> any efficiency advantage on problems of external significance is untested
> here (that is the J57–J60 external-ingredient question, still open).*

Do not quote the per-CPU-second number without the domain caveat.

---

## 6. Which of H50–H52 this answers

- **H50 (iters-to-solve vs composition depth — exponential?): partially
  informed, not answered as posed.** H50 asks for a parameterized
  composition-depth axis. What is measured here is evals-to-solve vs
  escalation-ladder stage on 11 fixed targets: 1 → 5 → 8 → 322, a
  ~2-order-of-magnitude jump when the target leaves the library closure.
  Consistent with the exponential Claim-C signature; a real H50 answer needs
  targets constructed at controlled depths d = 1, 2, 3, … .
- **H51 (closure coverage vs atom-set size): not addressed.** No atom-set-size
  sweep was run; library size here is an outcome (12→19), not a controlled
  variable.
- **H52 (mb_mass quality vs band width): not addressed.** Different
  sub-project (control agent), untouched.
- **New result this run adds (not previously in H):** the yield-vs-budget
  curve and its hard saturation, the novel-promotion budget curve, and the
  measured invention-per-CPU-second figure with strict-tax gating.

## 7. Limitations (all flagged above, gathered)

1. Eval unit is stage-granular; caps overshoot (x-axis uses consumed evals).
2. Measured range is 6–372 consumed evals; nothing here supports
   extrapolation past 372 — the engine cannot spend more on this battery.
3. Battery template is fixed across "seeds"; diversity comes from grid data
   and two monomial masks only.
4. Tax gate covers library promotions only; direct mod/pipeline solutions are
   not tax-checked.
5. `novel_strict` vs `survivors_v4` differ by design (v4 reality lane);
   both are reported — pick the strict one for "genuinely novel" claims.
6. Wall-clock was load-contaminated (busy box); CPU seconds via getrusage are
   the cost axis of record. Prep (~3.1 CPU-s) is included in §5, excluded
   from eval counts (engine convention).

## 8. Reproduce

```bash
cd sparse_poly_discovery
zig build-exe scaling_laws.zig -O ReleaseFast
./scaling_laws --seed=0  >  ../results/scaling_h50_2026_07_10.csv
./scaling_laws --seed=1 --no-header >> ../results/scaling_h50_2026_07_10.csv
./scaling_laws --seed=2 --no-header >> ../results/scaling_h50_2026_07_10.csv
./scaling_laws --seed=3 --no-header >> ../results/scaling_h50_2026_07_10.csv
```

Each per-seed invocation runs the 7-cap ladder in ~2 minutes of CPU
(well under the 15-minute per-run bound; the costliest single run is ~29 CPU-s).
