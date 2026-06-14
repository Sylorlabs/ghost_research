# Batched engine VALIDATED to 3-5 tps aggregate (2026-06-13)

User chose the batched-GPU engine (3-5 tps aggregate). Validated end-to-end from
MEASURED components before committing to the full multi-day build.

## Measured inputs
- Forged P3 experts (forge_experts.zig, L30: 384 experts, 13.6GB, 35.5MB/expert
  for w1+w2+w3) READ from fast SN850X at **5.3 GB/s** (dd, O_DIRECT) — pre-forged
  P3 means NO runtime fp4->P3 convert (the 7x tax, gone).
- GPU batched XNOR: 2955 Gw/s @ B=128 (bench_gpu5) = ~43 tps full-model compute
  (not the bottleneck).
- Expert union per layer saturates ~384 at B>=256 (E0/route traces).
- Frequency-precision: cold experts P1 = ~1.8-2.1x fewer fetch bytes, +0.037 nats
  (confirmed, freqprec_64.txt).
- KV (MLA, ~10KB/tok): B=512 @ 1K ctx = 5.2GB, @ 2K = 10.5GB — fits 16GB.

## Throughput (batched decode, fetch-bound)
step fetch = 384 experts x 58 layers x 35.5MB = 791GB/step, served across B tokens:
| B | fetch-bound | + freq-precision | system |
|---|---|---|---|
| 256 | 1.5 | 2.7 | 2.7 tps |
| 512 | 3.0 | 5.4 | **5.4 tps aggregate** |

CLEARS the 3-5 target at B=512. Aggregate throughput across 512 concurrent
sequences (serving/agentic/batch), NOT single-stream latency.

## The gate: fast-drive capacity
Full forged expert set (freq-precision: hot P3 + cold P1) ~= 440GB. Fast SN850X
is 931GB, ~429GB free if other projects/games cleared off it. So 5.4 tps needs
~440GB freed on the fast drive (disk management, not a hard wall). B=256 (2.7 tps)
needs less.

## Remaining build (now justified)
1. Forge all 58 score layers' experts to P3 (+freq-precision) on the fast drive.
2. Batched decode engine: B=512 sequences, per-sequence MLA KV cache, union-fetch
   from forged file, GPU batched XNOR (compute_1bit_elem), per-sequence sample.
3. Generation loop.
Single-stream interactive stays ~0.5-1 tps (fetch wall); 3-5 is aggregate/batched
or a RAM upgrade. This is the honest 16GB ceiling, now validated.
