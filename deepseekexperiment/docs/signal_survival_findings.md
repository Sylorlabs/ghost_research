# Signal Survival: DeepSeek V4 Pro under XOR-native quantization

**Date:** 2026-06-10
**Code:** `src/signal_survival.zig` (round 1: `./signal_survival`, round 2: `./signal_survival round2`)
**Raw output:** `signal_survival_results.txt`, `signal_survival_round2.txt`

## Question

Can DeepSeek V4 Pro's matmuls be replaced with pure XOR/popcount arithmetic
(1-bit sign weights + block scales) and keep the model's signal? Measured
directly on the real weights: cosine similarity between the reference fp32
GEMV and the quantized GEMV, per tensor, on gaussian and heavy-tail
(outlier-channel) activations.

## Ground truth about the checkpoint (fixes prior assumptions)

- Weights live at `/mnt/steamgames/DeepSeek-V4-Pro/` (806GB, 64 shards).
  `/mnt/corpus/...` paths in older code refer to a bind mount that no longer
  exists.
- The checkpoint is **already quantized by DeepSeek**: attention/shared-expert
  weights are fp8-e4m3 with 128x128 e8m0 block scales; the 384 routed experts
  per layer (~772GB of the total) are **fp4-e2m1, two values packed per byte
  along K, e8m0 scale per 32 weights**. Only norms/compressor/gate/embed are
  bf16.
- The previous distiller (`smart_distiller.zig`) read every tensor as bf16 —
  the 79GB `distilled_core/` produced from that is invalid data
  (halved element counts, signs taken from the wrong bytes, scales ignored).
- First 3 layers use **hash routing**: `gate.tid2eid[129280,6]` maps each
  vocab token id directly to its 6 experts — deterministic, perfectly
  prefetchable, near-uniform over the 384 experts. Layers 3-60 use score
  routing (sqrtsoftplus + bias topk-6) plus 1 always-active shared expert.

## Round 1: naive 1-bit (the original "XOR transition")

17 tensors across layer 0 and layer 30, fp8 + fp4 + bf16. Results are
uniform to ±0.01 everywhere:

| variant | gaussian acts | outlier acts |
|---|---|---|
| 1-bit weights, real acts | **0.80** | 0.80 |
| full XNOR (1-bit weights + unscaled 1-bit acts; what engine.zig computes) | 0.63 | **0.29-0.37** |
| ternary weights, real acts | 0.90 | 0.90 |
| ternary + 1-bit acts | 0.72 | 0.31-0.42 |

Findings:

1. **0.80 = sqrt(2/pi) exactly** — the theoretical cosine for sign-quantizing
   gaussian weights. Every tensor sits on the gaussian limit: there is no
   exploitable sign structure in the weights. One plane of signs cannot do
   better than 0.798 per matmul, period.
2. **Activation binarization is the killer, not weight binarization.** The
   current engine's XNOR path collapses to ~0.3 under realistic outlier
   channels.
3. **Block size (16..256) does not matter** for fidelity — scales can be
   coarse, storage can be cheap.
4. fp4 experts have ~11.7% exact-zero weights; sign-binarization forces them
   to ±1 (no measurable extra damage at this scale, ternary handles them
   naturally).

## Round 2: residual bitplanes + Hadamard rotation

Two methods that stay XOR-native:

- **Residual bitplanes (Pk):** binarize W, then binarize the residual as a
  second plane, etc. W ≈ Σ_k s_k·sign(r_k). Every plane is still
  XNOR+popcount at runtime. Theory: each plane cuts residual energy by
  (1−2/π)≈0.363.
- **Block Hadamard rotation (H):** W' = W·Hᵀ, x' = H·x (orthonormal, exact
  in pairs); spreads activation outlier energy across the block so 1-bit act
  quantization stops being dominated by outliers. Fast Walsh-Hadamard on
  chunks (1024/512), O(n log n), no storage cost.

Measured (4 tensors, identical to ±0.01; g=gaussian, h=heavy-tail):

| variant | g | h |
|---|---|---|
| P2 weights, real acts | 0.935 | 0.935 |
| P3 weights, real acts | 0.974 | 0.974 |
| P4 weights, real acts | 0.986 | 0.986 |
| P3 weights, 1-bit acts | 0.78 | 0.40 |
| P3 weights, P3 acts (no rotation) | 0.947 | 0.60 |
| **H + P3 weights + P3 acts** | **0.949** | **0.956** |
| H + P2 weights + P2 acts | 0.879 | 0.890 |

Findings:

5. **Bitplanes track theory exactly**: P2=0.935 (theory 0.932), P3=0.974
   (0.976), P4=0.986. The sqrt(2/pi) wall is broken by stacking XOR planes.
6. **1-bit activations have their own sqrt(2/pi) wall** (~0.78 cap regardless
   of weight quality). Multi-plane activations break it the same way.
7. **Hadamard rotation makes heavy-tail activations BETTER than gaussian**
   (0.956 vs 0.949) — rotation gaussianizes the activation distribution so
   per-block scales become accurate. Outliers stop being a failure mode.
8. **Recommended operating point: H + P3w + P3a** — 0.95 cosine per matmul,
   runtime = 9 popcount passes per 64-block + per-block scale multiplies +
   FWHT on the activation vector. Fully integer/bitwise except the small
   activation-side transforms.

## Cost of the recommended format

- Storage: 3 planes ≈ 3.2 bits/weight (block-64 u8 scales) vs fp4's 4.25 —
  modest savings; vs fp8 ~2.5x. Experts at P3: ~25MB/expert, full model
  ~310GB (does not fit local disks → keep cold experts as source fp4 on the
  NTFS drive, convert on read, cache converted: RAM → root NVMe → source).
- Compute per matmul: 9 XNOR+popcount passes ≈ 9/64 of an f32 MAC per
  weight-bit-block — far below memory bandwidth limits; the system is
  I/O-bound on expert fetch, not compute-bound.
- Per-token active set: ~28B expert params (6 routed + 1 shared, 61 layers).
  At P3 ≈ 11GB/token uncached; shared experts (~1.5GB at P3, always active)
  must be RAM-pinned; routed-expert caching + hash-layer prefetch
  (tid2eid is deterministic) decide real tps.

## Open questions (next experiments)

- End-to-end: 0.95/matmul compounded over 61 layers with residual streams —
  needs a correct V4 forward pass (MLA compressor + indexer + gate), ported
  from the official `inference/model.py` that ships with the weights.
- GPTQ-style error-compensated sign selection could push past 0.95 at the
  same bit budget (needs calibration activations).
- Expert reuse rate on real text for layers 3-60 (needs working forwards);
  hash layers 0-2 measurable from token streams alone.
- Whether attention (small, always active) should just stay fp8 — it's ~30GB
  total, the XOR treatment matters only for the 772GB of experts.
