# The two floors, and why surrogate experts are the unique escape

**Date:** 2026-06-12 (floor-breaking workflow + surrogate experiments E17-E19 + compute accounting)

## The finding that reframed everything: there are TWO floors

The whole project fixated on the **fetch floor** (disk I/O). The floor-breaking
workflow surfaced a second, harder one underneath:

| floor | full-model value | nature |
|---|---|---|
| Fetch (I/O) | ~0.23 tps labeled; ~0.5 tps feasible (cap-128, but needs 95GB RAM) | breakable framing |
| **Compute** | **~3.4 tps even with FREE fetch** (37.8 GMAC/token, XNOR@12 cores) | physical law (for full experts) |

20 tps needs <50ms/token; full-model compute alone is ~295ms/token. **For the
full-expert architecture, 20 tps is below the compute floor by ~6-7x — even
with infinite RAM and bandwidth.** The workflow's verdict is correct: batch/MTP
(its best conventional bet) asymptotes into ~2.5 tps aggregate at this wall.

## Per-token compute breakdown (full model)

| component | GMAC/token | share |
|---|---|---|
| routed experts (6×58 layers) | 23.0 | 61% |
| attention (MLA projections) | 11.0 | 29% |
| shared expert | 3.8 | 10% |
| **total** | **37.8** | → ~3.4 tps compute ceiling |

## Why surrogate experts (E17-E19) are the unique escape

Surrogate experts attack BOTH floors at once — the only retraining-free method
that does — because the property that shrinks storage (experts are locally
~84-dimensional, E18b: 0.93 output cosine at rank 84) shrinks compute too:

| architecture | routed-expert compute | total compute | compute ceiling | fetch |
|---|---|---|---|---|
| full XNOR experts | 23.0 GMAC | 37.8 GMAC | ~3.4 tps | 9-11GB/token |
| **surrogate experts** | **0.39 GMAC (59x less)** | 11.5 GMAC | **~11 tps** | ~0 (1.6GB RAM-resident) |
| surrogate experts + attention | 0.39 GMAC | 1.2 GMAC | **~100 tps** | ~0 |

- Surrogate experts alone move the compute ceiling from 3.4 → ~11 tps, with
  attention (untouched) now the 96% bottleneck. Fetch → ~0 (working set 1.6GB
  fits RAM, E19).
- Applying the same low-dim-context trick to attention's big projections
  (q_b, wo) → ~100 tps compute ceiling. 20 tps gets comfortable headroom.

## The honest status

**3 hours ago: "20 tps physically impossible" (both floors bind).**
**Now: the surrogate direction breaks both floors; 20 tps is no longer ruled
out — it gates entirely on ONE unproven number: surrogate fidelity.**

- Structure is sound: in-sample ceiling 0.90 @ rank 84 (E19d).
- Held-out fidelity at 96-token warmup: only 0.55, but climbing monotonically,
  not plateaued (basis under-estimation) (E19b).
- DECISIVE TEST RUNNING: 512-token capture → warm-up curve to ~384 tokens
  (`try_surrogate.sh` → E19c). Does held-out fidelity reach ~0.85-0.90?

Caveats kept honest: MAC ceilings overstate real tps (kernel efficiency,
projection overhead, int8-vs-XNOR rates, memory bandwidth all reduce them);
surrogates need a per-session warm-up (stream experts once to fit); the ~100 tps
figure assumes attention-surrogation also works (unproven). But the DIRECTION is
now the clear winner: the workflow proved every conventional path hits ~3 tps;
the surrogate is the one unconventional path that doesn't, and the two
investigations converge on it.

## What this makes the project's spine

1. Prove surrogate fidelity reaches deployable (~0.85+) with realistic warm-up
   (E19c running; if short, add a nonlinear correction core from sibling
   sparse_poly).
2. Build the warm-up→surrogate→RAM-decode engine; measure real tps vs the ~11 tps
   ceiling.
3. If experts work, surrogate attention projections too → toward ~20+ tps.
