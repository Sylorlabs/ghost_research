# Research roadmap: the speed campaign (20 tps on a 16GB desktop)

**Started:** 2026-06-11, after E11b settled the quality question.
**Goal:** DeepSeek V4 Pro at >= 20 tps, same intelligence, usable context,
on: Ryzen 5 5600X (12 threads), 16GB DDR4 (~40GB/s), RX 5700 XT 8GB
(448GB/s VRAM, idle so far), NVMe ext4 2.2GB/s / NTFS 1.1GB/s (measured).
**Rule:** no retraining. The function the weights encode is the one frozen
thing; number format, operator family, routing policy, decode loop, and
memory hierarchy are all replaceable.

## Where the campaign stands

- Intelligence: SOLVED (E11b). H+P3refit+int8acts = +0.206 nats on held-out
  text, median +0.028/position, damage concentrated in tails. See
  `e11_perplexity_2026_06_11.md`.
- Speed: ~0.23 tps measured ceiling (E10) vs 20 tps target = ~87x gap.
- Context: NON-PROBLEM. MLA+compressor = ~8-10KB/token state; 128K context
  ~= 1.2GB RAM. Attention residency (~30GB always-active weights) is the
  real attention-side issue -> U7/VRAM tier.

## The physics budget (why 87x is the number)

Per token: ~28B active params ~= 11GB at P3. 20 tps = 50ms/token.
- From NVMe (2.2GB/s): <= 110MB/token -> need ~100x byte reduction
- From RAM (40GB/s): <= 2GB/token -> need total resident model <= ~12GB
- CPU XNOR compute: ~360ms/token -> need ~7x compute reduction too
- GPU: 8GB VRAM @ 448GB/s sits idle; PCIe streaming loses; right use =
  pinned always-active weights (attention + shared experts, U7)

Bytes-read : information-produced ratio ~= 16,000:1. The campaign is a
chain of independent multipliers attacking that ratio; they compound.

## Letter conventions

- **E#** = numbered experiment (E1..E11 done)
- **U#** = Unmeasured inefficiency, queued as an experiment; graduates to a
  measured lever or a documented dead end
- **P#** = bitplane count of the weight format (P3 = 3 XOR planes)
- **R#** = radical rearchitecting direction (function-space family)

## The U-ledger

| ID | question | status | multiplier |
|---|---|---|---|
| U1 | Per-token channel sparsity in experts (3072-wide swiglu: how few channels carry output?) | queued; calib_acts.bin exists | 3-10x bytes+compute if concentrated |
| U2 | Cross-expert shared structure (384/layer: shared basis + small delta?) | queued — THE decisive one | 5-30x storage; decides 20tps feasibility |
| U3 | Cache-aware routing at thin gate margins | **CONFIRMED 2026-06-11**: 25.9% fetch cut @ +0.013 nats, quality side-benefit (hysteresis) | ~1.35x, more at higher cap |
| U4 | Early exit / adaptive depth for easy tokens | queued | layer-fraction skipped |
| U5 | MTP head draft acceptance rate (head ships in checkpoint, shard 64) | queued | 2-4x, multiplies everything |
| U7 | P2/refit quantization of attention block (enables VRAM pinning of ~30GB always-active) | queued | unlocks GPU tier + frees RAM |
| U8 | Unembed shortlist (proxy top-k + exact rescore vs 129,280-row GEMV) | queued | ~10x on head compute |
| U9 | Expert disk re-layout in routing-locality order + gate-signal prefetch | queued (engineering) | 1.5-2x on fetch bandwidth |
| U10 | Swiglu gate-mask stability between adjacent tokens (piecewise-linear => exact delta decode within region) | queued | unknown; novel math |

(U6 absorbed into U3/U5 — deterministic-routing distillation overlapped both.)

U3 follow-ups queued: cap sweep (128 running, 192), eps sweep (0.05/0.2/0.3),
selection-bias variant (score + lambda*resident in the top-6 itself), pure
hysteresis WITHOUT cache (ablation separating quality effect from caching;
candidate free repair of part of the 0.2-nat tax). Prior art to compare:
Apple Cache-Conditional Experts (arXiv 2412.00099), BuddyMoE, SliceMoE.
Steal: BuddyMoE's offline-calibrated substitution pairs, score-aware eviction.

## The R-map (function-space rearchitecting; all retraining-free)

- R1 Operator replacement: refit each expert matrix into a structured
  operator (low-rank+sparse / monarch / basis+delta) by least squares
  weighted by real activation covariance. Quantization replacement, not
  bit-packing. Overlaps U2.
- R2 Expert memoization: VQ centroid table + local linear correction;
  off-manifold inputs fall back to the real expert. Converts bandwidth
  into lookup + acts as a scheduler.
- R3 Working-set pinning: constrain routing to a per-window pinned expert
  subset, PPL-test the cost. Generalization of U3.
- R4 Anchor+delta decode (video-codec decoding). Depends on U10.
- R5 MTP-native speculative batching (= U5). Fetch cost of k drafted
  tokens = union of routings, not sum.
- R6 Hash-distill score routers toward deterministic token-conditioned
  routing (layers 0-2 prove the pattern works at full quality).

## Key prior findings the campaign builds on

- Weights are maximum-entropy gaussians (signal-survival R1): weight-space
  compression beyond bitplanes is provably dead; redundancy must live in
  function space. This is why R1/R2/U2 are the axis.
- Gate margins are razor-thin (P8 chaos control): read as an exploit —
  routing flexibility is free. U3 confirmed this empirically.
- Real attention re-anchors trajectories (E11): divergence-without-damage;
  reference-cosine is a diagnostic, PPL is the judge.
- Hash layers (0-2) are deterministic, prefetchable, quantization-immune.
- V4 config gems: num_nextn_predict_layers=1 (unused MTP head!), 1M
  max_position with window-128+compressor, moe_intermediate=3072.

## Instrument

`./ppl_stack <T> <max_layers> <stream_offset> <cache_cap> <eps> <threads>`
- T=256 verdict mode (~110 min), T=128 screening (~85 min — per-layer cost
  is dominated by unique-expert conversion, not tokens; expert-conversion
  disk cache is the queued fix)
- threads default 10; per-layer checkpointing (config-keyed, deterministic
  resume verified bit-identical, auto-deleted on completion) survives
  shutdowns; rerun the same command to resume
- per-position NLL/top-1 CSV per run; REF run-to-run float noise floor
  ~±0.003 nats (works-map accumulation order)
- eval text: stream_tokens.bin offset 8000 = this repo's CLAUDE.md
  (genuinely held-out; offset 0 = DeepSeek README = memorized, only useful
  as an easy-text control)
- weights path resolves at runtime (`weightsDir()`): the NTFS drive's two
  fstab entries race at boot (/mnt/steamgames vs /mnt/corpus)

## Honest uncertainty

The multiplier chain at mid-range values clears 20 tps with margin;
pessimistic values cap this machine at 2-4 tps. U2 is the decisive
unknown. Nothing measured so far rules the goal out — and the quality
result (E11b) was the half most likely to be impossible.
