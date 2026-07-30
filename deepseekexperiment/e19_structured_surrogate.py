# E19: OUR OWN EXPERT. Full structured surrogate (input+output projected,
# swiglu preserved), fit by closed-form SVD (NO retraining) to reproduce a
# DeepSeek expert on ONE context. Random fit/test split (removes drift
# confound). Reports HELD-OUT output cosine AND true bytes/expert.
import numpy as np, json, struct, os
WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4=np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L=30; rec=8+7168*4
out=open("e19_results.txt","w")
def log(s): print(s); out.write(s+"\n"); out.flush()
raw=open("acts_T128_off8000.bin","rb").read()
a=np.frombuffer(raw,dtype=np.uint8).reshape(-1,rec); lay=a[:,:4].view(np.uint32).reshape(-1)
X=a[lay==L][:,8:].view(np.float32).reshape(-1,7168).astype(np.float32)
N=len(X); rng=np.random.default_rng(0); perm=rng.permutation(N); tr,te=perm[:96],perm[96:]
log(f"E19 structured surrogate (OUR expert): layer {L}, {N} tokens, random {len(tr)} fit / {len(te)} held-out")
path=f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f=open(path,'rb'); n=struct.unpack('<Q',f.read(8))[0]; hdr=json.loads(f.read(n)); base=8+n
def T(nm):
    t=hdr[nm];o0,o1=t['data_offsets'];f.seek(base+o0);return np.frombuffer(f.read(o1-o0),dtype=np.uint8).reshape(t['shape'])
def deq(nm):
    w=T(nm+".weight");s=T(nm+".scale");W=np.empty((w.shape[0],w.shape[1]*2),dtype=np.float32);W[:,0::2]=FP4[w&15];W[:,1::2]=FP4[w>>4];return W*np.repeat(np.exp2(s.astype(np.float32)-127.),32,axis=1)
def silu(x): return x/(1.0+np.exp(-x))
def expert_full(X,W1,W3,W2):
    g=np.minimum(X@W1.T,10.);u=np.clip(X@W3.T,-10.,10.);return (silu(g)*u)@W2.T
def pcos(A,B):
    num=(A*B).sum(1);d=np.linalg.norm(A,axis=1)*np.linalg.norm(B,axis=1)+1e-30;return float((num/d).mean())
# shared input basis from FIT tokens (stored once/layer)
mux=X[tr].mean(0); Xc=X-mux; _,_,Vt=np.linalg.svd(Xc[tr],full_matrices=False)
experts=[0,50,150,300]
log(f"\nheld-out output cosine of OUR surrogate vs real expert, + true bytes/expert:")
log(f"{'r':>4} " + " ".join(f"e{e:>4}" for e in experts) + "   B/exp(fp32)  B/exp(P3~)  WS_hot64  WS_full250")
for r in [32,48,64,84]:
    B=Vt[:r]                                   # [r,7168] shared/layer
    Z=Xc@B.T                                   # [N,r]
    cosr=[]
    for e in experts:
        W1=deq(f"layers.{L}.ffn.experts.{e}.w1");W3=deq(f"layers.{L}.ffn.experts.{e}.w3");W2=deq(f"layers.{L}.ffn.experts.{e}.w2")
        # input-projected weights (our surrogate's params)
        W1p=B@W1.T; b1=mux@W1.T                 # [r,3072],[3072]
        W3p=B@W3.T; b3=mux@W3.T
        # true outputs on fit -> output basis (per expert)
        Ytr=expert_full(X[tr],W1,W3,W2); muy=Ytr.mean(0)
        _,_,VtY=np.linalg.svd(Ytr-muy,full_matrices=False); C=VtY[:r]   # [r,7168] per expert
        W2pp=(C@W2)                              # [r,3072]  (C@W2: r x 3072)
        # surrogate forward on HELD-OUT
        z=Z[te]
        g=np.minimum(z@W1p+b1,10.); u=np.clip(z@W3p+b3,-10.,10.); h=silu(g)*u   # [te,3072]
        ocoord=h@W2pp.T                          # [te,r]
        Ohat=muy+ocoord@C                        # [te,7168]
        Otrue=expert_full(X[te],W1,W3,W2)
        cosr.append(pcos(Otrue,Ohat))
    # bytes: W1p,W3p,W2pp [r,3072] + C[r,7168] + muy[7168] + b1,b3[3072]  (B shared/layer, excluded)
    params=3*r*3072 + r*7168 + 7168 + 2*3072
    b32=params*4/1e6; bp3=params*3.25/8/1e6
    log(f"{r:>4} " + " ".join(f"{c:.3f}" for c in cosr) + f"   {b32:.2f}MB     {bp3:.2f}MB    {64*58*bp3/1000:.1f}GB    {250*58*bp3/1000:.1f}GB")
log("\nP3 baseline (current per-matmul) ~0.98. >0.90 held-out at a RAM-fitting working set = OUR EXPERT beats streaming.")
log("WS_hot64 = surrogate working set if a coherent session has ~64 hot experts/layer (E16 measures this); WS_full250 = full diverse working set.")
out.close(); print("E19 DONE")
