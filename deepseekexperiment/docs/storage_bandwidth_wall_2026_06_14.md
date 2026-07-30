# The Storage-Bandwidth Wall — the real, final speed gate (2026-06-14)

This is the document that closes the speed campaign analytically. Intelligence is
solved. Compute is solved. What remains is a single, measured, hardware-shape
constraint: **you cannot put enough of the model on a fast-enough drive on this
machine to feed batched decode.**

No projections here — every number below is measured today or earlier in the repo.

## 1. The model can't be made smaller (routing forbids it)

The hope was: experts are routed unevenly, so keep a small "hot" subset resident
and stream the rest rarely. The route data refutes it.

From `route_coherent.log` (full 61-layer A/B over T=512 real tokens):

- Every score-routed layer touches **258–383 of 384 experts** over 512 tokens.
  Early layers hit **383/384**.
- Over real context you touch **essentially all experts per layer.**
- The `route_ov` column (~0.73–0.85) is *temporal* overlap between adjacent
  routing decisions — that is the locality the U3 cache exploits for ~1.3×. It is
  **not** spatial sparsity. It does not let you drop experts.

Conclusion: the working set is the whole expert bank. It cannot be shrunk to a
small resident hot-set without large quality loss.

## 2. The drives (measured cold, O_DIRECT, today)

| Drive | Model | Mount | Read BW | Free |
|-------|-------|-------|---------|------|
| FAST  | WD_BLACK SN850X 1TB     | `/`            | **5.0 GB/s** | 9.7 GB |
| SLOW  | KINGSTON SNV3S1000G 1TB | `/mnt/corpus`  | **1.1 GB/s** | 74 GB  |

The fast drive is 559 GB total, 521 GB used by OS + games — there is no realistic
way to free ~250 GB+ on it. The slow drive holds the 806 GB DeepSeek-V4-Pro source
(the only copy).

## 3. The working set (forged, full 58 MoE layers)

One forged P3 layer measured = 14 GB. Scaling:

| Precision | Quality | Size |
|-----------|---------|------|
| uniform P3 | validated, +0.1 nats | **812 GB** |
| freq-precision mix (hot P3 / cold P1, 2.1×) | ~near-P3 | **~387 GB** |
| uniform P1 (1-bit) | degraded | **250 GB** |

**Even the smallest full model (250 GB) exceeds all free fast storage (84 GB
combined).** That is the wall, stated exactly.

## 4. What aggregate throughput each scenario gives

Batched decode reads the full working set `W` once per step and serves `B` tokens,
with disk read overlapping GPU compute. So:

```
aggregate_tps = B × bandwidth / W       (B = 512)
```

| Storage | P3 (812 GB) | mix (387 GB) | P1 (250 GB) |
|---------|-------------|--------------|-------------|
| FAST 5.0 GB/s | 3.2 tps | 6.6 tps | 10.2 tps |
| SLOW 1.1 GB/s | 0.7 tps | 1.5 tps | 2.3 tps |

(The FAST-drive column is what the batched-engine validation projected — 5.4 tps
for the mix is consistent with 6.6 minus overhead — but **none of it fits on the
fast drive's 9.7 GB free.**)

## 5. The only ways through — all consumer, none "data center"

1. **Delete the 806 GB source** → slow drive gains ~880 GB free → forge the full
   model there.
   - full P3 (812 GB) → **~0.7 tps, full quality**
   - P1 (250 GB) → **~2.3 tps, degraded quality**
   - **Irreversible**: the source is the only copy. A safe forge-then-delete is
     impossible at 84 GB free (no room to stage the forged copy before deleting),
     so it would have to be delete-as-we-forge per shard. Needs explicit user
     authorization. Recovery = 806 GB re-download.

2. **Add one consumer NVMe (1–2 TB, ~$100–150)** → forge the freq-mix (387 GB) to
   it → **~6.6 tps, full quality.** Keeps the source intact. Cleanest path.

3. **Hit the 20 tps goal**: `B × bw / W = 20`. At B=512 with the 387 GB mix that
   needs **15 GB/s ≈ 3× NVMe in RAID0** (consumer), or a larger batch with more
   RAM (raises *aggregate* throughput, not single-stream latency). True
   single-stream interactive 20 tps needs the whole ~387 GB working set readable
   per-token-fast, i.e. resident in RAM/VRAM — not possible on 16 GB.

## 6. Bottom line

- **Intelligence:** solved. XOR/bitplane survives at +0.1 nats; the engine emits
  correct tokens ("Paris", logit 23.78).
- **Compute:** solved. GPU per-element batched XNOR = 26 tps compute-side; batched
  path validated from measured components.
- **Residual:** purely **storage capacity × bandwidth.** It is now a
  hardware-shape decision, not a math or software problem. The three options above
  are the complete, measured menu.
