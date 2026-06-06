# Concentration Control: the Order-Statistic Closure Boundary (H4)

**Status:** built, measured. Representational result DECISIVE and degree-general;
control result is a real-but-bounded reliability effect. 8–16 seeds, worst-case reported.

**Reproduce:**
```sh
zig build concentration-control            # default: control regimes A/B/C + decisive probes
zig build concentration-control -- degree  # degree-general closure probe (d=2 and d=3)
zig build concentration-control -- sweep    # feasibility-aware regime sweep (oracle floor)
zig build concentration-control -- confirm  # full-budget confirm of the witness regimes
zig build concentration-control -- robust   # per-seed + band-neighborhood robustness
```

## The Question (H4)

`basis_degree_control.md` showed a quadratic basis over the raw 16 cells solves the
*polynomial* band constraints (sum/left/right) perfectly. It flagged H4 as **untested**:
does an **order-statistic** constraint — `max(x) ≥ T`, which is NOT a fixed-degree
polynomial — defeat the quadratic basis? The shared env was degenerate (uniform dynamics
couple max and sum). Here we build a purpose-built **concentration** env where the max
constraint is separable, and we answer H4 cleanly at two levels:

1. **Representation** — can a degree-d polynomial of the raw state *represent* `max ≥ T`?
2. **Control** — does the representational gap *cause* a measurable control failure that
   one order-statistic feature fixes?

## Result 1 — Representation: max ∉ the polynomial closure, at EVERY finite degree

