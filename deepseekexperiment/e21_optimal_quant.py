# E21: can a BETTER quantizer beat greedy bitplanes at matched bits? (Not
# structure-exploitation — rate-distortion optimality. Noise result doesn't
# preclude this.) Compare on a real expert, measure GEMV cosine on real acts.
import numpy as np, json, struct, os
WD=next(d for d in("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4=np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L=30;rec=8+7168*4
out=open("e21_results.txt","w")
def log(s):print(s);out.write(s+"\n");out.flush()
path=f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f=open(path,'rb');n=struct.unpack('<Q',f.read(8))[0];hdr=json.loads(f.read(n));base=8+n
def deq(nm):
    t=hdr[nm+".weight"];o0,o1=t['data_offsets'];f.seek(base+o0);w=np.frombuffer(f.read(o1-o0),dtype=np.uint8).reshape(t['shape'])
    s=hdr[nm+".scale"];so0,so1=s['data_offsets'];f.seek(base+so0);sc=np.frombuffer(f.read(so1-so0),dtype=np.uint8).reshape(s['shape'])
    W=np.empty((w.shape[0],w.shape[1]*2),dtype=np.float32);W[:,0::2]=FP4[w&15];W[:,1::2]=FP4[w>>4]
    return W*np.repeat(np.exp2(sc.astype(np.float32)-127.),32,axis=1)
W=deq(f"layers.{L}.ffn.experts.0.w1")  # [3072,7168]
# real activations for this layer
raw=open("acts_long_off8000.bin","rb").read()
a=np.frombuffer(raw,dtype=np.uint8).reshape(-1,rec);lay=a[:,:4].view(np.uint32).reshape(-1)
X=a[lay==L][:,8:].view(np.float32).reshape(-1,7168).astype(np.float32)[:64]
Yref=X@W.T
def cos(B):
    Yb=X@B.T; return float((Yref*Yb).sum()/(np.linalg.norm(Yref)*np.linalg.norm(Yb)+1e-30))
log(f"E21 optimal-quant vs bitplanes: expert L30 e0 {W.shape}, {len(X)} real acts")
BLK=64
def bitplanes(W,planes):  # greedy sign decomposition (current method)
    R=W.copy().reshape(-1,BLK); out=np.zeros_like(R)
    for _ in range(planes):
        s=np.sign(R); s[s==0]=1; sc=np.abs(R).mean(1,keepdims=True); out+=s*sc; R-=s*sc
    return out.reshape(W.shape)
def lloydmax(W,bits):  # optimal scalar quantizer per block (k-means 1D)
    levels=2**bits; R=W.reshape(-1,BLK); out=np.empty_like(R)
    for i in range(R.shape[0]):
        v=R[i]; c=np.quantile(v,np.linspace(0,1,levels))  # init
        for _ in range(8):
            d=np.abs(v[:,None]-c[None,:]); idx=d.argmin(1)
            for k in range(levels):
                m=idx==k
                if m.any(): c[k]=v[m].mean()
        out[i]=c[np.abs(v[:,None]-c[None,:]).argmin(1)]
    return out.reshape(W.shape)
def vq(W,dim,cbits):  # vector quant: k-means on dim-D subvectors, 2^cbits codes
    R=W.reshape(-1,dim); K=2**cbits
    rng=np.random.default_rng(0); C=R[rng.choice(len(R),K,replace=False)].copy()
    for _ in range(6):
        # assign (chunked)
        idx=np.empty(len(R),dtype=np.int32)
        for s in range(0,len(R),100000):
            ch=R[s:s+100000]; d=((ch[:,None,:]-C[None,:,:])**2).sum(2); idx[s:s+100000]=d.argmin(1)
        for k in range(K):
            m=idx==k
            if m.any(): C[k]=R[m].mean(0)
    return C[idx].reshape(W.shape), (cbits/dim)  # bits/weight
log(f"\n{'method':<22}{'bits/w':>8}{'cosine':>10}")
log(f"{'bitplane P2':<22}{2.25:>8.2f}{cos(bitplanes(W,2)):>10.4f}")
log(f"{'bitplane P3':<22}{3.25:>8.2f}{cos(bitplanes(W,3)):>10.4f}")
log(f"{'Lloyd-Max 2-bit':<22}{2.13:>8.2f}{cos(lloydmax(W,2)):>10.4f}")
log(f"{'Lloyd-Max 3-bit':<22}{3.13:>8.2f}{cos(lloydmax(W,3)):>10.4f}")
for dim,cb in [(2,8),(4,8),(2,10)]:
    Bq,bpw=vq(W,dim,cb)
    log(f"{'VQ d='+str(dim)+' '+str(cb)+'bit':<22}{bpw+0.13:>8.2f}{cos(Bq):>10.4f}")
log("\nif Lloyd/VQ matches bitplane-P3 cosine at <3.25 bits -> real fetch win (better quantizer).")
out.close();print("E21 DONE")
