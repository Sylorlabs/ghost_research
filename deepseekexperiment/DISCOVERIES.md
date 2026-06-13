# DISCOVERIES — running ledger (DeepSeek V4 Pro on a 16GB desktop)

One line per discovery, newest at the bottom of each section. Full detail in
`docs/`. Goal: same intelligence, usable speed (target 20 tps, stretch 100),
16GB RAM / RX 5700 XT / Ryzen 5600X. Rule: no retraining the model.

## Intelligence (SOLVED)
- XOR-native format (block-Hadamard + 3 refit bitplanes + int8 acts) = 0.95-0.98
  cosine/matmul; naive 1-bit hits the sqrt(2/pi)=0.798 gaussian wall. [signal_survival]
- Full 61-layer perplexity A/B on held-out text: XOR model +0.206 nats vs the
  data-center original (ppl 24.4->29.9). Median token +0.028 nats; damage in
  rare-token tails, not core capability. INTELLIGENCE SURVIVES. [E11b]
- The "chaos collapse" was an attention-ablation artifact; real attention
  re-anchors trajectories (cos 0.83@L60 vs 0.22 ablated). [E11]
- Cache-aware routing (U3) repays ~40% of the conversion tax FOR FREE (also
  cuts fetches); top-1 agreement 86->90/127. Routing hysteresis damps
  thin-margin flip noise. [U3]
- On 39% of tokens the XOR model predicts BETTER than the original (symmetric
  noise, not pure degradation). [E11b per-position]

## Compression (linear family: DEAD at every level)
- Weights are max-entropy gaussians: no exploitable sign structure. [signal_survival]
- Experts share NO common row-space (held-out rel-err 0.91 @7x ~= random). [U2]
- Individual experts are near-full-rank (90% energy @ rank ~2075/3072). [B8]
- Global activation manifold high-dim (56% @ 128 dims on 15.6k samples; the
  488-sample 94.6% was a MIRAGE). [B5/B5-v2]
- Experts are functionally distinct (0% sibling pairs @ cos 0.70). [E15]
- Single-context activation manifold is HIGH-dim too: 292 dims/90% over 512
  tokens (the 128-sample "84-dim" was a MIRAGE, same as B5). [E19e]
- => Static low-rank surrogate experts DEAD: held-out fidelity caps 0.61, basis
  covers only 58% of held-out input energy at full rank. [surrogate_verdict]
- LESSON: never trust a low-dim finding without held-out test at >=10x dim
  (fooled us twice: B5@488, E17@128).

## Speed / I-O (characterized)
- Pure XNOR kernel = fastest (10.7 Gw/s, 1 thread); fp4-decode-on-read 7x slower. [E8]
- Measured I/O: ext4 2.18 GB/s, NTFS 1.08 GB/s. Single-token fetch-bound ceiling
  ~0.23 tps (92% fetch stall). [E10]
- Full P3 expert store ~600GB: fits on NO drive here (46GB ext4 + 74GB NTFS free).
  Experts stay fp4 on NTFS. [strategy]
- TWO FLOORS: fetch (~0.5 tps feasible) AND compute (~3.4 tps even with free
  fetch, 37.8 GMAC/token / CPU XNOR). 20 tps is below the COMPUTE floor for full
  experts. [two_floors]
- Batching amortizes fetch ~7x at B=256 (expert union saturates toward 384, not
  B*6). [E0 from works.count]

## Engine infra (built)
- Runtime weights-path resolution (fstab race fix). [commit e097ae1]
- Per-layer deterministic checkpointing (survives shutdown, bit-identical resume).
- Forged engine core: 16.8GB always-active path (attn+compressor+shared experts,
  P3-packed) on ext4, round-trip verified (diff 3.7e-9). [forge]
- Detached session-independent experiment queue (survives session death).

## OPEN FRONTIER (compute floor — NOT refuted by incompressibility)
- The compute floor (~3.4 tps) is a CPU-XNOR floor. The idle RX 5700 XT
  (448 GB/s, working 1-bit Vulkan GEMV shader exists) + batching is UNTESTED and
  attacks it. [investigating now: GPU XNOR throughput vs CPU 10.7 Gw/s]
- Early-exit / depth-adaptive: 52% of tokens are easy (<0.05 nat damage); if they
  need fewer layers, the compute floor rises. Untested (needs retraining-free
  exit signal). [queued]
- Precision-tier self-speculation (1-bit draft, P3 verify). [idea]

## GPU (2026-06-13, NEW — the compute-floor lever, CONFIRMED promising)
- GPU 1-bit GEMV benchmark (`bench_gpu.zig`, RX 5700 XT, naive shader +
  re-upload every call + float math): 20.4 Gw/s = 1.9x CPU-XNOR already. [bench_gpu]
- VRAM-resident packed-XNOR memory-bound ceiling ~1100 Gw/s (~103x CPU) -> compute
  floor could move 3.4 -> ~30-70 tps with an optimized kernel.
- CAVEAT: 600GB experts don't fit 8GB VRAM; PCIe (16GB/s) bottlenecks the full
  model, amortized only by batching. Resident rate applies to the core + batch
  working set. Next: optimized packed-XNOR resident-weight kernel + batched GEMM.
- BATCHED-GPU path model: at B>=32, PCIe transfer (disk->VRAM) amortizes below
  GPU compute -> aggregate ~29 tps (GPU-compute-bound at the resident rate).
  CLEARS the 20 target IN AGGREGATE (not single-stream latency). B=32/4K-ctx KV
  ~1.2GB fits 16GB. GATE: optimized kernel efficiency (naive=20 Gw/s; need
  >=300 Gw/s for ~8+ tps, ceiling 1100). [bench_gpu + model]