The classifier methodology (the project's readout-ceiling style): generate two classes
(some cell ≥ T vs all cells < T) and train logistic regression per basis on held-out data.

**Decisive probe (match `sum` AND `Σx²` exactly):** for exchangeable data the best
*quadratic* depends only on `(sum, Σx²)`; matching both forces any quadratic to chance.
```
  L=2 (T=6) | lin 0.496 | quad 0.564 | quad+max 1.000
  L=3 (T=6) | lin 0.505 | quad 0.528 | quad+max 1.000
  L=4 (T=9) | lin 0.503 | quad 0.515 | quad+max 1.000
  L=5 (T=9) | lin 0.499 | quad 0.503 | quad+max 1.000
```

**Degree-general probe (minimal power-sum basis `[1, p_1..p_d]`, match `p_1..p_d`):**
the key new math. For exchangeable data the best degree-d polynomial depends only on the
power sums `p_k = Σ x_i^k`. And `max(x) = lim_{k→∞} (p_k)^{1/k}` is the k→∞ limit — so no
finite d can capture it. Matching `p_1..p_d` exactly (integer-key bin-merge) forces any
degree-d polynomial to chance:
```
  degree 2 (match p1, p2)     | [1,p1,p2]    0.500 | [..,max] 1.000
  degree 3 (match p1, p2, p3) | [1,p1,p2,p3] 0.500 | [..,max] 1.000  (0.982 at L=4)
```
`0.500` is *exact* chance: with `p_1..p_3` matched, the power-sum feature vector has the
same distribution in both classes — literally zero signal. **One** order-statistic feature
(`max`) recovers perfect separation. So neither a quadratic nor a cubic over the raw state
can represent the max constraint; by the limit argument, **no finite-degree polynomial
can.** This is the cleanest closure-boundary witness in the project: a predicate provably
outside the polynomial closure at every degree, crossed by a single order-statistic atom.

Geometric reading: the decision boundary of `max(x) ≥ T` is a **union of 16 axis-aligned
half-spaces**. A degree-d level set is a single algebraic surface; it cannot equal a union
of planes for any finite d.

## Result 2 — Control: the gap becomes a reliability effect in a feasible regime

Per-action TD danger `Q(x,a) = w_a·φ(x)` over the raw 16 cells, three bases (only the basis
changes): `linear`, `quadratic`, `quad+max` (quadratic + one `max(x)` feature). Failure =
any cell ≥ T (overflow, order statistic) OR sum out of band (polynomial). `knockdown` is the
only max-control action and it COSTS sum, so the agent cannot always-knock — it must detect
*when* max is near T, i.e. represent the order statistic.

**The confound that made the first attempts (regimes B/C) inconclusive:** near-infeasible
regimes conflate "can't represent max" with "nobody can control this." To separate them we
added a **hand-coded max-rationing oracle** with perfect access to the true max/sum — the
**feasibility floor.** A feasibility-aware sweep then hunts for: oracle ≈ 0 (feasible),
quad+max ≈ oracle (learner recovers it), quad overflow ≫ quad+max overflow.

**Confirmed witness** `start=4, thresh=6, sum∈[48,80], knock=2, drip=1`, 80k train /
10k eval / 8 seeds:
```
  basis     |    mean |   worst | overflow | band
  ----------+---------+---------+----------+------
  oracle    |    0.00 |    0.00 |     0.00 |  0.00   <- feasible
  linear    |    7.81 |   34.30 |     2.71 |  5.10
  quadratic |   11.64 |   43.20 |     9.66 |  1.98   <- solves the band, fails the max
  quad+max  |    2.32 |    5.20 |     2.31 |  0.01   <- one feature closes overflow
```
The **band/overflow split is the clincher**: quadratic controls the polynomial band
(band=1.98) but leaves a **max-specific overflow residual** (9.66/1k). It is not generally
incompetent — it solved the part it *can* represent and failed the part it *can't*. The
`max` feature drops overflow ~4× (9.66 → 2.31).

**Honest robustness (16 seeds, per-seed):** quad+max wins overflow (by >2/1k) on **7/16**
seeds and ties on the rest. The mean gap is driven by quad's **overflow-collapse tail** —
seeds where quad hits 14–43 overflow/1k while quad+max stays ≤5. So the effect is
**reliability, not a universal per-seed win** (worst-case 43.2 → 9.4) — the same character
as the `basis_degree_control` phase transition ("reliability, not bare capability"). It
holds across band half-widths 12–18 (a neighborhood, not a knife-edge) and reverses at
half-width 20 where the band is so wide the regime gets noisy.

**A sweep candidate that did NOT survive** (the value of worst-case confirmation):
`start=4, thresh=7, knock=3` looked like a witness at 3 seeds / 30k (quad+max 3.3 vs quad
35.5) but at 80k / 8 seeds quad+max (41.53) was *worse* than quad (19.56), both with
collapsed seeds — the larger knock destabilizes TD. Reported as a negative, not buried.

## Honest Grade

- **Representation (Result 1): decisive and degree-general.** The order statistic is
  outside the polynomial closure at degree 2 *and* 3, exact-chance under matched power
  sums; `max` crosses it. This is a clean, reproducible closure-principle theorem-by-
  construction. This is the strong result.
- **Control (Result 2): real but bounded.** In a *certified-feasible* regime the
  representational gap shows up as a control gap, attributable specifically to overflow
  with the band controlled. But it is a **reliability/tail effect** (eliminates quad's
  overflow collapses), not a per-seed guarantee, and it lives in a finite regime
  neighborhood. We did NOT manufacture a regime where quad+max beats quad on every seed.

## What This Does NOT Show

- Toy 16-cell battery microworld. Not "beyond" anything in a literal capability sense.
- Textbook ingredients (linear/quadratic function approximation + TD(0) + one order-
  statistic feature). The contribution is the *measured, degree-general* demonstration
  that an order-statistic constraint is outside the polynomial closure, and that this
  representational fact has a (bounded) control consequence.
- The degree-3 probe has thinner `p_1..p_3`-matched overlap (n≈500–4900) than the
  degree-2 probe (n≈5k–11k); the 0.500 result is robust but the overlap shrinks fast with
  degree (a spike inflates `Σx³`), so d≥4 by this construction would need a much larger
  pool. The limit argument, not brute force, is what generalizes it.

## Connection to the Closure Principle

`basis_degree_control` showed the linear→quadratic boundary for **polynomial** band
constraints. This adds the next rung: **polynomial→order-statistic**. The band needs the
quadratic closure; the max constraint needs an order-statistic atom *outside every
polynomial closure*. The capability boundary is the closure boundary, here proven for all
finite polynomial degrees by matching power sums — the analytic version of the project's
"add the generator that adds the missing algebraic structure."

See: `basis_degree_control.md`, `triple_band.md`, `pair_feature_control.md`,
repo-root `CLOSURE_PRINCIPLE.md`.
