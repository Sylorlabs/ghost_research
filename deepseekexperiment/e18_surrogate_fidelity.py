# E18: can we REPLACE a DeepSeek expert with our OWN tiny module, fit (not
# retrained) to reproduce its function on ONE context's input manifold?
# Decisive test of "make our own experts". Fit on 96 tokens of context A,
# test fidelity on 32 HELD-OUT tokens of the same context (generalization to
# new tokens of the session). Sweep surrogate rank; report output cosine + bytes.
import numpy as np, json, struct, os, time
WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4 = np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L = 30
rec = 8 + 7168*4
out = open("e18_results.txt","w")
def log(s): print(s); out.write(s+"\n"); out.flush()

# context A inputs for layer L
raw = open("acts_T128_off8000.bin","rb").read()
a = np.frombuffer(raw, dtype=np.uint8).reshape(-1, rec)
lay = a[:, :4].view(np.uint32).reshape(-1)
X = a[lay==L][:, 8:].view(np.float32).reshape(-1, 7168).astype(np.float32)
ntok = len(X); ntr = 96
log(f"E18 surrogate fidelity: layer {L}, context A, {ntok} tokens ({ntr} fit / {ntok-ntr} held-out)")

path = f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f = open(path,'rb'); n = struct.unpack('<Q', f.read(8))[0]; hdr = json.loads(f.read(n)); base = 8+n
def T(name):
    t=hdr[name]; o0,o1=t['data_offsets']; f.seek(base+o0); return np.frombuffer(f.read(o1-o0),dtype=np.uint8).reshape(t['shape'])
def deq(name):
    w=T(name+".weight"); s=T(name+".scale")
    W=np.empty((w.shape[0], w.shape[1]*2),dtype=np.float32); W[:,0::2]=FP4[w&15]; W[:,1::2]=FP4[w>>4]
    return W*np.repeat(np.exp2(s.astype(np.float32)-127.),32,axis=1)
def silu(x): return x/(1.0+np.exp(-x))
def expert(X,e):
    W1=deq(f"layers.{L}.ffn.experts.{e}.w1"); W3=deq(f"layers.{L}.ffn.experts.{e}.w3"); W2=deq(f"layers.{L}.ffn.experts.{e}.w2")
    g=np.minimum(X@W1.T,10.0); u=np.clip(X@W3.T,-10.0,10.0); h=silu(g)*u; return h@W2.T

def cos(A,B):
    return float((A*B).sum()/(np.linalg.norm(A)*np.linalg.norm(B)+1e-30))

# SHARED input basis from the layer's context inputs (stored once/layer)
Xc = X - X.mean(0)
_,_,Vt = np.linalg.svd(Xc, full_matrices=False)

RANKS=[16,32,48,64,84]
experts=[0,50,150,300]
log("\nper-expert HELD-OUT output cosine (our surrogate vs the real expert), by surrogate rank:")
log(f"{'rank':>5} " + " ".join(f"e{e:>4}" for e in experts) + "   bytes/expert  WS@250x58")
# surrogate = linear map from r-dim shared-basis input coords -> 7168 output, fit by lstsq on train
mu = X.mean(0)
for r in RANKS:
    B = Vt[:r]                              # [r,7168] shared input basis (once/layer)
    Z = (X-mu) @ B.T                        # [ntok, r] coords
    Ztr = np.hstack([Z[:ntr], np.ones((ntr,1))]); Zte = np.hstack([Z[ntr:], np.ones((ntok-ntr,1))])
    row=[]
    for e in experts:
        Y = expert(X, e)                    # true [ntok,7168]
        M,_,_,_ = np.linalg.lstsq(Ztr, Y[:ntr], rcond=None)   # [r+1,7168] per-expert surrogate
        Yhat = Zte @ M
        row.append(cos(Y[ntr:], Yhat))
    per_expert_bytes = (r+1)*7168*4         # M per expert (B is shared/layer)
    ws = 250*58*per_expert_bytes/1e9
    log(f"{r:>5} " + " ".join(f"{c:.3f}" for c in row) + f"   {per_expert_bytes/1e6:.2f}MB      {ws:.0f}GB")

# reference: what does P3 (the current format) score on the same held-out outputs?
log("\nfor scale: P3 per-matmul cosine is ~0.98; an expert-level surrogate >0.95 held-out would be competitive.")
log("NOTE: linear surrogate is the FLOOR of what's achievable; a small nonlinear core (rank-r in, rank-r out, tiny MLP) would do better at similar size. This measures whether the LOCAL manifold is benign enough for cheap surrogates.")
out.close(); print("E18 DONE")
