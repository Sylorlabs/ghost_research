# RQ A10 — Does the binding algebra change the readout closure?

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build clifford`

## The question

The control-domain closure witness (`closure_escape_control.md`, `dynamics_probe.zig`)
proved that the stock VSA encoder XOR-folds all 16 grid cells into one 8192-bit vector,
so the grid collapses to a **parity** and total mass (a SUM) is unreadable: a linear
readout over all 8192 bits classifies "mass in band" at **0.51 (chance)**. That is a
property of the binding **algebra** — `bind = XOR` is its own inverse and carries no
magnitude — not of the task.

Both this repo's Closure Principle (escape corollary) and the external frontier research
on algebraic intelligence predict the same fix: inject a binding **generator outside the
XOR closure**. The frontier report's specific Tier-1 recommendation is the **Clifford
geometric product** (invertible, grade-typed). This experiment tests that claim — and,
critically, tests whether the geometric product *specifically* is what matters, or just
*leaving GF(2)*.

## Method (controlled before/after, one variable changed)

Same VSA recipe for every substrate — one random role per cell, a value filler, bind
within a cell, bundle across cells, then a linear readout over identical train/test
grids. **Only the bind operation changes:**

| substrate | bind | filler | dim |
|-----------|------|--------|-----|
| **XOR-VSA** | XOR (GF(2)) — the stock `EnvEncoder` | random/ordinal | 8192 bits |
| **Hadamard-R** *(control)* | scale role by value (real), bundle = sum | value as magnitude | 8192 reals |
| **Clifford-VSA** | geometric product in Cl(13,0) with a rotor filler | rotor `cos(vθ)+sin(vθ)Bᵢ` | 8192 reals (= 2¹³ blades) |

The Cl(13) multivector has exactly 8192 coefficients, matching the XOR substrate's 8192
bits, so any difference is the **algebra**, not the dimension budget. Rotor fillers are
sparse (scalar + one bivector), so binding never needs the full 8192×8192 product —
`bind(Pᵢ, R(v)) = cos(vθ)·Pᵢ + sin(vθ)·(Pᵢ Bᵢ)` with `Pᵢ Bᵢ` precomputed once.

**The Hadamard-R control arm is load-bearing.** Without it, a Clifford win would be
ambiguous: is it the geometric product, or merely real-vs-binary? The control isolates
that.

Two predicates up the order-statistics ladder: `sum ≥ 48` (linear, B1 — the decisive
cell) and `|sum−32| ≤ 16` (the band, nominally quadratic, B2). Readouts: linear logistic
regression, and a quadratic-of-sum readout (project onto the learned sum direction, fit
logistic over {proj, proj²}).

**Feature standardization is mandatory and was the first honest catch.** On the first run
Hadamard-R scored 0.515 (chance) — not a closure fact but an *optimization artifact*:
its raw summed features are large and heteroscedastic, saturating logistic SGD, while
Clifford's cos/sin features are naturally bounded. Per-column z-scoring on train stats
fixes the conditioning. A true closure ceiling survives standardization; only a scaling
artifact is removed by it.

## Result

```
  substrate                         | sum>=K linear | band linear | band quad-of-sum
  ----------------------------------+---------------+-------------+-----------------
  XOR-VSA   (GF(2), 8192 bits)      |    0.503      |   0.486     |     0.477
  Hadamard-R (real scale, 8192 d)   |    0.974      |   0.984     |     0.982
  Clifford-VSA (geo prod, 8192 d)   |    0.967      |   0.976     |     0.978
```
(4000 grids, 50/50 split; chance: sum 0.513, band 0.535)

## Two findings

**1. CONFIRMED — the escape corollary, at the level of the algebra.** XOR keeps total
mass outside the closure (0.503, chance, *surviving* standardization → a genuine
representational fact). Switching the bind off GF(2) collapses the ceiling: the sum
becomes linearly readable at 0.97. **Changing the binding algebra alone moves the
closure.** This is the report's "change the algebra" thesis and the Closure Principle's
escape corollary, demonstrated in-lab on a ceiling we had already proved.

**2. DEFLATION (the important honest result) — Clifford specifically is NOT the lever.**
A plain real-valued Hadamard bind (0.974) reads the sum *as well as* the full Clifford
geometric product (0.967). Clifford does **not** beat the cheap real control. The
load-bearing generator is **"leave GF(2) for a magnitude-carrying real field,"** not the
geometric product, its grades, or its bivectors — at least for this mass-symmetric
predicate. This is the same pattern the repo keeps finding: the VSA "semantic grounding"
was non-load-bearing; "more tiers" wasn't the meta-engine lever; the impressive-sounding
structure isn't where the work happens. The control arm is exactly what prevented an
overclaim ("Clifford binding cracks the band!").

## Honest caveats

- **The band is effectively one-sided here.** With cells 0..6 over 16 cells, mass centers
  ~48, so `mass < 16` is near-impossible and the band [16,48] ≈ `mass ≤ 48` — a *linear*
  threshold once the sum is readable. So the "quad-of-sum" column is **not** a clean
  two-sided quadratic test. A genuine narrow two-sided band (the real B2 case) needs the
  balanced construction in `order_statistics.zig`, where both tails are populated by
  design.
- **Where Clifford *could* still earn its keep is untested.** Clifford's distinctive gift
  is the grade-2 (bivector) part: oriented *pairwise* products xᵢxⱼ that are **not**
  functions of the sum. The sum/band don't need that. A predicate built on genuine
  relational/covariance structure (e.g., "cells i and j both high," not reducible to a
  symmetric function of mass) is where the geometric product might beat plain real
  binding. That is the honest next experiment, and this result does not settle it.
- **Cl(13) Euclidean only.** No mixed-signature metric, no learned roles, single rotor
  bivector per cell. A richer GA could behave differently; this tests the simplest
  faithful version.

## Bottom line

The binding algebra is a real closure lever — moving off XOR/GF(2) reads a feature that
was provably unreadable before. But the *specific* upgrade to Clifford is not what does
it on symmetric mass predicates; a one-line real-valued bind suffices. Pursue Clifford
only against predicates whose natural representation is the bivector (pairwise/relational)
grade — otherwise the cheaper real substrate is the honest choice.

See: repo-root `CLOSURE_PRINCIPLE.md`, `closure_escape_control.md` (the XOR ceiling this
builds on), `order_statistics_closure.md` (the ladder and the balanced two-sided band),
`feature_discovery.md` (the standardization-artifact precedent).
