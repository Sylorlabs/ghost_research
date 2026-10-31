# E19d: structural ceiling — in-sample (perfect basis from all tokens) surrogate
# fidelity. If full-surrogate hits >=0.90 here, the STRUCTURE works and the held-
# out gap is purely warm-up/basis-estimation (fixable with longer capture). If it
# caps low, the structure itself needs a nonlinear core.
import numpy as np, json, struct, os
WD=next(d for d in("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4=np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L=30;rec=8+7168*4
out=open("e19d_results.txt","w")
def log(s):print(s);out.write(s+"\n");out.flush()
raw=open("acts_T128_off8000.bin","rb").read()
a=np.frombuffer(raw,dtype=np.uint8).reshape(-1,rec);lay=a[:,:4].view(np.uint32).reshape(-1)
X=a[lay==L][:,8:].view(np.float32).reshape(-1,7168).astype(np.float32)
log(f"E19d structural ceiling (in-sample, perfect basis): layer {L}, {len(X)} tokens")
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
experts=[0,30,50,90,150,200,300,360]
EW={e:(deq(f"layers.{L}.ffn.experts.{e}.w1"),deq(f"layers.{L}.ffn.experts.{e}.w3"),deq(f"layers.{L}.ffn.experts.{e}.w2")) for e in experts}
mux=X.mean(0);Xc=X-mux;_,_,Vt=np.linalg.svd(Xc,full_matrices=False)
log(f"{'r':>4} {'input-proj':>11} {'full-surr':>10}  (mean over {len(experts)} experts, in-sample)")
for r in [48,64,84,110,124]:
    B=Vt[:r];ipo=[];full=[]
    Xr=mux+Xc@B.T@B;z=Xc@B.T
    for e in experts:
        W1,W3,W2=EW[e]
        ipo.append(pcos(ef(X,W1,W3,W2),ef(Xr,W1,W3,W2)))
        Y=ef(X,W1,W3,W2);muy=Y.mean(0);_,_,VtY=np.linalg.svd(Y-muy,full_matrices=False);C=VtY[:r]
        g=np.minimum(z@(B@W1.T)+mux@W1.T,10.);u=np.clip(z@(B@W3.T)+mux@W3.T,-10.,10.);h=silu(g)*u
        full.append(pcos(Y,muy+(h@(C@W2).T)@C))
    log(f"{r:>4} {np.mean(ipo):>11.3f} {np.mean(full):>10.3f}")
log("\nNOTE in-sample is OPTIMISTIC (128 tokens, basis up to r dims). Tells the STRUCTURAL ceiling, not deployable fidelity. >0.95 here => structure is sound, gap is warm-up.")
out.close();print("E19d DONE")
