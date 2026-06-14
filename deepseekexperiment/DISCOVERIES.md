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
- GPU resident-VRAM result (`bench_gpu2.zig`, gpu.benchResidentGEMV): putting
  weights in DEVICE_LOCAL VRAM (ReBAR, upload once) = 124 Gw/s single-plane,
  6.1x the naive PCIe shader (20.4). VRAM residency is the big lever.
- BUT honest apples-to-apples: P3 = 3 planes -> 41 Gw/s P3-equiv, which is 2.6x
  SLOWER than the 12-core CPU (107 Gw/s P3). The naive shader (per-bit branching,
  f32 acts, 1 thread/row, low occupancy) loses to the CPU. The GPU is NOT a free
  win with this kernel.
- Optimized P3-popcount ceiling (VRAM bandwidth-bound, 15.4GB/tok @ 448GB/s) =
  ~29 tps = 8.6x the CPU compute floor — but ONLY for VRAM-resident data (8GB);
  600GB experts stream over PCIe (batch-amortized). GATE: build the optimized
  popcount/high-occupancy/packed-act kernel; current naive one isn't enough.
- GPU OPTIMIZED KERNEL (2026-06-13): per-element batched GEMM, weights resident
  in VRAM, scales ~linearly with batch: B=32->741 Gw/s (2.3x CPU), B=64->1487
  (4.6x), B=128->2955 Gw/s (9.2x CPU) = P3 985 = 26.1 tps COMPUTE floor. BEATS
  the CPU and CLEARS 20 tps on the compute axis. (Tiled kernel worse: cuts
  occupancy. Per-element wins via thread count; ~91% of fp32 peak at B=128.)
- BUT honest system reconciliation: compute floor BROKEN (3.4->26 tps), yet the
  SYSTEM is still FETCH-bound. At B=128 the expert union saturates (~300/layer),
  so batching amortizes fetch only ~2.5x -> 3.7GB/token. From NTFS (1.08GB/s) =
  0.29 tps; fast NVMe (7GB/s) = 1.9 tps; RAM (40GB/s, needs ~600GB) = 11 tps.
  => 20 tps now needs (GPU compute, DONE) + (experts in ~600GB fast RAM, HARDWARE).
  The 16GB box stays fetch-bound ~0.29 tps regardless of the GPU. The wall is
  now cleanly MEMORY CAPACITY, not compute and not algorithm.
- TOP-K REDUCTION (2026-06-13): DEAD. REF ppl top-6=14.06, top-4=17.13(+0.20),
  top-3=17.84(+0.24), top-2=25.42(+0.59). Dropping below 6 experts costs MORE
  quality than the whole XOR tax, AND fetch savings are sublinear (union
  saturates: 198->134/layer at top-3, only 1.5x). The model genuinely uses all
  6 fine-grained experts. Not a viable fetch lever.
- FETCH-LEVER STATUS: compression DEAD, surrogate DEAD, top-k DEAD, faster-drive
  capacity-BLOCKED, frequency-precision UNTESTED (~2x bounded), MTP-speculative
  UNTESTED (fetch-FREQUENCY via consecutive-token locality — last big lever).
  Honest 16GB fetch ceiling stays ~1-2 tps. The 49B-active-params/token floor is
  physical; 20 tps needs RAM (hold working set) — not an assumption-wall.
- COHERENT-TEXT SPAN LOCALITY (2026-06-13, route_coherent.bin 512 tok, span_locality.py):
  coherent text is 4x more local than the diverse probe — consecutive-pair overlap
  0.32 (vs 0.08), K=8 span amortization 1.76x, K=16 2.15x. => MTP/span-batching is
  VIABLE as a ~1.8-2.2x fetch lever (the diverse-probe near-zero was a measurement
  artifact — re-measuring on coherent text was the right call). BUT session working
  set still 273/layer over 512 tokens (427GB) — doesn't fit 16GB; caching alone
  can't hold it. Honest stacked 16GB ceiling rises to ~3-6 tps (MTP 1.8x x
  freq-precision 2x x U3 1.3x x fast-drive placement), measured-grounded, still
  not 20 (session working set needs RAM). MTP port now justified.
- FREQUENCY-PRECISION CONFIRMED (2026-06-13, freqprec_*.txt): top-64 experts/layer
  at P3 + cold at P1 = 53% fewer fetch bytes (~2.1x) for only +0.037 nats over the
  all-P3 quant (ppl 16.53->16.94). top-32 too aggressive (+0.26 nats). Cold experts
  tolerate 1-bit (low routing weight). REAL measured fetch lever ~2x.
- LEAN-BIT SWEEP running: P2-global (1.6x leaner, end-to-end test never done) +
  per-layer lean-from-{40,30} (how deep layers tolerate P1). The XOR insight applied
  per-layer to attack bytes-per-expert.
- LEAN-BIT P2-GLOBAL (2026-06-13, lean_P2.txt): all experts at 2-bit = ppl 18.35
  vs all-P3 16.53 = +0.11 nats for only 1.44x fewer bytes. DOMINATED by
  frequency-precision (2.1x for +0.037). Lesson: usage-weighted precision >
  uniform — degrade COLD experts (low weight), not all. Per-layer deep-P1
  (lean-from-40/30) running to test if depth adds slack beyond usage-weighting.
