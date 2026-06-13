# E19b: does surrogate held-out fidelity climb with warm-up length? The E19
# gap (in-sample 0.93 vs held-out 0.55) looks like basis under-estimation from
# only 96 tokens. Sweep fit-set size against a FIXED held-out set. Also isolate
# input-projection-only (full W2) vs full output-projected surrogate.
import numpy as np, json, struct, os
WD=next(d for d in("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4=np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L=30;rec=8+7168*4;r=64
out=open("e19b_results.txt","w")
def log(s):print(s);out.write(s+"\n");out.flush()
raw=open("acts_T128_off8000.bin","rb").read()
a=np.frombuffer(raw,dtype=np.uint8).reshape(-1,rec);lay=a[:,:4].view(np.uint32).reshape(-1)
X=a[lay==L][:,8:].view(np.float32).reshape(-1,7168).astype(np.float32)
N=len(X);rng=np.random.default_rng(1);perm=rng.permutation(N);te=perm[-32:];pool=perm[:-32]
path=f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f=open(path,'rb');n=struct.unpack('<Q',f.read(8))[0];hdr=json.loads(f.read(n));base=8+n
def T(nm):
    t=hdr[nm];o0,o1=t['data_offsets'];f.seek(base+o0);return np.frombuffer(f.read(o1-o0),dtype=np.uint8).reshape(t['shape'])
def deq(nm):
    w=T(nm+".weight");s=T(nm+".scale");W=np.empty((w.shape[0],w.shape[1]*2),dtype=np.float32);W[:,0::2]=FP4[w&15];W[:,1::2]=FP4[w>>4];return W*np.repeat(np.exp2(s.astype(np.float32)-127.),32,axis=1)
def silu(x):return x/(1.0+np.exp(-x))
def ef(X,W1,W3,W2):
    g=np.minimum(X@W1.T,10.);u=np.clip(X@W3.T,-10.,10.);return(silu(g)*u)@W2.T
def pcos(A,B):
    num=(A*B).sum(1);d=np.linalg.norm(A,axis=1)*np.linalg.norm(B,axis=1)+1e-30;return float((num/d).mean())
experts=[0,50,150,300]
EW={e:(deq(f"layers.{L}.ffn.experts.{e}.w1"),deq(f"layers.{L}.ffn.experts.{e}.w3"),deq(f"layers.{L}.ffn.experts.{e}.w2")) for e in experts}
log(f"E19b warm-up curve (r={r}, fixed 32 held-out), mean held-out cosine over {len(experts)} experts:")
log(f"{'warmup':>7} {'input-proj-only':>16} {'full-surrogate':>15}")
for fit in [16,32,48,64,80,96]:
    tr=pool[:fit]
    mux=X[tr].mean(0);Xc=X-mux
    if fit<=r:  # basis rank can't exceed samples
        _,_,Vt=np.linalg.svd(Xc[tr],full_matrices=False);B=Vt[:min(r,fit-1)]
    else:
        _,_,Vt=np.linalg.svd(Xc[tr],full_matrices=False);B=Vt[:r]
    ipo,full=[],[]
    Xrte=mux+Xc[te]@B.T@B
    for e in experts:
        W1,W3,W2=EW[e]
        ipo.append(pcos(ef(X[te],W1,W3,W2), ef(Xrte,W1,W3,W2)))   # input-proj only, full weights
        # full surrogate
        Ytr=ef(X[tr],W1,W3,W2);muy=Ytr.mean(0)
        _,_,VtY=np.linalg.svd(Ytr-muy,full_matrices=False);C=VtY[:min(r,len(tr)-1)]
        z=Xc[te]@B.T
        g=np.minimum(z@(B@W1.T)+mux@W1.T,10.);u=np.clip(z@(B@W3.T)+mux@W3.T,-10.,10.);h=silu(g)*u
        Ohat=muy+(h@(C@W2).T)@C
        full.append(pcos(ef(X[te],W1,W3,W2),Ohat))
    log(f"{fit:>7} {np.mean(ipo):>16.3f} {np.mean(full):>15.3f}")
log("\nIf both columns CLIMB with warm-up, longer sessions => higher fidelity (capture more tokens to confirm).")
log("input-proj-only ceiling = best possible if output basis were perfect; gap to full = output-projection cost.")
out.close();print("E19b DONE")
