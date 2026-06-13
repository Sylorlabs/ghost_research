# Most-generous GHOST: r=64 surrogate, in-sample ceiling check, and "does VQ even help?"
# Also: what cosine WOULD small-gate picks need to keep NLL delta < 0.03 nats?
import numpy as np, json, struct, os, time
WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4 = np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L=30; rec=8+7168*4
raw=open("acts_combined.bin","rb").read(); ntot=len(raw)//rec
hdr=np.frombuffer(raw,dtype=np.int32).reshape(ntot,rec//4)[:,:2]
idx=np.where(hdr[:,0]==L)[0]
X=np.stack([np.frombuffer(raw[i*rec+8:(i+1)*rec],dtype=np.float32) for i in idx]); N=X.shape[0]
path=f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f=open(path,'rb'); n=struct.unpack('<Q',f.read(8))[0]; hh=json.loads(f.read(n)); base=8+n
def T(name):
    t=hh[name]; o0,o1=t['data_offsets']; f.seek(base+o0); return np.frombuffer(f.read(o1-o0),dtype=np.uint8).reshape(t['shape'])
def deq(name):
    w=T(name+".weight"); s=T(name+".scale")
    W=np.empty((w.shape[0],w.shape[1]*2),dtype=np.float32); W[:,0::2]=FP4[w&15]; W[:,1::2]=FP4[w>>4]
    return W*np.repeat(np.exp2(s.astype(np.float32)-127.),32,axis=1)
def silu(x): return x/(1.0+np.exp(-x))
def fwd(e,Xin):
    w1=deq(f"layers.{L}.ffn.experts.{e}.w1");w3=deq(f"layers.{L}.ffn.experts.{e}.w3");w2=deq(f"layers.{L}.ffn.experts.{e}.w2")
    g=np.minimum(Xin@w1.T,10.0);u=np.clip(Xin@w3.T,-10.0,10.0);h=silu(g)*u;return h@w2.T
np.random.seed(1)
experts=[5,120,300]
perm=np.random.permutation(N); tr=perm[:N//2]; te=perm[N//2:]
Xtr,Xte=X[tr],X[te]
for r in (64,):
  print(f"=== r={r}, in-sample (TRAIN) vs held-out (TEST) ceiling ===")
  for e in experts:
    Otr=fwd(e,Xtr); Ote=fwd(e,Xte)
    mu=Xtr.mean(0); _,_,Vt=np.linalg.svd(Xtr-mu,full_matrices=False); P=Vt[:r]
    Ctr=(Xtr-mu)@P.T; Cte=(Xte-mu)@P.T
    A,_,_,_=np.linalg.lstsq(Ctr,Otr,rcond=None)
    def rc(Pm,Gm):
        pn=Pm/(np.linalg.norm(Pm,axis=1,keepdims=True)+1e-30);gn=Gm/(np.linalg.norm(Gm,axis=1,keepdims=True)+1e-30);return (pn*gn).sum(1)
    ctr=rc(Ctr@A,Otr); cte=rc(Cte@A,Ote)
    # variance explained: how much of output energy lives in the r-dim input projection at all
    print(f"  e{e}: TRAIN(in-sample) cos={ctr.mean():.3f}  TEST(held-out) cos={cte.mean():.3f} p10={np.percentile(cte,10):.3f}")
  # The fundamental wall: is the output even a function of a low-rank projection of input?
  # Test: full-rank linear map (r=128) held-out
  e=120; Otr=fwd(e,Xtr); Ote=fwd(e,Xte)
  for r2 in (128,):
    mu=Xtr.mean(0);_,_,Vt=np.linalg.svd(Xtr-mu,full_matrices=False);P=Vt[:r2]
    Ctr=(Xtr-mu)@P.T;Cte=(Xte-mu)@P.T;A,_,_,_=np.linalg.lstsq(Ctr,Otr,rcond=None)
    def rc(Pm,Gm):
        pn=Pm/(np.linalg.norm(Pm,axis=1,keepdims=True)+1e-30);gn=Gm/(np.linalg.norm(Gm,axis=1,keepdims=True)+1e-30);return (pn*gn).sum(1)
    print(f"  e120 FULL r={r2} linear: TRAIN cos={rc(Ctr@A,Otr).mean():.3f}  TEST cos={rc(Cte@A,Ote).mean():.3f}")
