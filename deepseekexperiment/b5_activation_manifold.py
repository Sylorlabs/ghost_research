# B5: activation-manifold compression. Experts compute W.x; if real x
# concentrates in a k-dim subspace B, store W.B (k/7168 of original bytes)
# regardless of W's own (measured: flat) spectrum.
# Data: calib_acts.bin = 8 tokens x 61 layers of post-ffn_norm expert inputs.
import numpy as np, struct
rec = 8 + 7168*4
import sys
src = sys.argv[1] if len(sys.argv) > 1 else 'calib_acts.bin'
out_name = sys.argv[2] if len(sys.argv) > 2 else 'b5_results.txt'
raw = open(src,'rb').read()
X = []
for i in range(len(raw)//rec):
    X.append(np.frombuffer(raw[i*rec+8:(i+1)*rec], dtype=np.float32))
X = np.stack(X)  # [488, 7168]
out = open(out_name,'w')
def log(s): print(s); out.write(s+"\n"); out.flush()
log(f"activation matrix: {X.shape}")
# global PCA (all layers pooled) and per-layer-band: energy capture vs k
Xc = X - X.mean(0)
U,S,Vt = np.linalg.svd(Xc, full_matrices=False)
en = np.cumsum(S**2)/np.sum(S**2)
log("pooled activation spectrum (488 samples cap rank at 488):")
for k in (16,32,64,128,256,512,1024,2048,4000):
    if k >= len(X): break
    log(f"  top-{k:4d}: {100*en[k-1]:6.2f}% energy")
# leave-one-out generalization: project held-out vectors on basis from rest
rng = np.random.default_rng(0)
idx = rng.permutation(len(X)); ntr = int(len(X)*0.85); tr, te = idx[:ntr], idx[ntr:]
mu = X[tr].mean(0)
_,S2,V2 = np.linalg.svd(X[tr]-mu, full_matrices=False)
for k in (64,128,256,512,1024,2048,min(4000,ntr-1)):
    B = V2[:k]
    R = (X[te]-mu) - ((X[te]-mu) @ B.T) @ B
    cap = 1 - (R**2).sum()/((X[te]-mu)**2).sum()
    log(f"held-out capture top-{k:4d}: {100*cap:6.2f}%  -> compression x{7168/k:.0f}, residual rel-err {np.sqrt(max(1-cap,0)):.3f}")
out.close(); print("B5 DONE")
