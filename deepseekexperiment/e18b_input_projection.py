# E18b: clean diagnostic — does an expert's OUTPUT depend only on the top-r
# input dims of a context? Project input to rank r (NO fitting), run the REAL
# expert, compare to full-input output. Isolates "is the expert locally
# low-dim" from "can a linear map capture it". Random split irrelevant (no fit).
import numpy as np, json, struct, os
WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4 = np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L=30; rec=8+7168*4
out=open("e18b_results.txt","w")
def log(s): print(s); out.write(s+"\n"); out.flush()
raw=open("acts_T128_off8000.bin","rb").read()
a=np.frombuffer(raw,dtype=np.uint8).reshape(-1,rec); lay=a[:,:4].view(np.uint32).reshape(-1)
X=a[lay==L][:,8:].view(np.float32).reshape(-1,7168).astype(np.float32)
log(f"E18b input-projection fidelity: layer {L}, {len(X)} context tokens")
path=f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f=open(path,'rb'); n=struct.unpack('<Q',f.read(8))[0]; hdr=json.loads(f.read(n)); base=8+n
def T(nm):
    t=hdr[nm]; o0,o1=t['data_offsets']; f.seek(base+o0); return np.frombuffer(f.read(o1-o0),dtype=np.uint8).reshape(t['shape'])
def deq(nm):
    w=T(nm+".weight"); s=T(nm+".scale"); W=np.empty((w.shape[0],w.shape[1]*2),dtype=np.float32); W[:,0::2]=FP4[w&15]; W[:,1::2]=FP4[w>>4]; return W*np.repeat(np.exp2(s.astype(np.float32)-127.),32,axis=1)
def silu(x): return x/(1.0+np.exp(-x))
def expert(X,e):
    W1=deq(f"layers.{L}.ffn.experts.{e}.w1");W3=deq(f"layers.{L}.ffn.experts.{e}.w3");W2=deq(f"layers.{L}.ffn.experts.{e}.w2")
    g=np.minimum(X@W1.T,10.);u=np.clip(X@W3.T,-10.,10.);return (silu(g)*u)@W2.T
def pcos(A,B):  # per-row mean cosine
    num=(A*B).sum(1); d=np.linalg.norm(A,axis=1)*np.linalg.norm(B,axis=1)+1e-30; return float((num/d).mean())
mu=X.mean(0); Xc=X-mu; _,_,Vt=np.linalg.svd(Xc,full_matrices=False)
experts=[0,50,150,300]
log(f"\nper-token output cosine: expert(proj_r(x)) vs expert(x)  [real expert, no fitting]")
log(f"{'rank':>5} " + " ".join(f"e{e:>4}" for e in experts))
for r in [16,32,48,64,84,110]:
    B=Vt[:r]; Xr=mu+Xc@B.T@B
    row=[pcos(expert(X,e), expert(Xr,e)) for e in experts]
    log(f"{r:>5} " + " ".join(f"{c:.3f}" for c in row))
log("\nINTERPRETATION: high cosine (>0.95) at small r => expert IS locally low-dim, surrogates viable (my E18 linear fit was just too weak). Low cosine => experts use full input dim even locally => input-subspace surrogates dead.")
out.close(); print("E18b DONE")
