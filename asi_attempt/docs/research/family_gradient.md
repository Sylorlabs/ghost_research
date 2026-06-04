# RQ C23 — Can gradient discover the primitive parameter, or only grid search?

**Status:** built, measured. Reproduce: `cd asi_attempt && zig build family-gradient`

## The question

`order_statistics.zig`'s forge closes the invention loop on parity-of-count by **grid-
searching** `(H, ω)` for the count-Fourier feature `cos(ω·#{cells≥H})`; it finds `H=5, ω=π`
(= `(-1)^count`) and promotes it. `primitive_class_inference.md` flags the honest limit:
the parameter is *enumerated*, not *learned* — "learning the parity frequency by gradient is
the canonical hard case and would likely fail." This makes that prediction concrete.

Fix `H=5` (the forge's threshold) to isolate the ω problem, then ask: from a random ω, does
gradient descent on a logistic classifier with feature `cos(ω·count)` reach ω≈π and separate
parity?

## Result

```
  method                              | test acc | notes
  ------------------------------------+----------+----------------------------
  grid search over ω (the forge)      |  1.000   | best ω=3.000  (π=3.142)
  gradient, random ω init (best/40)   |  0.728   | 0/40 inits reached >0.95
  gradient, random ω init (mean/40)   |  0.670   | typical random-init outcome
  gradient, warm start near π (best)  |  0.728   | 0/40 inits reached >0.95
```

## Verdict: confirmed negative — and gradient is *structurally* blind here

Grid search nails it (1.000); gradient from random ω is stuck near chance (mean 0.670), and
**0/40 runs** reach 0.95. The striking part: even **warm-started within ±0.3 of π**, gradient
still fails (0/40). The reason is exact and damning:

> The ω-gradient is `(p−y)·a·(−count·sin(ω·count))`. At the solution ω=π, and for integer
> counts, `sin(π·count) = 0`. **The gradient vanishes at the exact optimum.**

So ω=π is not a smooth basin gradient can roll into — it is a measure-zero spike where the
gradient carries *no information*. Warm starts get no pull toward it and drift away on SGD
noise. The optimum is invisible to first-order methods by construction.

## Significance

This is the closure question re-asked in parameter space. The forge's grid search works
precisely *because* it does not rely on landscape smoothness — it enumerates. "Discover the
primitive parameter by gradient" does **not** close the invention loop for the parity family;
the discovery is the enumeration, not the descent. A genuinely open forge that must *grow* a
primitive whose parameter is non-enumerable (continuous, high-dimensional) cannot fall back
on gradient when the target is oscillatory — it needs either a structured search the family
affords, or a different (e.g. spectral / periodicity-aware) discovery operator. That gap is
the honest frontier the forge demo left open.

## Honest caveats

- This is the *isolated* ω problem with `H` fixed at the known-good value. The full forge also
  must find `H` (discrete, enumerable) — that part grid search handles trivially.
- Parity frequency is deliberately the hardest case (vanishing-gradient at the optimum). A
  smoother primitive family (e.g., a threshold whose loss is monotone in the parameter) would
  likely be gradient-learnable; this result is a statement about *this* family, which is the
  one the forge actually needed.
- Bigger trial counts / annealing schedules were not exhausted; but the vanishing-gradient
  argument says no first-order schedule fixes the structural problem, only enumeration or a
  periodicity-aware operator does.

See: `order_statistics.zig` (the forge), `primitive_class_inference.md` (the flagged limit),
repo-root `CLOSURE_PRINCIPLE.md` (discover-the-generator frontier).
