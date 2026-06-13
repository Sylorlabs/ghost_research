# Surrogate-expert verdict: DEAD (small-sample manifold mirage, same as B5)

**Date:** 2026-06-13. The "make our own experts" direction (Micah's reframe),
tested decisively. VERDICT: dead as a speedup.

## What killed it

The whole direction rested on E17/E18b: a single context's activations looked
~84-dimensional, so an expert could be replaced by a tiny rank-~84 surrogate.
The 512-token capture + held-out test (E19c/E19e) refutes this:

- Single-context manifold (512 tokens, layer 30): 90% energy needs **292 dims**,
  95% needs 374, 99% needs 473 — near-full-rank. E17's "84 dims" was a
  128-SAMPLE MIRAGE (identical failure mode to B5's 488-sample mirage).
- Held-out coverage: a basis from 384 warm-up tokens covers only **41% (r=64) to
  58% (r=383)** of held-out tokens' input energy. Bigger basis barely helps.
- Held-out surrogate fidelity plateaus at **0.50 (r=64) to 0.61 (r=383)** — far
  below the 0.85 deployment bar — and MORE warm-up does not help (0.51@96tok ->
  0.50@384tok, flat).
- Sizes that might cover the manifold (r>=292) don't fit RAM (WS_250 = 25-37GB)
  and don't compress meaningfully anyway.

## Why (the unifying picture)

DeepSeek V4 Pro is genuinely incompressible by linear/low-rank methods at EVERY
level we tested: weights are max-entropy (sqrt(2/pi), signal-survival), experts
share no subspace (U2) and aren't individually low-rank (B8), the global
activation manifold is high-dim (B5), single-context activations are high-dim
(this), and experts are functionally distinct (E15). It is a dense,
well-utilized, high-dimensional model with no linear fat to cut. The only things
that ever worked are precision reduction (XOR bitplanes, 3.25 bits) and
amortization (batching) and small routing tricks (U3) — NOT structural
compression.

## Consequence for the goal

20 tps interactive and 100 tps are NOT reachable by retraining-free methods on
this 16GB box. The compute floor (~3.4 tps for full XNOR experts) stands; the
surrogate cannot break it because experts cannot be cheaply approximated.
Honest realistic ceiling (unchanged from the two-floors workflow): ~2.5-5 tps
aggregate offline batch, best with a ~$150 RAM+disk upgrade. Intelligence is
preserved (+0.1 nats after U3 repair); context is free.

## What survives / what we keep

- Forged engine core (16.8GB, verified) — real, reusable.
- U3 cache-aware routing: ~25-34% fetch cut + ~40% tax repair, free.
- Batching: ~7x fetch amortization (works.count union saturates toward 384).
- The honest, complete characterization: we now know precisely why this model
  resists every compression angle, which is itself the research result.

## Methodology note (logged)

Small-sample subspace estimates in 7168-dim are untrustworthy and lied to us
TWICE (B5 at 488, E17 at 128). Rule reaffirmed: never trust a low-dim /
low-rank finding without a held-out test at >=10x the dimension.
