# E19e: does a BIGGER basis close the held-out generalization gap? Held-out
# fidelity at warmup=384, sweeping r. If input-proj held-out reaches ~0.90 at
# some r, the surrogate is viable at that r (size permitting via hot-set);
# if it plateaus low for ALL r, the manifold drifts too much -> static surrogate dead.
import numpy as np, json, struct, os
WD=next(d for d in("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4=np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L=30;rec=8+7168*4
out=open("e19e_results.txt","w")
def log(s):print(s);out.write(s+"\n");out.flush()
raw=open("acts_long_off8000.bin","rb").read()
a=np.frombuffer(raw,dtype=np.uint8).reshape(-1,rec);lay=a[:,:4].view(np.uint32).reshape(-1)
X=a[lay==L][:,8:].view(np.float32).reshape(-1,7168).astype(np.float32)
N=len(X);rng=np.random.default_rng(1);perm=rng.permutation(N);te=perm[-128:];tr=perm[:384]
log(f"E19e rank sweep (held-out generalization): layer {L}, {len(tr)} warmup / {len(te)} held-out")
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
mux=X[tr].mean(0);Xc=X-mux;_,_,Vt=np.linalg.svd(Xc[tr],full_matrices=False)
log(f"{'r':>4} {'inputproj-HO':>13} {'fullsurr-HO':>12} {'P3 MB/exp':>10} {'WS_hot64':>9} {'WS_250':>7} {'held-out input energy covered':>30}")
for r in [64,128,192,256,320,383]:
    B=Vt[:r]
    cov=float((np.linalg.norm(Xc[te]@B.T,axis=1)**2 / (np.linalg.norm(Xc[te],axis=1)**2+1e-30)).mean())
    Xrte=mux+Xc[te]@B.T@B;z=Xc[te]@B.T
    ipo=[];full=[]
    for e in experts:
        W1,W3,W2=EW[e]
        ipo.append(pcos(ef(X[te],W1,W3,W2),ef(Xrte,W1,W3,W2)))
        Ytr=ef(X[tr],W1,W3,W2);muy=Ytr.mean(0);_,_,VtY=np.linalg.svd(Ytr-muy,full_matrices=False);C=VtY[:r]
        g=np.minimum(z@(B@W1.T)+mux@W1.T,10.);u=np.clip(z@(B@W3.T)+mux@W3.T,-10.,10.);h=silu(g)*u
        full.append(pcos(ef(X[te],W1,W3,W2),muy+(h@(C@W2).T)@C))
    params=3*r*3072+r*7168+7168+2*3072;mb=params*3.25/8/1e6
    log(f"{r:>4} {np.mean(ipo):>13.3f} {np.mean(full):>12.3f} {mb:>10.2f} {64*58*mb/1000:>8.1f}G {250*58*mb/1000:>6.1f}G {100*cov:>28.0f}%")
log("\nif input-proj-HO reaches ~0.95 at some r AND WS fits 16GB -> surrogate viable at that r; if it plateaus <0.7 for all r -> manifold drift kills static surrogate (go hybrid).")
out.close();print("E19e DONE")
