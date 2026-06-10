#!/usr/bin/env python3
"""E10a: measured I/O throughput for expert-sized reads on both drives.

- NTFS (steamgames, where the 806GB weights live): random 33MB expert reads
  spread over many shards — far exceeds RAM, so page cache cannot help.
- ext4 root NVMe (where converted bitplanes would live): random 25MB reads
  from the 79GB distilled_core directory (mostly uncached for the same reason).
Reports MB/s and per-expert fetch latency.
"""
import os, time, random, glob

def bench_random_reads(paths, read_size, n_reads, label):
    files = []
    total = 0
    for p in paths:
        sz = os.path.getsize(p)
        if sz > read_size * 2:
            files.append((p, sz))
            total += sz
    random.seed(11)
    lat = []
    t0 = time.time()
    done = 0
    for _ in range(n_reads):
        p, sz = random.choice(files)
        off = random.randrange(0, sz - read_size)
        off -= off % 4096
        t1 = time.time()
        with open(p, "rb") as f:
            f.seek(off)
            data = f.read(read_size)
        lat.append(time.time() - t1)
        done += len(data)
    dt = time.time() - t0
    lat.sort()
    print(f"{label}: {done/dt/1e6:.0f} MB/s aggregate | "
          f"per-{read_size//2**20}MB read p50={lat[len(lat)//2]*1e3:.0f}ms "
          f"p90={lat[int(len(lat)*0.9)]*1e3:.0f}ms | corpus {total/2**30:.0f}GiB")
    return done / dt

EXPERT_FP4 = 33 * 2**20      # one expert (w1+w2+w3) in fp4
EXPERT_P3 = 25 * 2**20       # one expert at 3 bitplanes + u8 scales

ntfs = bench_random_reads(
    glob.glob("/mnt/steamgames/DeepSeek-V4-Pro/model-*.safetensors"),
    EXPERT_FP4, 24, "NTFS source (fp4 expert reads)")

ext4_files = glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    "distilled_core/shard-*.bin"))
ext4 = bench_random_reads(ext4_files, EXPERT_P3, 24, "ext4 root (P3 expert reads)")

print(f"\nper-token fetch cost if NOTHING cached (58 score layers x 6 routed experts):")
print(f"  from NTFS fp4 : {58*6*EXPERT_FP4/ntfs:.1f} s/token")
print(f"  from ext4 P3  : {58*6*EXPERT_P3/ext4:.1f} s/token")
print("(shared experts + hash layers are pinned/prefetched; caching cuts the rest)")
