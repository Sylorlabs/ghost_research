# U1: per-token channel sparsity in routed experts.
# Question: of each expert's 3072 swiglu channels, how few carry the output
# energy per token? Decides the contextual-sparsity lever (fetch/compute only
# hot rows).
#
# Uses calib_acts.bin (records: layer u32, tok u32, 7168 f32 — post-ffn_norm
# expert inputs captured from the real E4 stack run, layers {5,30,50}) and
# real fp4 experts from the checkpoint. Swiglu per moe_stack.zig:
#   g = min(gate, 10); v = clamp(up, -10, 10); h = silu(g) * v
import numpy as np, json, struct, os, sys

WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro", "/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4 = np.array([0, .5, 1, 1.5, 2, 3, 4, 6, -0, -.5, -1, -1.5, -2, -3, -4, -6], dtype=np.float32)
N_EXPERTS_PROBED = 8
out = open("u1_results.txt", "w")

def log(s):
    print(s); out.write(s + "\n"); out.flush()

def load_shard_header(path):
    with open(path, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        hdr = json.loads(f.read(n))
    return hdr, 8 + n

def load_tensor(path, hdr, base, name):
    t = hdr[name]
    off0, off1 = t["data_offsets"]
    with open(path, "rb") as f:
        f.seek(base + off0)
        raw = f.read(off1 - off0)
    return np.frombuffer(raw, dtype=np.uint8).reshape(t["shape"])

def dequant_fp4(w_u8, s_u8):
    rows, bcols = w_u8.shape
    w = np.empty((rows, bcols * 2), dtype=np.float32)
    w[:, 0::2] = FP4[w_u8 & 15]
    w[:, 1::2] = FP4[w_u8 >> 4]
    scale = np.exp2(s_u8.astype(np.float32) - 127.0)
    return w * np.repeat(scale, 32, axis=1)

# --- load real activations ---
acts = {}  # layer -> [n,7168]
rec = 4 + 4 + 7168 * 4
raw = open("calib_acts.bin", "rb").read()
for i in range(len(raw) // rec):
    chunk = raw[i * rec:(i + 1) * rec]
    layer = struct.unpack("<I", chunk[:4])[0]
    x = np.frombuffer(chunk[8:], dtype=np.float32)
    acts.setdefault(layer, []).append(x)
acts = {l: np.stack(v) for l, v in acts.items()}
log(f"activations: {{l: a.shape[0] for l, a in acts.items()}} -> " + str({l: a.shape[0] for l, a in acts.items()}))

def silu(x):
    return x / (1.0 + np.exp(-x))

for layer, X in sorted(acts.items()):
    path = f"{WD}/model-{layer + 2:05d}-of-00064.safetensors"
    hdr, base = load_shard_header(path)
    frac_needed = {0.5: [], 0.9: [], 0.95: [], 0.99: []}
    top_sets = []
    for e in range(N_EXPERTS_PROBED):
        w1 = dequant_fp4(load_tensor(path, hdr, base, f"layers.{layer}.ffn.experts.{e}.w1.weight"),
                         load_tensor(path, hdr, base, f"layers.{layer}.ffn.experts.{e}.w1.scale"))
        w3 = dequant_fp4(load_tensor(path, hdr, base, f"layers.{layer}.ffn.experts.{e}.w3.weight"),
                         load_tensor(path, hdr, base, f"layers.{layer}.ffn.experts.{e}.w3.scale"))
        G = np.minimum(X @ w1.T, 10.0)
        V = np.clip(X @ w3.T, -10.0, 10.0)
        H = silu(G) * V  # [n, 3072]
        E = H * H
        E /= E.sum(axis=1, keepdims=True) + 1e-30
        srt = np.sort(E, axis=1)[:, ::-1]
        cum = np.cumsum(srt, axis=1)
        for q in frac_needed:
            frac_needed[q].append((cum < q).sum(axis=1) + 1)
        # top-10% channel set per token (for overlap stats)
        k10 = 307
        idx = np.argpartition(E, -k10, axis=1)[:, -k10:]
        top_sets.append(idx)
    log(f"\n=== layer {layer} ({X.shape[0]} real tokens x {N_EXPERTS_PROBED} experts) ===")
    for q, v in frac_needed.items():
        v = np.concatenate(v)
        log(f"  channels for {int(q*100)}% energy: mean {v.mean():7.1f} / median {np.median(v):6.0f} / p90 {np.percentile(v, 90):6.0f}  (of 3072)")
    # cross-token overlap of top-10% sets within an expert
    ovl = []
    for sets in top_sets:
        n = sets.shape[0]
        for _ in range(200):
            i, j = np.random.randint(0, n, 2)
            if i != j:
                ovl.append(len(np.intersect1d(sets[i], sets[j])) / 307.0)
    log(f"  top-10% set overlap between random token pairs: mean {np.mean(ovl):.3f}")
    # union growth: how many channels would static pruning need to keep?
    uni = []
    for sets in top_sets:
        u = set()
        for r in sets:
            u.update(r.tolist())
        uni.append(len(u))
    log(f"  union of top-10% sets over all tokens: mean {np.mean(uni):7.0f} / 3072 (static-prune ceiling)")
out.close()
print("U1 DONE")
