# Fetch-lever kills & locality methodology (2026-06-13)

Consolidated record of the fetch-reduction levers tested and killed, plus the
locality methodology that gates the survivors (MTP, span-batching, caching).

## Coarse-to-fine super-experts — DEAD (c2f_probe.py, c2f_results_L30_K32.txt)
Cluster the 384 experts into K=32 RAM-resident centroids; serve routine tokens
from a centroid, pay disk only when the centroid residual is large.
- At cos>=0.90, only **0.3%** of tokens served from RAM; phi_disk=0.997.
- Conditional on real top-6 routing: **0.0%** served-from-RAM at cos>=0.80.
- Centroid/true-expert norm ratio 0.259, mean residual 0.25 — centroids are
  near-orthogonal to the true experts. Same root cause as U2/E15: experts are
  functionally distinct, so no small shared set approximates them.

## Surrogate kill-tests — DEAD (ghost_kill.py, ghost_generous.py)
Per-expert rank-r linear surrogate + VQ residual table, gate-weighted
contribution reproduction on held-out tokens. Confirmed the E19 verdict:
held-out fidelity far below the bar; the contribution can't be cheaply faked.

## Top-k routing reduction — DEAD (topk_*.txt)
REF ppl top-6=14.06 -> top-3=17.84 (+0.24 nats, worse than the XOR tax) for
only 1.5x fetch (union saturates). Model needs all 6 fine-grained experts.

## Locality methodology (gates the survivors)
The whole fetch ceiling rests on "working set ~250 experts/layer", measured on
DIVERSE text. Two unmeasured-on-coherent-text quantities decide the survivors:
1. **Consecutive/span union** (gates MTP + span-batching): if K consecutive
   tokens share experts, verification fetches a small union. On DeepSeek's
   adversarially-diverse 8-token probe (e4_routing.csv): consecutive-pair
   overlap 0.08, K=8 amortization only 1.23x — near-zero. BUT that probe is
   3 domains in 8 tokens; coherent-text re-measurement in progress
   (route_coherent.bin -> span_locality.py).
2. **Session working set** (gates caching): distinct experts used over a whole
   coherent generation. If << 250/layer, the wall softens. Measuring now.

## Surviving untested levers
- Frequency-weighted precision (cold experts at P1): ~2x bytes, small quality
  cost. Untested.
- MTP speculative decode: gated on (1) above. MTP head = a full MoE layer
  (2343 tensors, shard 64), so drafting isn't free; only worth porting if
  coherent-text consecutive locality is high.
- The honest standing conclusion: 16GB fetch ceiling ~1-2 tps unless coherent
  session working set is far smaller than diverse (measuring), or hardware (RAM).
