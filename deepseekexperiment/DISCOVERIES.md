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

## STREAMING ENGINE ON THE SLOW NVME — overlap MEASURED (2026-06-14, bench_stream)
Built the missing integration test (bench_stream.zig) and ran it on a REAL forged
layer copied to the slow drive (/mnt/corpus/engine_test/L30_experts_P3.bin, 14.27GB,
no source deleted). Answers the one unknown behind every tps projection: does disk
read run at full speed CONCURRENTLY with GPU compute?
- solo disk read (O_DIRECT, 3 passes / 42GB)  = 1.23 GB/s  (honest sustained QLC;
  dd's earlier 1.5 caught the SLC cache region).
- solo GPU batched XNOR (tiled shader, B=64)   = 405 Gw/s (1-plane) / 125 eff P3.
- CONCURRENT disk + GPU                          = 1.23 GB/s = **100% of solo**.
  => read/compute OVERLAP IS REAL, zero contention. The B x bw / W projection holds.
- Disk-bound confirmed even at the modest tiled rate: per-step compute (top-6/token)
  P3 ~304s vs disk read (all 384 experts/layer) ~673s; P1 compute ~29s vs disk 203s.
  Disk dominates at every precision -> GPU speed does not gate; bigger batch is free.
- MEASURED aggregate tps from the slow NVME = B x 1.23 / W:
    B=512:  P3 0.78 | mix 1.63 | P1 2.52     B=1024:  P3 1.6 | mix 3.3 | P1 5.0
  Scales linearly in B until 16GB caps KV+acts (MLA KV ~4.7KB/tok -> B=1024 @ 2k ctx
  ~ <10GB, room to spare). So batch is the live lever on this drive.
- Slow-drive WRITE measured = 147 MB/s (14GB copy in 94.8s; QLC post-SLC). Forging
  the full model TO this drive is write-bound: P1 250GB ~28min, P3 812GB ~90min
  (plus forge compute). Inference READS at 1.23 GB/s though -- write cost is one-time.
- "ENGINEER IT BETTER" path now measured & concrete: (1) delete source -> forge P1
  (250GB) or mix (387GB) to slow drive; (2) run batched engine at B=1024-2048 ->
  ~3-10 tps aggregate (P1 degraded / mix near-full quality). Gate remains: 74GB free
  can't hold even P1 (250GB) -> needs the source deleted (user-authorized, irreversible).
  Dual-drive parallel read deferred (fast drive only 9.7GB free -> negligible add).

## P3 SCALE-PACKING WASTE FIXED (2026-06-14, e23) — full P3 now FITS the slow drive
Investigated why forged P3 (870GB) is BIGGER than the fp4 source (806GB) when P3 is
supposed to be fewer bits. Found the waste in packBitplanesRefit (signal_survival.zig):
- format = 3 sign-plane bits/w (=3.0 b/w, correct) + ONE f32 scale per (plane x
  64-block) = 3*32/64 = **1.5 b/w of scales** -> total **4.5 b/w > fp4's 4.25**.
  The scales cost half-again as much as the data. That is the entire mystery.
- FIX = coarsen the scale block (one f32 per 256 weights, not 64). bits/w = P + P*S/B.
- MEASURED on 12 real experts (layer 30, 3072x7168), cosine/matmul vs fp4:
    block 64  (now): cos 0.97475  4.50 b/w  870GB  (> source)
    block 128:       cos 0.97376  3.75 b/w  725GB
    block 256:       cos 0.97327  3.375 b/w 653GB   <-- recommended
    block 512:       cos 0.97302  3.19 b/w  617GB
  block 64->256 costs 0.0015 cosine (0.15%, << the +0.1-nat XOR tax & run noise) for
  a 25% size cut. Confirms prior "block 16-256 fidelity-free" on real experts.
- IMPACT: full-quality P3 at block 256 = **653GB < 806GB source**. Re-forging at
  block 256 means forged/layer (10.7GB) < source shard (12.6GB) -> delete-as-we-forge
  FREES ~1.9GB/layer (no deadlock), fits the slow drive with ~213GB to spare, and
  needs ZERO collateral deletion (no pagefile/games/corpus). Final quality = full P3.
- Further options (more margin, slightly more code): fp16 scales (block256 -> 617GB),
  block512 (617GB). fp8 scales REJECTED (scale magnitudes need >fp8 precision; block-
  coarsening is the proven-safe lever, fp8 unproven). Engine kernel must read scales
  per 256-block to match (forge + ppl_stack/gpu/chat_v4 unpack change).
- This reopens "full P3 on the slow drive" as feasible & clean -- the option that
  looked impossible (870GB, deadlock, collateral) was an artifact of f32-per-64 scales.

## BEYOND-XOR CONVERSION FRONTIER (2026-06-14, e24) — real but ~1.2x, source kept
User reframe: we are DISK/fetch-bound, compute is ~free (GPU 2-7x > disk), so pick the
format by RATE-DISTORTION not XNOR-friendliness -- "beyond XOR" is allowed (costlier
decode but smaller = net win). Also: KEEP the source (don't delete, may want later).
Measured bitplanes vs Lloyd-Max scalar (adaptive k-means, real distribution) on 12
real experts, honest overhead (f32 scale/256 = 0.125 b/w):
    format        b/w     cos      fullGB   B512 tps
    bitplane P2   2.250   0.93612  435      1.35
    bitplane P3   3.375   0.97327  653      0.92   <- current quality bar
    bitplane P4   4.500   0.98607  870      0.70
    lloyd N=4     2.125   0.93961  411      1.43
    lloyd N=6     2.710   0.97065  524      1.14
    lloyd N=8     3.125   0.98261  604      0.99   <- beats P3 at fewer bits
    lloyd N=16    4.125   0.99519  798      0.76
- BEYOND-XOR CONFIRMED: Lloyd-Max beats bitplanes per bit everywhere (N=8 0.9826 @
  3.125 > P3 0.9733 @ 3.375). To MATCH the P3 bar, Lloyd needs ~2.75 b/w vs 3.375 =
  ~19% smaller, ~1.2x faster, SAME quality, free. Decode = table lookup << disk, fine.
- MAGNITUDE is ~1.2x, capped by weights-are-noise entropy floor (consistent w/ e21's
  ~1.15x). NOT an order-of-magnitude win. Real, modest, stacks with the scale fix.
- "FREE STORAGE while keeping source" -> NOT achievable: source (806GB) is near the
  entropy floor (noise, ~no lossless recompression), and even the smallest good lossy
  forge (Lloyd N=4 411GB) cannot fit in the ~70GB free alongside the 806GB source.
  Keeping source AND a full forged model exceeds the machine's storage, period.
- "PAY TAX LATER": can forge aggressive-low (N=4 2.1 b/w 411GB cos 0.94 ~1.4 tps) for
  max speed/min size, recover ~40% via U3 routing. Partial; still won't fit by source.
- STORAGE FORK is unavoidable (any one must give): add a drive | eventually replace
  source | forge only part. Conversion improves the speed/quality knob (~1.2x) but
  does not dissolve the capacity wall while the 806GB source is retained.
- NEXT conversion lever to measure (could stack toward ~2.5 b/w eff): ADAPTIVE
  precision across matrix-types (w1/w2/w3), layers (depth), and expert temperature --
  spend bits where sensitive. Not "compressing noise" -- allocating bits by impact.

## SELF-SPECULATION DEAD (2026-06-14, spec_accept.log) — no cheap draft tracks the model
Tested spec-decode-as-fetch-amortization: a cheap RAM-resident/low-fetch draft proposes
K tokens, the big model verifies all K in ONE batched fetch -> single-stream fetch
amortized ~K x IF draft acceptance is high. Measured cheap-draft quality (T=64, off8000,
full 61 layers); full-model f32 baseline ppl = 24.23:
    draft                       f32 ppl   note
    shared-expert only (resident)  561     23x worse than full -> terrible predictor
    top-1 routed expert            194     8x worse
    P1 full model (1-bit)          213     9x worse; agreement w/ f32-full only 29%
- VERDICT: every cheap DERIVATIVE of the model (fewer experts / fewer bits) is a BAD
  predictor of the full model -> low acceptance -> self-speculation gives ~nothing.
  Exactly what weights-are-noise/experts-distinct predicts: the model has NO cheap
  approximation; its quality is genuinely spread across all 6 experts at >=P3. The only
  trained draft is the MTP head (~1.8x, in shard 64) -- it works because it was TRAINED
  as a draft, unlike these derived ones. Standard spec-decode needs a separately-trained
  small model = not available (no retraining).
- THE INTERACTIVE FLOOR (first-principles, post-measurement): per token ~24B routed-expert
  params, freshly selected from a 283GB bank (P3), CHANGE every token -> can't be cached
  (bank >> 16GB; useful caps need ~278GB) and can't be approximated (just measured). Must
  fetch ~10GB/token: fast drive 0.5 tps, slow 0.12 tps. 20 tps needs the 283GB bank
  resident in fast memory = not this machine. Wall is hardware-shape, not algorithmic.
- Levers that survive (don't need a cheap approximation): resident-core+stream-routed
  (~2x), MTP (1.8x), Lloyd (1.2x), batching (offline aggregate). Stack to low-single-digit
  interactive / multi-tps offline.
- OPEN (Micah's reframe): the meaning is RELATIONAL (vectors + relations), not in weights.
  Weight relations tested dead (U2/E15/B5). UNTESTED = ACTIVATION-vector relations at
  runtime (e26): if related tokens give related hidden states, computation is REUSABLE
  (cache hit skips fetch+compute). Measuring now via ACT_DUMP geometry.
- GOTCHA logged: ppl_stack checkpoint key (T/off/cap/eps) omits topk/gplanes -> different
  draft configs collide on ckpt; safe only because completion auto-deletes it. Add to key.

## ACTIVATION-VECTOR RELATIONS (2026-06-14, e26) — structure real, but not fetch-reducing
Micah's principle: meaning is RELATIONAL (vectors + relations between them), not in
weights -> dissect the activation-vector geometry at runtime for computation reuse.
Measured on real MoE-input vectors (post-ffn-norm), T=128 off8000, all 61 layers:
- CAUSAL REUSE: for each token, best cosine to a PAST token's hidden state. Hits at
  cos>0.90 = **0.00 at EVERY layer**; NN-mean (best match) ~0.62. Output reuse needs
  ~0.98 to be safe -> caching expert outputs by input vector is DEAD (no near-duplicates).
- BUT STRUCTURE IS REAL: NN-mean 0.62 vs ~0.03 for random 7168-d gaussians = ~50 sigma
  more correlated. Activations are strongly ANISOTROPIC (cone-like), meanCos rises with
  depth 0.10(L1)->0.34(L60). Micah is RIGHT the vectors relate -- but the relation is a
  shared GLOBAL direction, not token-specific similarity, so it doesn't reduce fetch.
- dim90 ~85/7168 is NOT low-dim: capped by n=128 tokens (max 127); 85 of 127 available
  dims hold 90% energy = activations FILL their span (high-dim), corroborating B5. True
  intrinsic dim unmeasurable here (needs ~70k tokens; refused the small-sample mirage).
- VERDICT: the activation-relational axis is high-entropy too (like weights). Every
  probeable axis -- weights, weight-relations, activation-manifold, activation-relations,
  cheap-drafts, reuse, early-exit -- is exhausted by MEASUREMENT. No software lever breaks
  the fetch wall by an order of magnitude. CONVERGED: achievability is hardware-shape.
  Software ceiling ~ resident-core(2x) x MTP(1.8x) x Lloyd(1.2x) ~ 4x -> ~1 tps interactive
  (capacity-gated) / multi-tps offline-batch. 20 tps interactive needs the 283GB bank in
  fast memory = consumer hardware add (RAM or fast NVMe), not a missing algorithm.

## CONVERSION FRONTIER HITS THE SHANNON FLOOR (2026-06-14, e27/e28) — "beyond XOR" = ~1.4x, a THEOREM
Micah: "something beyond xor; find what's expensive and convert it." Research-grade
output-aware + information-theoretic analysis on the expensive part (experts), real L30
activations + dumped experts.
- E27 activation-aware (AWQ): full swiglu OUTPUT cosine on real acts (uniform/Lloyd/AWQ):
    bits  uniform  lloyd  awq-unif  awq-lloyd
    2     0.249    0.840  0.364     0.812
    3     0.889    0.960  0.884     0.939
    4     0.977    0.979  0.977     0.975
  AWQ does NOT help (slightly hurts). MECHANISM: expert input is post-RMSNorm -> per-channel
  magnitude already equalized (anisotropy only 2.4x vs the 10-100x outliers AWQ needs).
  RMSNorm already did AWQ's job. Lloyd >> uniform confirmed at the OUTPUT level too.
- Activation covariance (GPTQ headroom): 90% energy needs 83/128 dims, top-8 eigvals only
  34% -> no few-direction dominance -> GPTQ/projection helps only modestly; expert compute
  genuinely uses ~80+ activation dims (corroborates B5/E19).
- E28 SHANNON RATE-DISTORTION CEILING (definitive "how far beyond XOR, ever"): weight
  kurtosis 3.125 = gaussian -> R(D)=0.5 log2(sigma^2/D) applies. Optimal-scalar(Lloyd) vs
  Shannon bound: bits2 gap 0.474b (1.39x), bits3 gap 0.465b (1.38x). => the BEST POSSIBLE
  quantizer (lattice/trellis, QuIP#/QTIP) saves ~0.47 b/w = ~1.4x over scalar. THEOREM for
  gaussian sources, not a creativity limit.
- COMPLETE CONVERSION FRONTIER (full quality, experts): bitplane-P3 3.375 b/w -> scalar-
  Lloyd ~2.75 -> lattice/trellis (Shannon floor) ~2.3 b/w. Absolute smallest full-quality
  bank ~= 1.546e12*2.4/8 ~ 464GB (vs 806 source). STILL >> 70GB free / 16GB RAM -> even at
  the information-theoretic floor the model can't sit in this machine's fast memory.
- FINAL: "beyond XOR" is real (lattice/trellis) but bounded ~1.4x by Shannon; with the
  scale-fix ~1.7x smaller than source, never the 10x needed to fit. Conversion axis closed
  at its theoretical limit. Achievability = hardware (fast memory for the ~464-653GB bank),
  proven by THEOREM not just failed attempts.

## MAD-SCIENTIST BATTERY (2026-06-14, e29 + entropy coding) — all dense, one over-claim corrected
Micah: "you ran out of ideas, try riskier mad-scientist experiments." Ran a battery; all
confirm the model is information-DENSE (no exploitable concentration anywhere):
- ADAPTIVE-K (e29A): gate route-weights by rank = 0.30/0.20/0.16/0.13/0.11/0.10 — nearly
  FLAT. 90% of route weight needs 5.48 of 6 experts -> 1.09x. Load-balancing training
  deliberately spreads routing; no "easy token needs fewer experts." DEAD.
- PER-MATRIX SENSITIVITY (e29B): w1/w2/w3 equally bit-hungry (3-bit out-cos 0.954/0.950/
  0.960). No imbalance -> adaptive per-matrix precision DEAD.
- LOSSLESS ENTROPY CODING (zstd): CAUTION TALE. Whole-file/region samples gave 1.59x-4.3x
  and I briefly claimed "free storage exists." CLEAN per-tensor: fp4 expert WEIGHTS = 1.030x
  (nibble entropy 3.884/4 bits = near-max-entropy, INCOMPRESSIBLE). The apparent gain was
  SCALE tensors (7.3x but only ~6% of bytes) + headers. Net free storage ~negligible.
  "Weights are noise" CONFIRMED at source. Lesson: isolate the variable (tensor type) before
  claiming; a dirty sample over-claimed 4x.
- UNIFYING MECHANISM (measured from many angles): gaussian weights (incompressible) +
  RMSNorm-flat activations (2.4x, kills AWQ/column-sampling) + flat load-balanced gate
  (kills adaptive-k) + high-dim Hessian (kills GPTQ/projection/low-rank) + no near-duplicate
  activations (kills reuse) + no cheap approximation (kills spec-decode self-draft). V4 Pro
  is an unusually well-balanced, information-dense model; no wasteful concentration to exploit
  without retraining.
- REMAINING REAL LEVERS (complete set): scale-packing fix (e23 ~1.3x) + Lloyd/trellis quant
  (~1.4x, Shannon-bounded) + resident-core+stream (2x) + MTP (1.8x) + batching (offline).
  Everything else tested DEAD by measurement. Achievability = hardware (fast memory for the
  bank) OR accept lower quality (P2 ~2.25 b/w) for more speed -- the "pay tax later" knob.

## TIERED STREAMING ENGINE — BUILT, TESTED, MEASURED (2026-06-15, stream_engine.zig)
Micah: "make it fit entirely in storage, fetch into RAM, disburse into VRAM/CPU cache."
Built the integrated tiered engine (disk->RAM->VRAM->compute). doc: docs/tiered_streaming_engine_2026_06_15.md
- COMPUTE TIER CORRECT: GPU shader vs CPU reference on identical packed weights = cosine
  1.000000. (Shader is binary-weight x fp-activation dot, matches the real format.)
- OVERLAP MEASURED on real forged experts: fast SN850X 4.0-4.3 GB/s under GPU load (~85% of
  5.0 solo; gap = per-dispatch upload overhead, batching recovers it -> bench_stream 100%).
  Slow Kingston 0.69 GB/s under load.
- AGGREGATE TPS (measured, block-64 P3, full model 870GB/step): fast NVMe B=512 2.4-2.5 /
  B=1024 4.7-5.0 ; interactive B=1 (active 6/384, ~14GB/tok) 0.37. With scale-fix (653GB)
  x1.33 -> ~3.2 / ~6.3 / ~0.49.
- SYSTEMS FINDING: the P3 always-active core is 17.6GB > 16GB RAM -> can't be fully resident
  at P3; the scale-fix (block-256 ~13GB) or Lloyd core is REQUIRED for the resident tier to
  fit, not optional. Disk-bound confirmed; per-dispatch overhead must be amortized (batch
  uploads). This is the MAX the memory hierarchy allows for full-intelligence streaming on
  16GB; more needs the bank in fast memory (hardware), not software.

## ENGINE OVERLAP CONFIRMED FULL + batched-path note (2026-06-15, stream_engine)
Tried the batched-upload optimization (offer a). Result: the stable g.dispatch path (persistent
VRAM buffers, alloc-once) already overlaps FULLY -- fast SN850X 5.27 GB/s under GPU load (>= the
5.0 solo; earlier 4.0-4.3 was cold-cache variance). Final measured engine: B=512 -> 3.1 tps,
B=1024 -> 6.2 tps (block-64 P3); scale-fix block-256 -> ~4.1 / ~8.2. Correctness 1.000000.
The batched-RESIDENT GEMM path (benchResidentGEMM in a loop) is UNSTABLE -- it alloc/frees VRAM
buffers per call -> GPU context-loss at B>=512, and slower. Not needed (dispatch already full
overlap); a true batched path needs persistent reused buffers. gpu.zig: RESIDENT_GEN flag added
to skip CPU weight-gen. NEXT real win = scale-fix block-256 forge (1.33x + makes the 17.6GB core
fit 16GB RAM).
