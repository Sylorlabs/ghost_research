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
- DEEP-LAYER LEAN DEAD (2026-06-13, lean_from40.txt): layers 40-60 at P1 = ppl
  20.59 vs all-P3 16.53 = +0.31 nats. Deep layers do NOT tolerate 1-bit — they're
  the sensitive cascade region (E11). Depth gives no slack.
- BIT-PRECISION MAP COMPLETE: only usage-weighted (frequency-precision, cold
  experts->P1) works = 2.1x/+0.037 nats. Uniform-P2 dominated (1.44x/+0.11);
  depth-based dead (+0.31). Leanness must target rarely-routed experts, not whole
  layers or blanket cuts. ONE confirmed bit lever: ~2x.
- HASH-ROUTING CONVERSION DEAD (2026-06-13): per-token-id routing consistency on
  coherent text = 0.34 (0% of tokens route >=0.9 consistently, 3% >=0.7). Score
  routing is genuinely context-dependent (that's why DeepSeek score-routes layers
  3-60, hash-routes only 0-2). Converting to fixed token->expert mis-routes ~66%
  of slots -> tax too large to pay back. ARCHITECTURAL PRINCIPLE (measured across
  ~12 changes): the only "tax you can pay back" is on things the model barely uses
  (cold experts, +0.037 nats). Everything load-bearing (context routing, all 6
  experts, deep layers, weights) resists restructuring. V4 is maximally-tight;
  no architectural slack without retraining.

## ENGINE WORKS (2026-06-13) — the deliverable
- chat_v4 (src/chat_v4.zig): XOR-quant V4 on 16GB desktop, prompt->next-token.
- "The capital of France is" -> "Paris" (logit 23.78, decisive), top-5 all
  sensible. END-TO-END PROVEN: the 1.6T frontier model runs + predicts correctly
  on consumer hardware with pure XOR/popcount experts.
- 47min/forward un-optimized (0.23 tps). Throughput = remaining engineering
  (gen loop + KV cache + tiered fetch + freq-precision + GPU kernel -> ~3-5 tps).

## BATCHED ENGINE VALIDATED (2026-06-13) -> 3-5 tps achievable
- Forged P3 experts read 5.3 GB/s from fast drive (forge_experts.zig). Batched
  B=512 + freq-precision = 5.4 tps AGGREGATE (measured components: 5.3GB/s read,
  43 tps GPU compute, 384 union, 35.5MB/expert, KV 5.2GB fits). CLEARS 3-5.
- Gate: forge ~440GB experts to fast drive (free ~440GB on SN850X). Full engine
  build justified. Single-stream stays ~0.5-1 tps (fetch wall); 3-5 = batched.

## WEIGHTS ARE NOISE (2026-06-13) — representation space CLOSED
- e20: real expert statistically INDISTINGUISHABLE from gaussian noise (WHT top-1%
  8.36 vs 8.37, autocorr ~0, kurtosis +0.10, only 2.9% row-norm var captured by P3).
- Trained weights are maximum-entropy -> ALL representation math precluded (linear/
  spectral are rotations, gaussian-invariant; nonlinear precluded by high-dim
  manifold). Can't compress white noise. sqrt(2/pi) was the first sign. This is WHY
  the model is strong + incompressible. NO new math remains. Path = systems (batched
  engine, KV-dissection on activations) + hardware, not representation.

## OPTIMAL QUANTIZATION beats bitplanes (2026-06-13, e21) — Micah was right
- Lloyd-Max optimal scalar quant: 0.9921 @ 3.13 bits vs bitplane P3 0.9812 @ 3.25.
  To MATCH P3 fidelity, Lloyd-Max needs ~2.5 bits -> ~1.3x fetch reduction, FREE,
  SAME quality. VQ/codebook (computing) typically beats scalar -> possibly more.
- KEY CORRECTION: "weights are noise" precludes STRUCTURE-exploitation, NOT
  quantizer-optimality. Greedy bitplanes don't hit the gaussian rate-distortion
  limit; Lloyd-Max/VQ get closer. Two different axes — I over-extended the noise
  result. Real ~1.3x fetch lever, stacks with freq-precision/etc.
- CATCH: codebook quant breaks the XNOR popcount kernel (lookup vs popcount) ->
  different/slower compute, but fetch is binding (GPU has compute headroom), so
  the fetch win holds. Worth wiring into the engine.

## E21 CORRECTION (2026-06-13): optimal-quant lever is ~1.15x, not the ~1.3x I eyeballed
- Full table: bitplane P3 0.9812@3.25b; Lloyd-Max 0.9921@3.13b, 0.9563@2.13b;
  VQ d=2/8bit 0.9976@4.13b (near-lossless), VQ d=4/8bit 0.9638@2.13b.
- Lloyd-Max matches P3 fidelity (0.9812) at ~2.83 bits = **1.15x fetch reduction**,
  free, same quality (interpolated; I'd wrongly eyeballed 1.3x — corrected).
- VQ near-lossless at 4 bits but not better per-bit at the low rate that matters.
- HONEST: optimal quantization IS a real lever (beats greedy bitplanes), but
  modest (~1.15x) AND breaks the XNOR popcount kernel (codebook lookup), so it
  trades a fetch win for slower compute. Real but small; stacks with the others.
- Standing lesson reaffirmed: "no structure" != "no headroom" (the lever exists),
  but measure the magnitude before claiming it (1.15x not 1.3x).

## KV-DISSECTION (2026-06-13, kv_4.txt) — real but NOT free
- 4-bit KV latent (below the fp8 baseline): QUANT ppl 18.20 vs fp8 16.53 = +0.11
  nats. Halving KV below fp8 costs ~the whole XOR tax again. A throughput/quality
  TRADE: ~2x batch headroom (-> ~2x aggregate tps) for +0.11 nats. NOT the free 2x
  hoped. DeepSeek's fp8 KV was near the floor (unlike weights, where fp4 was the
  design point). 3-bit pending (will be worse).
