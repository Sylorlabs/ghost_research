#!/usr/bin/env python3
"""E10b: tps projection from MEASURED numbers (E7 hit rates, E8 kernels, E10a I/O).

Architecture priced here:
  - shared experts (61, always active): P3-converted, pinned in RAM
  - hash layers 0-2: routing known from token id => prefetched during the
    previous token's compute (zero stall if fetch < compute time)
  - score layers 3-60: 6 routed experts each; RAM LRU cache (P3 form), miss =>
    fetch from ext4 P3 store (if converted) or NTFS fp4 + convert
  - attention + everything else: ~3GB at P3/f32, RAM-resident
"""

# --- measured inputs ---
XNOR_GWPS_1T = 10.7e9       # E8 kernel C, single thread
THREADS_EFF = 8.0            # of 12 cores (parallel GEMV efficiency, conservative)
NTFS_MBPS = 1079.0           # E10a
EXT4_MBPS = 2183.0           # E10a
CONVERT_S = 0.095 * 3        # E8: fp4->P3 per expert (3 matrices)
EXPERT_W = 3 * 3072 * 7168   # weights per expert
EXPERT_P3_MB = EXPERT_W * 3.25 / 8 / 2**20   # 3 planes + u8 scales
EXPERT_FP4_MB = EXPERT_W * 4.25 / 8 / 2**20

N_SCORE = 58
N_HASH = 3
TOPK = 6

# E7 measured LRU hit rates (hash layers, real text, per-layer cap -> rate)
# used as proxy for score layers (caveat: score-layer temporal locality
# unmeasured; hash-layer Zipf locality is the best available estimate)
LRU_PTS = [(0, 0.0), (32, 0.16), (64, 0.33), (128, 0.59), (192, 0.75),
           (256, 0.86), (384, 0.997)]

def lru_hit(cap):
    for (c0, h0), (c1, h1) in zip(LRU_PTS, LRU_PTS[1:]):
        if cap <= c1:
            return h0 + (h1 - h0) * (cap - c0) / (c1 - c0)
    return LRU_PTS[-1][1]

def project(ram_cache_gb, store):
    # per-layer expert cache capacity (score layers share the budget)
    cap_experts = int(ram_cache_gb * 1024 / EXPERT_P3_MB / N_SCORE)
    snap = cap_experts
    hit = lru_hit(cap_experts)

    # compute: 7 experts x 61 layers of XNOR + attention (~10% extra)
    w_per_tok = EXPERT_W * (TOPK + 1) * (N_SCORE + N_HASH)
    t_compute = w_per_tok / (XNOR_GWPS_1T * THREADS_EFF) * 1.10

    # fetch: score-layer misses only (hash prefetched, shared pinned)
    misses = N_SCORE * TOPK * (1 - hit)
    if store == "ext4_p3":
        t_fetch = misses * EXPERT_P3_MB / EXT4_MBPS
    else:  # NTFS fp4 + on-the-fly conversion (conversion overlaps with I/O partly)
        t_fetch = misses * (EXPERT_FP4_MB / NTFS_MBPS + CONVERT_S * 0.5)

    t = t_compute + t_fetch
    return cap_experts, snap, hit, t_compute, t_fetch, 1 / t

print(f"expert sizes: P3={EXPERT_P3_MB:.1f}MB fp4={EXPERT_FP4_MB:.1f}MB; "
      f"shared experts pinned: {61*EXPERT_P3_MB/1024:.1f}GB ... too big for 16GB RAM!")
print(f"=> price shared experts as always-RAM only if cache budget >= 1.6GB+\n")

print(f"{'RAM cache':>10} {'store':>8} {'cap/layer':>9} {'hit':>5} "
      f"{'compute':>8} {'fetch':>7} {'tps':>6}")
for store in ("ext4_p3", "ntfs_fp4"):
    for gb in (4, 8, 12, 24, 48, 96):
        cap, snap, hit, tc, tf, tps = project(gb, store)
        print(f"{gb:>8}GB {store:>8} {cap:>9} {hit:>5.2f} {tc*1e3:>6.0f}ms "
              f"{tf*1e3:>6.0f}ms {tps:>6.2f}")

print("""
notes:
- 16GB machine: realistic RAM cache budget ~6-8GB after shared experts pinned
  (1.6GB) + attention/gates/OS => the 4-8GB rows are this machine.
- ext4_p3 store requires ~300GB converted store; currently no drive fits the
  full set; a partial store (hot experts) interpolates between rows.
- score-layer hit rates are extrapolated from hash-layer Zipf locality; true
  sequential-text score routing needs the attention port (future work).
- RAM upgrade (e.g. 64-96GB) moves cache on-die: 192-384 experts/layer cached
  => 0.75-1.0 hit rate => 1-3 tps territory on this CPU.""")
