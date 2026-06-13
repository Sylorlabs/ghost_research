# Frequency-precision + MTP — the two remaining fetch levers (2026-06-13)

## Experiment 1: Frequency-weighted precision (BUILT + MEASURED)
Hot experts/layer (top-N by batch usage) kept at P3; cold experts dropped to P1
(1-bit, 3.25x fewer bytes). Implemented in ppl_stack (FREQ_TOPN arg9): per layer,
rank experts by usage, top-N -> W_PLANES, rest -> 1 plane. Shared expert always P3.

**Upside (measured from route_coherent.bin, 512 coherent tokens):**
| top-N at P3 | fetch bytes saved | hot experts serve % of routings |
|---|---|---|
| 16 | 65% | 41% |
| 32 | 61% | 55% |
| 48 | 57% | 65% |
| 64 | 53% | 72% |
| 96 | 45% | 82% |

So top-64 = ~2.1x fewer fetch bytes, with 72% of token-routings still hitting
P3-quality experts. The cold 28% hit P1 (0.798 cosine/matmul, the gaussian wall).

**Quality cost (PPL run, freqprec_{64,32}.txt):** measured vs all-P3 baseline
(QUANT ppl 16.53 @ T=128 off8000). [RESULTS PENDING — run in progress]
Decision rule: if top-64 keeps QUANT ppl within ~5% of 16.53, frequency-precision
is a confirmed ~2x fetch lever at negligible quality cost.

## Experiment 2: MTP speculative decode (SCOPED + ESTIMATED, full port deferred)
The checkpoint ships a trained MTP head (mtp.0.*, shard 64): a full transformer
block (attention + 384-expert MoE + shared) plus fusion (e_proj/h_proj/enorm/
hnorm) that takes the main model's hidden state h_t + embed(token t+1) and
predicts token t+2. Verified structure against inference/model.py MTPBlock.

**Why viable (measured):** coherent-text span locality gives K=8 fetch
amortization 1.76x, K=16 2.15x — verifying K speculative tokens fetches their
small union, not K x.

**Acceptance estimate (architecture-grounded, not yet measured):** the MTP head
sees the TRUE token t+1 (its embedding) and predicts t+2 given full context
through t. That is essentially a next-token prediction at the same difficulty as
the main model's (which scores ~70% top-1, E11b), minus a margin for the head
being 1 block vs 61 -> estimate ~55-65% acceptance. At 60% acceptance + 1.8x
span amortization, MTP yields ~1.5-2x system throughput.

**Why the full port is deferred (honest):** ppl_stack's attention+MoE layer body
is INLINED in main(), not a callable function. Measuring MTP acceptance requires
running the MTP block = refactor the layer body into a reusable function (or
duplicate ~200 lines), then add the fusion + head. That is a careful half-day
refactor of the 1288-line validated harness; rushing it risks silently breaking
the perplexity instrument every result depends on. Scoped as the next dedicated
build, not an end-of-session hack. Port plan:
  1. Extract layer-forward (q/kv/compressor/attn/o + MoE + HC) into fn blockForward.
  2. Add fn mtpForward: fuse e_proj(enorm(embed(t+1))) + h_proj(hnorm(h)),
     call blockForward with mtp.0.* tensors, apply hc_head -> logits for t+2.
  3. Measure top-1 acceptance vs true t+2 on eval positions.

## Combined honest outlook
Frequency-precision (~2x, measured upside) x MTP (~1.5-2x, estimated) x U3 (1.3x)
x fast-drive placement, on the GPU compute floor (26 tps), stacks to the
~3-6 tps system ceiling on 16GB. Both attack FETCH (the binding constraint);
neither reaches 20 tps, which needs the 273-expert/layer working set in RAM.