- vs frequency-precision (+0.037 for 2x fetch): KV-dissection is a worse trade,
  but a DIFFERENT axis (batch size vs fetch bytes) so they stack if the +0.11 is
  acceptable. Activations have a little squeeze left below fp8, but not free.

## EARLY-EXIT DEAD (2026-06-13, e22) — speed lever B
- Consecutive-layer activation cosine: rises 0.52->0.81 by L9, then PLATEAUS
  ~0.79-0.83 through L12-30 (no convergence; L28->29=0.76, even falling). The
  representation keeps transforming every layer -> no skippable late layers ->
  early-exit weak. Corroborates depth-leaning (deep layers load-bearing). Every
  layer is doing real work. (Measured L0-30; trend + depth result say no.)
- Speed levers remaining: MTP (~1.8x, big build), batched engine (validated),
  KV-4bit batch (2x, +0.11 nat trade), optimal-quant fetch (1.15x). Tax-payoff:
  refit-alternations (running), U3 (~40%, confirmed), optimal-quant (same-bits
  quality gain).

## REFIT-ALTERNATIONS DEAD (2026-06-14, refit_2.txt) — tax-payoff A
- refit_alt=2: QUANT ppl 16.48 vs alt=0 baseline 16.53 = -0.05 (within +-0.015 nat
  REF noise) = NEGLIGIBLE. More error-feedback re-greedy passes don't pay off the
  XOR tax; bitplanes + 1 refit already hit the structural optimum. Free XNOR-native
  tax-payoff is exhausted.
- TAX-PAYOFF MAP: refit-alternations dead; U3 hysteresis ~40% (confirmed, free);
  Lloyd-Max/VQ better quantizer (~0.011/matmul) but breaks XNOR kernel (GPU path).
  Paying off tax = U3 + quantizer-family-switch, not tuning bitplanes harder.
- refit_alt=4 (refit_4.txt) CONFIRMS: QUANT ppl 16.51, 48/63 top1 — identical to
  alt=2 (16.48) and baseline (16.53). 2 vs 4 error-feedback passes: no difference.
  Refit-alternations fully closed.

## THE STORAGE-BANDWIDTH WALL (2026-06-14) — the real, final gate, MEASURED
Routing skew (route_coherent.log, T=512) + drive bandwidths (O_DIRECT) settle the
whole speed problem analytically. No more projection — these are the binding facts.
- ROUTE SKEW: every score-routed layer touches 258-383 of 384 experts over 512
  tokens (early layers 383/384). Over real context you touch ~ALL experts per
  layer. route_ov ~0.73-0.85 is TEMPORAL locality (the ~1.3x U3 cache lever), NOT
  spatial sparsity. => the working set CANNOT shrink to a small resident hot-set.
- DRIVE BANDWIDTH (cold, O_DIRECT, measured today):
    FAST  WD_BLACK SN850X  (mounted /)           = 5.0 GB/s
    SLOW  Kingston SNV3S1000G (/mnt/corpus, holds 806GB source) = 1.1 GB/s
- FREE SPACE: fast / = 9.7 GB ; slow /mnt/corpus = 74 GB. (Fast drive is 559GB
  total, 521GB used by OS+games — cannot free ~250GB+ there without nuking system.)
- WORKING SET (full 58 MoE layers; one P3 layer measured = 14GB):
    uniform P3 (validated quality, +0.1 nats) = 812 GB
    freq-precision mix (hot P3 / cold P1, 2.1x) = ~387 GB
    uniform P1 (1-bit, degraded quality)        = 250 GB
- HARD FACT: even the SMALLEST full working set (P1, 250GB) exceeds ALL free fast
  storage (84GB combined). You cannot hold a full-quality model on this machine's
  free space, and routing forbids keeping only a small subset. The wall is
  fast-storage CAPACITY, and it is absolute on the current disks.
- AGGREGATE TPS = B x bandwidth / W (read-bound, compute overlaps), B=512:
    on FAST 5.0GB/s:  P3 3.2 tps | mix 6.6 tps | P1 10.2 tps   (but won't FIT)
    on SLOW 1.1GB/s:  P3 0.7 tps | mix 1.5 tps | P1 2.3 tps
- THE ONLY WAYS THROUGH (all measured, none "data center"):
  1. Delete 806GB source -> slow drive gains ~880GB free -> forge full P3 (812GB)
     to slow drive -> ~0.7 tps full quality; or P1 (250GB) -> ~2.3 tps degraded.
     IRREVERSIBLE (source is the only copy; safe forge-then-delete impossible at
     84GB free -> would be delete-as-we-forge, per-shard). NEEDS user authorization.
  2. Add ONE consumer NVMe (1-2TB, ~$100-150) -> forge freq-mix (387GB) to it ->
     ~6.6 tps full quality. Consumer hardware, not data center. CLEANEST path.
  3. 20 tps goal: B x bw / W = 20 -> at B=512, mix 387GB needs 15 GB/s ~= 3x NVMe
     RAID0 (consumer) OR larger B with more RAM (aggregate-throughput, not single-
     stream latency). Single-stream interactive latency at 20 tps needs the whole
     working set readable per-token-fast = ~387GB in RAM/VRAM = not this machine.
- BOTTOM LINE: intelligence is solved (XOR survives, +0.1 nats, "Paris"); compute
  is solved (GPU 26 tps, batched path validated); the residual is PURELY storage
  capacity x bandwidth. It is a hardware-shape problem now, not a math problem.
