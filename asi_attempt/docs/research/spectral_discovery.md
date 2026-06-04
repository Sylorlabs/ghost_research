# Frontier 2 — A periodicity-aware operator discovers ω where gradient cannot

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build spectral-discovery`

## The gap this closes

`family_gradient.md` (RQ C23) proved a *negative*: gradient descent cannot find the primitive
parameter ω=π for parity, because the ω-gradient `∝ −count·sin(ω·count)` **vanishes at the
optimum** (`sin(π·integer)=0`). ω=π is a measure-zero spike, invisible to first-order methods.
The doc named the fix — a "periodicity-aware / spectral" discovery operator — but did not build
it. This is the constructive other half: discovery *is* possible, with an operator matched to
the family's structure.

## The operator (no gradients, no accuracy-grid over ω)

1. Estimate the conditional-mean signal `f(c) = E[label | count = c]`.
2. Take its count-weighted power spectrum over ω ∈ (0, π].
3. The **peak frequency is the primitive's period** — for parity, a sharp spike at ω=π.
4. Verify the classifier `cos(ω*·count)` separates the target.

This transforms to the domain where a period is a single peak, instead of hunting a knob
against a classification objective (the forge's grid method) or rolling downhill (gradient).
It runs in O(bins × freqs) on a 17-point signal — trivially cheap.

## Result

```
conditional-mean signal f(c)=E[label|count=c]:
  0 1 0 1 0 1 0 1 0 1 0 1 · · · · ·          (perfect alternation = period 2)

  discovery operator                  | found ω  | test acc
  ------------------------------------+----------+---------
  gradient descent (random init, 20)  |  varies  |  0.663     (STUCK — from family_gradient)
  spectral peak (periodicity-aware)   |  3.1416  |  1.000     (= π, exactly)
```

## Verdict

**The operator is the lever.** The spectral peak lands at ω=3.1416 = π and its classifier
separates parity at 1.000, while gradient from random inits is stuck at 0.663. The *same*
parameter that gradient structurally cannot find is read off a single spectral peak by an
operator matched to periodicity.

This is the honest, constructive complement to the C negative, and it sharpens the closure
lesson into a statement about **discovery operators**: a generator is discoverable iff the
discoverer's inductive bias matches the generator's structure. Gradient's bias (smooth local
descent) does not match an oscillatory parity frequency; a spectral bias (global periodicity)
does. "Discover the generator" is the closure question re-asked about the *discoverer*: its
operator must contain the structure it hopes to find.

## Honest caveats

- The spectral operator is itself *specialised* — it assumes the structure is periodic in the
  count. It would not find a non-periodic primitive any more than gradient finds the periodic
  one. There is no universal discovery operator here; the win is *matching* operator to family,
  not a free lunch. This is exactly the wcore atom-forge conclusion (closure all the way up):
  every level of "discover the generator" presupposes a richer bias to search within.
- It relies on a clean conditional-mean estimate `f(c)`, which needs enough samples per count
  bin. Sparse bins (high counts here) are simply dropped; the period is recovered from the
  populated bins.
- `H` is fixed at the forge's value to isolate the ω problem, as in `family_gradient.md`.

See: `family_gradient.md` (the negative this completes), `order_statistics.zig` (the forge),
repo-root `CLOSURE_PRINCIPLE.md` (the discover-the-generator frontier).
