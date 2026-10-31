# GHOST kill-or-confirm: per-expert rank-r linear surrogate + VQ residual table.
# Tests the ACTUAL claim: gate-weighted CONTRIBUTION reproduction on HELD-OUT tokens.
import numpy as np, json, struct, os, time
WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4 = np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L = 30
rec = 8 + 7168*4
raw = open("acts_combined.bin","rb").read()
ntot = len(raw)//rec
hdr = np.frombuffer(raw, dtype=np.int32).reshape(ntot, rec//4)[:, :2]
idx = np.where(hdr[:,0]==L)[0]
X = np.stack([np.frombuffer(raw[i*rec+8:(i+1)*rec], dtype=np.float32) for i in idx])  # [256,7168]
N = X.shape[0]
print(f"layer {L}: {N} real inputs")

path = f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f = open(path,'rb'); n = struct.unpack('<Q', f.read(8))[0]; hh = json.loads(f.read(n)); base = 8+n
def T(name):
    t = hh[name]; o0,o1 = t['data_offsets']; f.seek(base+o0); return np.frombuffer(f.read(o1-o0),dtype=np.uint8).reshape(t['shape'])
def deq(name):
    w = T(name+".weight"); s = T(name+".scale")
    W = np.empty((w.shape[0], w.shape[1]*2), dtype=np.float32); W[:,0::2]=FP4[w&15]; W[:,1::2]=FP4[w>>4]
    return W * np.repeat(np.exp2(s.astype(np.float32)-127.), 32, axis=1)
def silu(x): return x/(1.0+np.exp(-x))

def expert_fwd(e, Xin):
    w1=deq(f"layers.{L}.ffn.experts.{e}.w1"); w3=deq(f"layers.{L}.ffn.experts.{e}.w3"); w2=deq(f"layers.{L}.ffn.experts.{e}.w2")
    g=np.minimum(Xin@w1.T,10.0); u=np.clip(Xin@w3.T,-10.0,10.0); h=silu(g)*u; return h@w2.T  # [n,7168]

# pick experts: use a spread (GHOST says "most-reused"; we test general behavior)
np.random.seed(0)
experts = [5, 50, 120, 200, 300, 370]
# train/test split of the 256 inputs
perm = np.random.permutation(N); tr=perm[:N//2]; te=perm[N//2:]
Xtr, Xte = X[tr], X[te]

for r in (16, 32):
  print(f"\n===== rank r={r} surrogate + VQ residual (K=128) =====")
  cos_full=[]; cos_resid=[]
  for e in experts:
    Otr = expert_fwd(e, Xtr)   # ground truth contribution (pre-gate) [128,7168]
    Ote = expert_fwd(e, Xte)
    # build per-expert top-r input subspace from TRAIN inputs
    mu = Xtr.mean(0)
    Uu,Ss,Vt = np.linalg.svd(Xtr-mu, full_matrices=False)
    P = Vt[:r]                      # [r,7168] right singular dirs
    Ctr = (Xtr-mu)@P.T             # [128,r] codes
    Cte = (Xte-mu)@P.T
    # linear surrogate: least-squares map code->output (W_lin in low-rank form)
    # O ~= Ctr @ A   where A:[r,7168]
    A,_,_,_ = np.linalg.lstsq(Ctr, Otr, rcond=None)
    pred_lin_te = Cte@A
    # VQ residual on TRAIN: kmeans on Ctr codes, store mean residual per bucket
    K=min(128, len(tr))
    # simple kmeans
    cen = Ctr[np.random.choice(len(Ctr),K,replace=False)]
    for _ in range(15):
        d = ((Ctr[:,None,:]-cen[None,:,:])**2).sum(-1)
        asn = d.argmin(1)
        for k in range(K):
            m=asn==k
            if m.any(): cen[k]=Ctr[m].mean(0)
    resid_tr = Otr - (Ctr@A)
    table = np.zeros((K,7168),dtype=np.float32); cnt=np.zeros(K)
    for i,a in enumerate(asn): table[a]+=resid_tr[i]; cnt[a]+=1
    table[cnt>0]/=cnt[cnt>0,None]
    # apply to test: assign each test code to nearest train centroid
    dte=((Cte[:,None,:]-cen[None,:,:])**2).sum(-1); asn_te=dte.argmin(1)
    pred_full_te = pred_lin_te + table[asn_te]
    # cosine per test token (full output, ungated -- gate folds in as scalar so cosine unchanged)
    def rowcos(Pmat,Gmat):
        pn=Pmat/(np.linalg.norm(Pmat,axis=1,keepdims=True)+1e-30)
        gn=Gmat/(np.linalg.norm(Gmat,axis=1,keepdims=True)+1e-30)
        return (pn*gn).sum(1)
    cl=rowcos(pred_lin_te,Ote); cf=rowcos(pred_full_te,Ote)
    cos_full.append(cl.mean()); cos_resid.append(cf.mean())
    print(f"  expert {e:3d}: lin-only cos mean={cl.mean():.3f} p10={np.percentile(cl,10):.3f} | +VQresid cos mean={cf.mean():.3f} p10={np.percentile(cf,10):.3f}")
  print(f"  AVG lin-only={np.mean(cos_full):.3f}  AVG +VQ={np.mean(cos_resid):.3f}")
