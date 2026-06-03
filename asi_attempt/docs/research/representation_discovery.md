# Representation Discovery: Gradient Finds the Right Rung of the Power-Mean Ladder

**Status:** built, measured. Positive and DECISIVE on the hard case (max); honest
caveat on the easy case (sum). Reproduce: `zig build concentration-control -- discover`

## The Idea (why this matters for "invention")

`concentration_control.md` proved that `max(x) ≥ T` is outside every finite-degree
polynomial closure, and that HANDING the controller a `max` feature crosses the boundary.
But being handed the feature is not invention. The harder, more interesting question:

> Can the system **discover, on its own,** that the task needs an order statistic —
> rather than being told?

We proved the key identity: `max(x) = lim_{p→∞} ( (1/N) Σ (x_i/S)^p )^{1/p}`. That is a
**continuous, differentiable ladder of representations** parameterised by a single scalar
`p`: the power mean `f_p`. p=1 is the arithmetic mean (linear / sum); p→∞ is max; every
rung in between is a softer order statistic.

So instead of a discrete feature menu (the old pair/triplet search), give the controller
ONE feature with a **learnable exponent `p`**, and let gradient descent move `p` to the
rung the task needs. This turns "which feature?" from a discrete search into a smooth
optimisation — and lets us VERIFY discovery against each task's known closure requirement.

## Method

A logistic readout `σ(b + w·f_p(x))` with `b, w, p` all trained by SGD. `f_p` and `df/dp`
are computed in a numerically stable log-sum-exp form (so p can range to ~64 without
overflow). Two **matched** binary tasks that differ ONLY in which order statistic decides
the label:

- **MAX task:** sum held constant (matched), classify `max(x) ≥ T`. Truth: needs p→∞.
- **SUM task:** max held constant (one cell fixed at C), classify `sum(x) ≥ K`. Truth:
  needs p≈1 (the mean); max is constant so it is blind to the label.

`p` is initialised at the SAME neutral value (2.0) for both tasks. Fixed-p models (p=1,
p=32) are run as ground-truth baselines.

## Results

```
MAX task (sum matched at 64, classify max>=T=9):
  learned-p: p  2.00 -> 41.14 -> 46.57 -> 49.90 -> 52.28 -> 54.14 | final p=54.14, acc=1.000
  baselines: fixed p=1  acc=0.500 (mean blind to max) | fixed p=32 acc=1.000

SUM task (max matched at C=8, classify sum>=K=60):
  learned-p (from below, init  2): p  2.00 -> ... -> 2.17 | final p=2.17, acc=0.890
  learned-p (from above, init 12): p 12.00 -> 2.10 -> ... -> 2.17 | final p=2.17, acc=0.890
  baselines: fixed p=1  acc=1.000 | fixed p=32 acc=0.500 (max blind to sum)
```

**What this shows:**

1. **MAX task — discovered perfectly.** From a neutral start (p=2) gradient drives p to
   the ceiling (54.14) and reaches **acc 1.000**, exactly where the truth says it should
   go (fixed p=1 is at chance 0.500; the mean cannot see a single spike). The system
   *invented* the order-statistic representation it needed, from a scalar it could have
   left anywhere.

2. **SUM task — gradient correctly REFUSES to climb,** and lands on a real attractor.
   From BOTH below (2→2.17) and above (12→2.17) it converges to the *same* p≈2.17 — a
   genuine gradient attractor, not inertia. It does not run off toward max (where acc
   would collapse to 0.500). So the discovery is **directionally correct from either
   side**: the task that needs a low rung pulls p down/keeps it low; the task that needs
   a high rung pushes it up.

3. **The contrast is the result.** The *same* learnable feature, identically initialised,
   moves to opposite ends of the ladder according to which order statistic each task
   requires — verified against the known answer.

## Honest Grade

- **Decisive on the hard case (max).** This is the interesting one: the spike is invisible
  to every polynomial proxy, and gradient still finds the exponent that exposes it,
  reaching perfect accuracy. Clean positive.
- **Caveat on the easy case (sum).** The SUM attractor (p≈2.17, acc 0.890) is in the
  *correct region* (low, not max) but is **not the true optimum** (fixed p=1 gives 1.000).
  The joint `(w, b, p)` logistic loss basins near p≈2 — the p-gradient is shallow there
  because at p≈2 the feature already carries most of the sum signal, so gradient has
  little pressure to descend the last stretch to p=1. The representation it discovers is
  *good and correctly-typed*, not optimal. Reporting this, not hiding it.
- **Not new-to-world math.** Learnable-`p` power/p-norm pooling exists (e.g. generalised
  mean / pNorm pooling). The contribution is the *measured demonstration*, inside this
  project's closure framework, that a single learnable exponent lets a controller
  **discover which order statistic a task needs**, with a ground-truth check on both ends
  of the ladder — converting the discrete feature-search problem into one smooth scalar.

## Why This Is a Step Worth Taking

The project's central struggle was feature discovery — pair/triplet/correlation searches
over a hand-built menu. `basis_degree_control` removed the menu for *polynomial* features
(raise the basis degree). This removes it for *order statistics*: a one-parameter family
that gradient navigates. Together they sketch a path where the controller is handed a
*parameterised space of representations* and discovers the right one, rather than a human
enumerating candidates. That is the small, honest version of the larger aim — a system
that invents the representation a problem needs.

## Next

1. Make the SUM attractor reach p≈1: anneal lr, decouple the readout scale, or regularise
   p — does the optimum become reachable, or is p≈2 a real basin of this readout?
2. Two learnable features (p and a second exponent q) — can it discover it needs BOTH a
   low and a high rung (the triple-band analogue) without being told how many?
3. Wire the learnable-p feature into the live TD CONTROLLER (not just a classifier): does
   p climb during control on the concentration task, closing the overflow residual that
   the hand-given max feature closed in `concentration_control.md`?

See: `concentration_control.md`, `basis_degree_control.md`, `feature_discovery.md`,
`correlation_feature_discovery.md`, repo-root `CLOSURE_PRINCIPLE.md`.
