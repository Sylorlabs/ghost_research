# U2/B8/B5: the compression verdicts — linear is dead, the manifold is open

**Date:** 2026-06-12
**Code:** `u2_expert_spectrum.py`, `b8_per_expert_rank.py`, `b5_activation_manifold.py`
**Raw outputs:** `u2_spectrum_L{30,10}_w1.txt`, `u2_spectrum_L30_w2.txt` — L10 and w2 confirm the same flat spectrum (L10 w1: rel-err 0.887 @ k=1024; w2: 0.577 even at k=2048 of 3072). Flatness is universal across layers and matrix classes.,
`b8_results.txt`, `b5_results.txt`, saved basis `u2_basis_L30_w1.npy`

## U2 — cross-expert shared subspace: DEAD

Row covariance over 300 train experts (512 rows each, layer 30 w1),
eigendecomposed, reconstruction tested on 34 held-out experts:

- Spectrum nearly flat: top-1024/7168 dims = 21.7% energy; top-3072 = 54.7%.
- Held-out reconstruction: rel-err 0.907 at 7x compression (k=1024);
  0.727 at k=3072 — a pure random matrix would give 0.756. The experts
  share essentially NO common row-space.
- MP control: a handful of directions poke above the random bulk (top
  eigenvalue 7.5x mean) but carry negligible total energy.

The "shared basis + per-expert delta" lever (5-30x hoped) is dead in its
linear form. This was the single biggest factor in the 20-tps multiplier
chain.

## B8 — per-expert internal rank: DEAD

SVD of individual experts (0, 100, 350; layer 30 w1): 90% energy needs
rank ~2075 of 3072 (~68%) — near-full-rank, consistent across experts,
barely distinguishable from random. Per-expert low-rank factorization is
also not a lever.

Together with the sqrt(2/pi) result (weights are per-coefficient maximum
entropy) and U2 (no shared directions): **DeepSeek V4 Pro's expert weights
are incompressible by any linear method, at every granularity tested.**
Residual XOR bitplanes remain the only working weight format precisely
because they don't assume structure.

## B5 — the activation manifold: OPEN, promising, data-starved

Experts compute W.x. If x lives in a k-dim subspace B, store W.B
(k/7168 of the bytes) — W's randomness is irrelevant on this axis.
Measured on the 488 captured real activations (8 tokens x 61 layers):

- Pooled spectrum: top-128 dims = 94.6% energy — activations are
  dramatically lower-dimensional than weights.
- Held-out capture: 90.2% at k=256 (rel-err 0.31), 92.3% at k=399
  (rel-err 0.28), still rising at the sample cap.

0.3 residual is too lossy as a sole format, BUT 488 samples both cap and
understate the true capture (basis starved). Decision deferred to a
10-60x larger activation corpus.

**Action taken:** `ppl_stack` gained an `ACT_DUMP=<path>` env option that
dumps ref-stream post-ffn_norm activations ([layer u32, tok u32, 7168 f32]
records, same format as calib_acts.bin) during any run. Built as a separate
`ppl_stack_actdump` binary so the in-flight queue's proven binary is
untouched. Chained for tonight: dump runs at offsets 8000 and 21601
(7,808 vectors each), then automatic B5 rerun on the larger corpus.

## Revised multiplier chain (post-verdicts)

Surviving levers: U1 dynamic channel sparsity (2-5x, measured, needs
gate-first fetch design), U3 cache-aware routing (~1.4x, confirmed),
MTP speculative batching (2-4x, untested), disk re-layout/prefetch
(1.5-2x), activation-manifold format (unresolved). Without a manifold/
nonlinear win, realistic ceiling on this box is ~2-5 tps, not 20.
The honest framing: 20 tps now depends on (a) the bigger activation
corpus rescuing W.B compression, (b) MTP acceptance rates, or (c) a
hardware lever (RAM).
