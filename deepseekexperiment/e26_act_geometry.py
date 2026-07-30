#!/usr/bin/env python3
# E26: dissect the "meaning between vectors" (Micah's principle, 2026-06-14).
# Weights are iid-gaussian noise (incompressible). But the MEANING is relational:
# it lives in how the ACTIVATION vectors relate as data flows. If related tokens
# produce related hidden states, their expert computation is REUSABLE -> a cache
# hit skips both fetch and compute (order-of-magnitude lever, not weight compression).
#
# Reads ACT_DUMP (post-ffn-norm MoE-input vectors): records [layer:u32, tok:u32, 7168 f32].
# Per layer measures:
#   - NN cosine: max cos to ANY other token  (reuse ceiling)
#   - causal NN: max cos to a PAST token     (deployable cache hit)
#   - intrinsic dim: PCA comps for 90% energy (is the meaning low-dim here?)
#   - mean pairwise cos (anisotropy baseline)
import numpy as np, sys, struct, collections

DIM = 7168
path = sys.argv[1] if len(sys.argv) > 1 else "acts_T128.bin"
raw = open(path, "rb").read()
rec = 8 + DIM * 4
n = len(raw) // rec
print(f"records: {n}  ({len(raw)} bytes, rec={rec})")
by_layer = collections.defaultdict(list)
order = collections.defaultdict(list)
off = 0
for _ in range(n):
    l, t = struct.unpack_from("<II", raw, off)
    v = np.frombuffer(raw, dtype="<f4", count=DIM, offset=off + 8)
    by_layer[l].append(v.astype(np.float32))
    order[l].append(t)
    off += rec

def stats(V, toks):
    # V: [ntok, DIM]
    X = V / (np.linalg.norm(V, axis=1, keepdims=True) + 1e-9)
    C = X @ X.T                      # cosine matrix
    np.fill_diagonal(C, -2)
    nn = C.max(axis=1)              # best match to any other token
    # causal: only past tokens (by token id order)
    o = np.argsort(toks)
    Xc = X[o]
    Cc = Xc @ Xc.T
    causal = np.full(len(o), -2.0)
    for i in range(1, len(o)):
        causal[i] = Cc[i, :i].max()
    causal = causal[1:]
    # intrinsic dim via PCA (center)
    Xc2 = V - V.mean(0)
    s = np.linalg.svd(Xc2, compute_uv=False)
    e = (s * s)
    cum = np.cumsum(e) / e.sum()
    dim90 = int(np.searchsorted(cum, 0.90) + 1)
    mean_off = C[C > -1.5].mean()
    return nn, causal, dim90, mean_off

layers = sorted(by_layer)
print(f"\n{'layer':>5} | {'meanCos':>7} | {'NN>.95':>7} {'NN>.90':>7} | {'caus>.95':>8} {'caus>.90':>8} | {'dim90':>6} | {'NNmean':>7}")
agg = []
for l in layers:
    V = np.stack(by_layer[l]); toks = np.array(order[l])
    nn, causal, dim90, mean_off = stats(V, toks)
    f_nn95 = (nn > 0.95).mean(); f_nn90 = (nn > 0.90).mean()
    f_c95 = (causal > 0.95).mean(); f_c90 = (causal > 0.90).mean()
    print(f"{l:>5} | {mean_off:>7.3f} | {f_nn95:>7.2f} {f_nn90:>7.2f} | {f_c95:>8.2f} {f_c90:>8.2f} | {dim90:>6} | {nn.mean():>7.3f}")
    agg.append((f_c90, f_c95, dim90, nn.mean(), V.shape[0]))
A = np.array([a[:4] for a in agg])
print(f"\nMEAN over layers: causal-hit>.90 = {A[:,0].mean():.2f}  >.95 = {A[:,1].mean():.2f}  "
      f"dim90 = {A[:,2].mean():.0f}/{DIM}  NNmean = {A[:,3].mean():.3f}")
print(f"tokens/layer = {agg[0][4]}")
print("\nREAD: high causal-hit => computation reuse viable (skip fetch+compute for repeat-ish tokens).")
print("low dim90 at some layers => meaning is low-dim there => layer-specific surrogate possible.")
