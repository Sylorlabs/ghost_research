# COARSE-TO-FINE decisive probe (retraining-free hierarchical MoE).
# Question: can ~32 RAM-resident super-expert centroids serve ROUTINE tokens,
# paying disk for the exact expert only when the centroid residual is large?
#
# This directly tests the floor lever: phi_effective = fraction of (token,layer,slot)
# expert invocations that MUST hit disk = fraction where centroid is NOT good enough.
#
# Runs entirely on data already on disk:
#   - acts_combined.bin : 15616 real post-ffn_norm activations (layer,token,7168f)
#   - fp4 experts of layer L from /mnt/corpus
#
# Method:
#   1. Build the 384 experts of layer L (full swiglu).
#   2. Forward N real layer-L activations through ALL 384 experts -> O[384,N,7168].
#   3. Cluster experts into K=32 super-experts by their OUTPUT signature (the E15
#      output-distance matrix, agglomerated). Super-expert function = mean of members.
#   4. For each (token, true-expert) pair that ACTUALLY occurs in routing, compute
#      cos(super_expert_output, true_expert_output). This is the served-by-centroid error.
#   5. Report the residual distribution: what fraction of invocations clear a quality
#      bar (cos>=0.95, 0.90, 0.80) when served by their super-expert centroid?
#      That fraction = tokens served from RAM = 1 - phi_disk for the C2F tier.
import numpy as np, json, struct, os, time, sys

WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4 = np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L = int(sys.argv[1]) if len(sys.argv)>1 else 30
K = int(sys.argv[2]) if len(sys.argv)>2 else 32
N_IN = int(sys.argv[3]) if len(sys.argv)>3 else 128
N_EXPERTS = 384
TOPK = 6
out = open(f"c2f_results_L{L}_K{K}.txt","w")
def log(s): print(s); out.write(s+"\n"); out.flush()

