# Ten Experiments: XOR-native DeepSeek V4 Pro on a 16GB desktop

**Date:** 2026-06-10
**Hardware:** 12-core CPU, 16GB RAM, RX 5700 XT 8GB, NVMe ext4 (root) + NVMe NTFS (weights)
**Code:** `src/signal_survival.zig` (rounds 3-4), `src/moe_stack.zig`, `src/xnor_bench.zig`, `src/e6_calib.zig`, `e7_expert_workingset.py`, `e7b_score_routing.py`, `e10_iobench.py`, `e10_tps_model.py`
**Raw outputs:** `signal_survival_round{3,4}.txt`, `e4_e9_full_run.txt`, `e9_p3_forced_routing.txt`, `e9_p4_run.txt`, `e9_p8_chaos_control.txt`, `e6_results.txt`, `e7_results.txt`, `e7b_results.txt`, `e8_results.txt`, `e10a_results.txt`, `e10b_results.txt`, `e4_metrics_p3.csv`, `e4_routing_p3.csv`, `calib_acts_p3.bin`

All experiments run on the real 806GB checkpoint with correct fp8/fp4 decode.
The deep-stack experiments use the model's true FFN path: sqrtsoftplus gating,
hash routing (layers 0-2) / score routing (3-60), top-6 + shared expert,
swiglu clamps, and the full Hyper-Connections residual machinery (hc_mult=4,
Sinkhorn comb mixing) ported from the official `inference/model.py`.
**Attention is ablated to zero in both streams** (its HC mixing still runs) —
the one structural difference from the real model. Probe tokens come from
DeepSeek's own tokenizer.

## E1 — Refit-optimized bitplanes

Least-squares refit of plane scales after greedy sign selection, plus 2
rounds of sign re-greedy. Same storage, pure preprocessing.
**Result: P3 0.972 → 0.979, P2 0.935 → 0.941. Free win, adopted everywhere.**

## E2 — Activation budget

With P3 weights + Hadamard: act planes 1/2/3/4 = 0.79/0.92/0.956/0.967.
**int8 acts (per-64 absmax) = 0.9799 vs f32 acts = 0.9799 — identical.**
Act block size irrelevant (32/64/128 within 0.004).
**Adopted: int8 activations. The "lightweight floating point" lives in the
activations and scales; weights stay pure XOR planes.**

## E3 — Per-tensor sensitivity

15 tensor classes (attention LoRA factors, compressor, gate, shared+routed
experts), P1-P4 each. **All classes identical to ±0.005 at every plane count**
(P1≈0.80, P2≈0.94, P3≈0.98, P4≈0.99). No mixed-precision allocation needed;
the weights are statistically uniform gaussians everywhere.

## E5 — Rotation design

Hadamard chunk 256 marginally beats 1024 on outlier acts (0.970 vs 0.963);
random-sign diagonal (QuaRot-style) adds nothing. Without rotation, P3+P3a
collapses on outlier acts (0.60). **Adopted: plain block-Hadamard.**
FWHT costs 6 microseconds per 7168-vector — free.

## E6 — Calibration on real activations

Real activations captured from the 61-layer run have outlier severity
max/mean ≈ 16x. On them: naive P3 = 0.981-0.986 per matmul, **rotation
unnecessary** (norm + HC keep activations well-conditioned), and **AWQ-style
activation-aware scaling HURTS** (0.982 vs 0.986) — sign-planes don't benefit
from grid-style calibration. Per-matmul error is structural, not fixable by
calibration at the same bit budget.

## E7 — Expert working sets on real text

Hash layers (0-2) route deterministically via `tid2eid[token]`:
- Working set saturates all 384 experts within ~1K tokens; no small hot set.
- LRU hit rates: 59% at 128 cached, 86% at 256, 99.7% at 384.
- Temporal locality from Zipf: 87% of a token's experts appeared in the
  previous 128 tokens.
- **Hash-layer fetches are perfectly prefetchable** (known from token id
  before the layer runs — even at sampling time of the previous token).
Score layers (E7b, from the stack run): 8 unrelated tokens use 39 of 48
possible expert slots per layer — cross-token sharing only 1.23x. Sequential-
text score-layer locality is unmeasured (needs the attention port).

## E4 — Deep-stack compounding (the decisive experiment)

8 real tokens through all 61 layers, reference vs quantized (H + P3-refit
weights + rotated int8 acts), each stream computing its own routing:

