# E11: Standalone perplexity A/B — does intelligence survive XOR conversion?

**Date:** 2026-06-11
**Code:** `src/ppl_stack.zig` (full V4 forward: MLA + window-128 + gated
compressor + indexer-free exact attention at T=256, true FFN path, Sinkhorn
hyper-connections, fp8/fp4 decode)
**Raw outputs:** `e11_ppl_full.txt` (first attempt, killed at L54 by machine
shutdown 2026-06-11 00:24), `e11_ppl_full2.txt` (complete rerun),
`e11b_hard_text.txt` + `e11_positions_off8000.csv` (E11b, held-out text)

## Setup

256 real tokens from `stream_tokens.bin`, two streams through all 61 layers:
reference (f32 dequant of the shipped fp8/fp4) vs quantized (block-Hadamard +
P3-refit XOR bitplane weights + per-64 int8 activations). Each stream computes
its own routing. Final head on second-half positions → per-stream NLL/PPL.
Run is deterministic (rerun reproduces the killed run digit-for-digit).
~110 min per run on 12 cores (~6.2GB RSS).

Infra fix along the way: the weights drive has two fstab entries (same UUID,
`/mnt/steamgames` + `/mnt/corpus`) that race at boot. All harnesses now resolve
the checkpoint path at runtime (`weightsDir()`/`shardPath()` in
`signal_survival.zig`) instead of a comptime constant.

## E11 results (stream offset 0)

Layer trajectory (vs the attention-ablated E4 run): with real attention in the
loop, divergence is dramatically slower —

| metric | ablated (E4) | real attention (E11) |
|---|---|---|
| route overlap @L40 | 0.08 | 0.85 |
| route overlap @L60 | 0.12 | 0.66 |
| hidden cosine @L60 | 0.225 | 0.833 |

**The E4/E9 "chaos collapse" was substantially an attention-ablation
artifact.** Real attention re-anchors both streams to the shared input context
every layer, exactly as the E9 caveat hypothesized. Score-layer expert usage
on sequential text: ~160–273 unique experts per layer per 256-token window
(~7.7x cross-token reuse of expert fetches).

Head A/B:

```
REF   mean NLL = 0.0030 nats  ppl = 1.00
QUANT mean NLL = 0.2060 nats  ppl = 1.23
top1 agreement: 61/64 (95.3%)
```

## Instrument validity caveat (decisive for interpretation)

Decoding `stream_tokens.bin` showed offset 0–~7000 is **DeepSeek's own
model-card README** — badge/HTML boilerplate the reference model completes at
NLL 0.003 (memorized). On such text logit margins are enormous, so even
drifted hidden states snap to the same top-1. E11 therefore proves:

1. The full XOR-converted V4 runs end-to-end and stays on-rails (95% top-1,
   +0.20 nats) **on easy text** — trajectory divergence (cos 0.83) does not
   automatically mean functional divergence. Divergence-without-damage is real.
2. But it cannot answer "did intelligence survive" — easy text can't
   discriminate. A 0.2-nat leak on memorized boilerplate could balloon on
   thin-margin text.

## E11b: the real test (held-out text) — COMPLETE

Stream offset 8000 = this repo's own `CLAUDE.md` — unpublished, project-
specific technical prose (impossible to have memorized). Harness additions:
stream-offset argument, eval at every second-half position (128 instead of
64), per-position NLL/top-1 CSV (`e11_positions_off<N>.csv`).

```
REF   mean NLL = 3.1938 nats  ppl = 24.38   (valid instrument: hard text)
QUANT mean NLL = 3.3993 nats  ppl = 29.94   (+0.206 nats, +6.4% NLL, 1.23x ppl)
top1 agreement: 86/127 (67.7%)
```

Layer trajectory nearly identical to easy text (cos 0.85@L60, route_ov 0.74);
harder text engages ~35% more experts/layer (230–280) and flips routes
slightly more (0.70–0.75 vs 0.80-0.85).

**Damage-structure analysis (the key finding, `e11_positions_off8000.csv`):**

- median delta = **+0.028 nats** (vs mean +0.206) — at the typical position the
  XOR model is statistically indistinguishable from reference.
- quant beats ref outright at 50/127 positions (symmetric noise).
- Damage is concentrated: **top-10 of 127 positions carry 92% of the total
  NLL gap**; 8 positions blow up >2 nats.
- At 5 of the 8 worst positions, ref and quant made the SAME top-1
  prediction and were both wrong — genuinely unpredictable tokens
  (' dialogues', ' Hon', ' code' in project-specific phrasing) where quant
  holds thinner tail probability. Not behavioral divergence.
- top-1 agreement is 90% (47/52) where ref is confident (NLL<1); the
  disagreements live where ref itself is uncertain (52% at NLL≥1, where even
  resampling ref would disagree with itself).
- corr(ref_nll, delta) = −0.14: damage does NOT grow with text difficulty.
- Mean delta on hard text (+0.206) ≈ mean delta on memorized boilerplate
  (+0.203): a constant per-token tax, not compounding error.

## Verdict

**Intelligence substantially survives XOR conversion.** H+P3refit+int8acts
costs a constant ~0.2 nats/token, and that cost is concentrated in thinner
tails at rare/unpredictable tokens — the distribution heads (what sampling
actually uses) match the reference at 90% where it matters. The stack is not
chaotic under quantization once real attention is in the loop; E4/E9's
collapse was the ablation.

Consequences:
1. The project pivots from quality-rescue to **throughput engineering**
   (U-backlog: cache-aware routing, channel sparsity, cross-expert
   compression, MTP speculative batching). Quality regression harness =
   this exact run.
2. The remaining 0.2-nat tax is a targeted repair, not a redesign:
   candidate levers are GPTQ-style error-compensated sign selection,
   routing hysteresis at thin margins (= U3, which is ALSO the throughput
   lever — one mechanism, both wins), and P4 on attributed-sensitive spots.
3. Tail-thinning is the one capability risk to watch on functional evals
   (precise recall of rare specifics); worth a task-style eval once the
   tiered engine exists.