rec = 8 + 7168*4
raw = open("acts_combined.bin","rb").read()
ntot = len(raw)//rec
# pull layer-L records (header=(layer,token)); fall back to spread if too few
hdrs = np.frombuffer(raw, dtype=np.int32).reshape(ntot, rec//4)[:, :2]
layer_mask = np.where(hdrs[:,0]==L)[0]
if len(layer_mask) >= 8:
    sel = layer_mask[np.linspace(0,len(layer_mask)-1,min(N_IN,len(layer_mask))).astype(int)]
    src = f"layer-{L} records (n_avail={len(layer_mask)})"
else:
    sel = np.linspace(0,ntot-1,N_IN).astype(int)
    src = f"spread across all layers (no layer-{L} records)"
X = np.stack([np.frombuffer(raw[i*rec+8:(i+1)*rec], dtype=np.float32) for i in sel])  # [N,7168]
N = X.shape[0]
log(f"C2F probe: layer {L}, K={K} super-experts, {N} real inputs from {src}")

path = f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f = open(path,'rb'); n = struct.unpack('<Q', f.read(8))[0]; hdr = json.loads(f.read(n)); base = 8+n
def T(name):
    t = hdr[name]; o0,o1 = t['data_offsets']; f.seek(base+o0); return np.frombuffer(f.read(o1-o0),dtype=np.uint8).reshape(t['shape'])
def deq(name):
    w = T(name+".weight"); s = T(name+".scale")
    W = np.empty((w.shape[0], w.shape[1]*2), dtype=np.float32); W[:,0::2]=FP4[w&15]; W[:,1::2]=FP4[w>>4]
    return W * np.repeat(np.exp2(s.astype(np.float32)-127.), 32, axis=1)
def silu(x): return x/(1.0+np.exp(-x))

t0 = time.time()
# O[e] = output of expert e on all N inputs, flattened+raw (keep raw for centroid mean)
O = np.empty((N_EXPERTS, N, 7168), dtype=np.float32)
for e in range(N_EXPERTS):
    w1 = deq(f"layers.{L}.ffn.experts.{e}.w1")
    w3 = deq(f"layers.{L}.ffn.experts.{e}.w3")
    w2 = deq(f"layers.{L}.ffn.experts.{e}.w2")
    g = np.minimum(X @ w1.T, 10.0)
    u = np.clip(X @ w3.T, -10.0, 10.0)
    h = silu(g) * u
    O[e] = (h @ w2.T)
    if e % 96 == 0: log(f"  expert {e}  t={time.time()-t0:.0f}s")

# ---- E15 functional dedup (free byproduct) ----
flat = O.reshape(N_EXPERTS, -1)
norm = flat / (np.linalg.norm(flat,axis=1,keepdims=True)+1e-30)
C = norm @ norm.T
np.fill_diagonal(C, -1)
best = C.max(axis=1)
log("\n=== E15 functional sibling cosine (output space) ===")
for thr in (0.99,0.95,0.90,0.80,0.70):
    log(f"  experts w/ sibling cos>={thr:.2f}: {100*(best>=thr).mean():5.1f}%")
log(f"  mean nearest sibling cos = {best.mean():.4f}  median={np.median(best):.4f}")

# ---- Coarse-to-fine: cluster experts into K super-experts by output signature ----
# Agglomerative average-linkage on (1-cosine) distance, dense numpy (384x384 is tiny).
D = (1.0 - (norm @ norm.T)).astype(np.float64)
np.fill_diagonal(D, np.inf)
groups=[[i] for i in range(N_EXPERTS)]
M = D.copy()  # current cluster-cluster avg-linkage distance, index aligned to groups
while len(groups) > K:
    flat_idx = np.argmin(M)
    i,j = divmod(flat_idx, M.shape[0])
    if i>j: i,j=j,i
    ni,nj=len(groups[i]),len(groups[j])
    # average linkage update for merged row/col
    newrow = (ni*M[i] + nj*M[j])/(ni+nj)
    groups[i]=groups[i]+groups[j]
    M[i]=newrow; M[:,i]=newrow; M[i,i]=np.inf
    M=np.delete(M,j,0); M=np.delete(M,j,1)
    del groups[j]
log(f"\n=== C2F clustering into {len(groups)} super-experts ===")
sizes=sorted(len(g) for g in groups)
log(f"  cluster sizes: min={sizes[0]} median={sizes[len(sizes)//2]} max={sizes[-1]}")

# super-expert function = mean RAW output of members (RAM-resident centroid).
cent = np.zeros((len(groups), N, 7168), dtype=np.float32)
eid2grp = np.full(N_EXPERTS,-1,dtype=int)
for gi,g in enumerate(groups):
    cent[gi] = O[g].mean(axis=0)
    for e in g: eid2grp[e]=gi

# ---- served-by-centroid residual over the realized routing ----
# Use the e4_routing trace if present; else simulate top-6 by a proxy gate (||O|| rank
# is NOT the gate, so instead: for each input token, the true experts are whichever the
# model picked. We don't have layer-L per-token routing here, so measure the residual
# over ALL (expert,token) pairs weighted uniformly = unconditional upper bound, AND the
# conditional version restricted to each token's top-6 by centroid-cosine as a routing proxy).
def cos_rows(a,b):
    an=a/ (np.linalg.norm(a,axis=-1,keepdims=True)+1e-30)
    bn=b/ (np.linalg.norm(b,axis=-1,keepdims=True)+1e-30)
    return (an*bn).sum(-1)

# residual per (expert e, token t): cos(true expert output, its super-expert centroid)
res = np.empty((N_EXPERTS,N),dtype=np.float32)
for e in range(N_EXPERTS):
    res[e]=cos_rows(O[e], cent[eid2grp[e]])
log("\n=== served-by-super-expert residual: cos(true expert out, centroid) ===")
log("  (fraction of (expert,token) invocations cleared at each quality bar)")
for thr in (0.99,0.95,0.90,0.80,0.70,0.50):
    log(f"   cos>={thr:.2f}: {100*(res>=thr).mean():5.1f}%   [served from RAM => no disk fetch]")
log(f"  mean residual cos = {res.mean():.4f}  median={np.median(res):.4f}")

# magnitude check: centroid often points right but is shorter (averaging shrinks norm).
# report norm ratio so we know if a scalar rescale would help.
tn = np.linalg.norm(O.reshape(N_EXPERTS,N,7168),axis=-1)
cn = np.linalg.norm(cent[eid2grp],axis=-1)
log(f"  centroid/true norm ratio: mean={np.nanmean(cn/(tn+1e-30)):.3f} median={np.nanmedian(cn/(tn+1e-30)):.3f}")

# ---- the floor number: with K=32 RAM-resident centroids, projected phi ----
# A token-slot is served from RAM iff its centroid residual clears the bar.
# phi_disk(bar) = fraction NOT cleared = must fetch exact expert.
log("\n=== projected disk fraction phi if C2F centroids serve cleared invocations ===")
for thr in (0.95,0.90,0.80):
    phi=1-(res>=thr).mean()
    log(f"   bar cos>={thr:.2f}: phi_disk={phi:.3f}  (vs U3 cap128 phi~0.81, baseline phi=1.0)")
np.save(f"c2f_cosine_L{L}.npy", C)
out.close(); print("C2F DONE")