| layer | hidden cosine | routing overlap |
|---|---|---|
| 0-2 (hash) | 0.988 | **1.00** |
| 10 | 0.937 | 0.69 |
| 19 | 0.910 | 0.69 |
| 25 | 0.708 | 0.46 |
| 40 | 0.394 | 0.08 |
| 60 | 0.225 | 0.12 |

Final logits: top-1 agreement **0/8**, top-10 overlap 0.10.

A plateau (~0.916, layers 12-19) breaks at layer ~20 and divergence cascades.
The routing overlap collapses first: with 0.98-fidelity hidden states, the
gate's marginal top-6 picks flip; different experts = different computation;
divergence is then self-reinforcing. **Hash-routed layers are immune by
construction** — deterministic routing is quantization-robust architecture.

## E9 — Controls: what exactly fails

**Control 1, routing forced to reference (P3):** holds 0.96 to layer 20
(vs 0.88 unforced) but still decays — 0.84 (L30), 0.69 (L40), 0.42 (L60),
top-1 1/8. Routing flips are roughly *half* the damage; plain numeric error
accumulation through 116 sublayers is the other half.

**Control 2, P4 weights (free routing):** delays onset ~5 layers, same end
state (0.19 at L60, routing overlap 0.10, top-1 1/8). **One more XOR plane
does not escape the cascade — diminishing returns are immediate.**

**Control 3, P8 weights (~0.9995/matmul, diagnostic only — more bits than
fp4):** see `e9_p8_chaos_control.txt`. Purpose: distinguish "the stack is
chaotically sensitive to ANY perturbation" (cosine-to-reference is then the
wrong metric; only task metrics like perplexity are meaningful) from
"P3-specific damage."

**Honest interpretation:** a 61-layer, 1.5T-param MoE amplifies per-matmul
error ~0.98 into total trajectory divergence. Matching the reference model
token-for-token at XOR bit budgets is ruled out by these runs. What is NOT
yet ruled out: the quantized model remaining a *good language model* in its
own right (divergence ≠ damage in a chaotic system — two fp64 weather sims
diverge too). Deciding that requires task evaluation (perplexity over text),
which requires the attention port. The P8 control tells us which world we
are in.

## E8 — Kernel throughput (this CPU)

| kernel | ms / 22M-weight GEMV | Gweights/s |
|---|---|---|
| f32 GEMV (SIMD) | 3.19 | 6.9 |
| P3w x int8a | 4.62 | 4.8 |
| **P3w x P3a pure XNOR** | **2.06** | **10.7** |
| fp4 decode-on-read | 14.28 | 1.5 |

Pure XNOR is the fastest path (popcount density beats everything); fp4
decode-on-read is 7x slower than converting once (95ms/expert) and running
XNOR. Compute-bound decode ≈ 360ms/token on 12 cores ≈ **2.8-3.8 tps if I/O
were free**.

## E10 — Measured I/O and the tps verdict

Random expert-sized reads: NTFS source 1.08 GB/s, ext4 root 2.18 GB/s.
Per-token uncached fetch (58 score layers x 6 experts): 11.2s (fp4/NTFS),
4.2s (P3/ext4). With measured LRU rates and this machine's realistic ~6GB
cache budget: **~0.23 tps** (4.3 s/token, 92% fetch stall). Even 96GB RAM
only reaches ~0.33 tps with uniform LRU assumptions, because the per-layer
working set is the full 384 experts on diverse text.

**The wall is physical: V4 Pro's score-routed expert working set (~300GB at
P3) exceeds any consumer RAM; tps is bounded by NVMe random-read bandwidth
divided by ~9GB of expert misses per token.** Levers that change the answer:
sequential-text locality (unmeasured, could be much better than Zipf proxy),
batch decoding (amortize fetches), smaller V4 variants, or 256GB+ RAM.

## What 10 experiments established

1. The XOR conversion math works and is now fully characterized: H + P3-refit
   planes + int8 acts = 0.98 per matmul on real weights and real activations,
   3.25 bits/weight, fastest kernel on this CPU.
2. The failure mode is not precision — it's **dynamics**: score routing
   amplifies sub-2% hidden-state error into discrete expert flips that
   cascade through 61 layers. Hash routing (DeepSeek's own innovation,
   layers 0-2) is immune; if the whole model were hash-routed it would
   likely survive XOR conversion.
3. Token-for-token reference matching at XOR budgets: ruled out. Quality of
   the diverged model: open question, needs attention port + perplexity.
4. This machine tops out ≈0.23 tps for V4 Pro regardless of quantization
   cleverness — the expert working set is the binding constraint, not FLOPs.
