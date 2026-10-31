# B5-v2: the activation-manifold verdict (15,616 samples)

**Date:** 2026-06-12 ~20:30
**Code:** `b5_activation_manifold.py acts_combined.bin b5_results_v2.txt`
**Data:** 15,616 real post-ffn_norm activation vectors (two text domains,
offsets 8000 + 21601, dumped via `ppl_stack_actdump`), 32x the starved
488-sample first pass.

## Result

| basis k | compression | held-out energy captured | residual rel-err |
|---|---|---|---|
| 64 | 112x | 45.7% | 0.737 |
| 128 | 56x | 56.5% | 0.659 |
| 256 | 28x | 67.9% | 0.567 |
| 512 | 14x | 78.6% | 0.463 |
| 1024 | 7x | 87.1% | 0.359 |
| 2048 | 4x | 93.2% | 0.261 |
| 4000 | 2x | 97.3% | 0.165 |

## Verdict: the 488-sample result was a small-sample MIRAGE. Lever DEAD at useful ratios.

The first pass (488 samples) showed 94.6% energy in 128 dims. At 15,616
samples that collapses to **56.5%** — the apparent low-dimensionality was
basis overfitting (488 points can't help but lie near a 128-dim subspace;
7168-dim geometry needs >>488 samples to see its true spread). The honest
spectrum is only mildly concentrated: half the energy needs ~128 dims, but
the tail is heavy — 90% needs ~1024 dims, 95% needs ~2048.

For the W.B expert-compression scheme this is fatal at the ratios that
mattered: useful speedups need k<=256 (>=28x), where held-out reconstruction
error is 0.57-0.74 — far worse than P3's per-matmul 0.02. Even k=1024 (only
7x, and 1024-wide projections are not cheap) leaves 0.36 error. There is no
operating point where activation-manifold projection beats just keeping P3.

## Consequence: linear compression is now dead on BOTH axes

- Weight space (U2/B8): experts share no subspace, individually full-rank.
- Activation space (B5-v2): manifold too high-dimensional to project onto.

DeepSeek V4 Pro's MoE is, by every linear measure tested, near-incompressible
beyond the bitplane format. This is a clean, strong, and final negative —
the 30-50x "free lunch" does not exist. Methodological win: caught only
because we distrusted a too-good 488-sample number and re-ran at 32x scale.
GENERAL LESSON (logged): subspace/PCA findings on <few-thousand samples in
7168-dim are untrustworthy; always check the held-out curve at >=10x dim.

## Revised tps outlook (honest)

Surviving levers, all measured or near-measured:
- U1 dynamic channel sparsity: 2-5x bytes+compute (per-token hot set;
  needs gate-first fetch). Strongest survivor.
- U3 recency-aware routing: ~1.3x I/O (confirmed) + quality repair.
- MTP speculative batching: 2-4x (untested; head ships in checkpoint).
- Disk re-layout + hash-prefetch: 1.5-2x I/O.

Compounded mid-range ~= 10-25x over 0.23 tps => realistic 2.5-5 tps on this
16GB machine. 20 tps now hinges on (a) MTP overperforming, (b) U1's dynamic
sparsity reaching its high end AND being I/O-realizable, or (c) more RAM.
Engine plan unchanged: P3 core (forging tonight) + P3 routed experts +
recency routing + U1 gate-first sparsity + MTP. No format pivot — B5-v2
removes the only reason one was on the table.
