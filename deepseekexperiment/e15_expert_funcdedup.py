# E15: whole-expert FUNCTIONAL dedup on the realized input distribution.
# U2/B8/B5 proved experts are WEIGHT-space incompressible. Never tested:
# do two experts with orthogonal row-spaces compute the SAME function on the
# ~hundreds of inputs that actually occur? If >25% of experts are functional
# near-copies, effective cache occupancy rises for free, and U3 gets a
# substitution-neighbor table. Prior says it dies (<10%) because the router
# is trained to AVOID routing near-duplicates — but it's a 5-min test.
#
# Method: GEMV N real post-ffn_norm activations through each expert's full
# swiglu forward; flatten+normalize each expert's output; 384x384 cosine.
import numpy as np, json, struct, os, time
WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4 = np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L = 30
N_IN = 96          # real activation vectors (memory-bounded)
N_EXPERTS = 384
out = open("e15_results.txt","w")
def log(s): print(s); out.write(s+"\n"); out.flush()

# real inputs (post-ffn_norm); take a spread across the corpus
rec = 8 + 7168*4
raw = open("acts_combined.bin","rb").read()
ntot = len(raw)//rec
idx = np.linspace(0, ntot-1, N_IN).astype(int)
X = np.stack([np.frombuffer(raw[i*rec+8:(i+1)*rec], dtype=np.float32) for i in idx])  # [N_IN,7168]
log(f"E15 functional dedup: layer {L}, {N_IN} real inputs, {N_EXPERTS} experts")

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
OUT = np.empty((N_EXPERTS, N_IN*7168), dtype=np.float32)
for e in range(N_EXPERTS):
    w1 = deq(f"layers.{L}.ffn.experts.{e}.w1")  # [3072,7168]
    w3 = deq(f"layers.{L}.ffn.experts.{e}.w3")
    w2 = deq(f"layers.{L}.ffn.experts.{e}.w2")  # [7168,3072]
    g = np.minimum(X @ w1.T, 10.0)
    u = np.clip(X @ w3.T, -10.0, 10.0)
    h = silu(g) * u                              # [N_IN,3072]
    o = h @ w2.T                                 # [N_IN,7168]
    v = o.reshape(-1)
    OUT[e] = v / (np.linalg.norm(v) + 1e-30)
    if e % 64 == 0: log(f"  expert {e}  t={time.time()-t0:.0f}s")

C = OUT @ OUT.T                                   # [384,384] cosine
np.fill_diagonal(C, -1)
best = C.max(axis=1)                              # each expert's nearest functional sibling
log(f"\n=== functional sibling cosine distribution (layer {L}, {N_IN} real inputs) ===")
for thr in (0.99, 0.95, 0.90, 0.80, 0.70):
    frac = (best >= thr).mean()
    log(f"  experts with a sibling at cos >= {thr:.2f}: {100*frac:5.1f}%")
log(f"  mean nearest-sibling cos = {best.mean():.4f}  median = {np.median(best):.4f}  max = {best.max():.4f}")
# verdict
f25 = (best >= 0.95).mean()
log(f"\nVERDICT: {'LONG-SHOT HIT — >25% near-duplicate, dedup viable' if f25>0.25 else ('PARTIAL — '+f'{100*f25:.0f}%'+' siblings, feeds U3 substitution table' if f25>0.10 else 'DEAD as predicted — experts functionally distinct; consolation = U3 neighbor table')}")
np.save("e15_func_cosine_L30.npy", C)
out.close(); print("E15 DONE")
