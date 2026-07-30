# COARSE-TO-FINE decisive probe v2 — sorted-offset single-pass weight read.
# Same science as c2f_probe.py but avoids fuse random-seek thrash: collect all
# (w1,w3,w2) tensor byte-ranges for the 384 experts, sort by file offset, read in
# one forward sweep. Then forward real acts, cluster into K super-experts, measure
# served-by-centroid residual = the C2F floor lever (phi_disk).
import numpy as np, json, struct, os, time, sys
WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4 = np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L = int(sys.argv[1]) if len(sys.argv)>1 else 30
K = int(sys.argv[2]) if len(sys.argv)>2 else 32
N_IN = int(sys.argv[3]) if len(sys.argv)>3 else 64
N_EXPERTS = 384
out = open(f"c2f_results_L{L}_K{K}.txt","w")
def log(s): print(s,flush=True); out.write(s+"\n"); out.flush()

rec = 8 + 7168*4
raw = open("acts_combined.bin","rb").read()
ntot = len(raw)//rec
hdrs = np.frombuffer(raw, dtype=np.int32).reshape(ntot, rec//4)[:, :2]
layer_mask = np.where(hdrs[:,0]==L)[0]
sel = layer_mask[np.linspace(0,len(layer_mask)-1,min(N_IN,len(layer_mask))).astype(int)]
X = np.stack([np.frombuffer(raw[i*rec+8:(i+1)*rec], dtype=np.float32) for i in sel]).astype(np.float32)
N = X.shape[0]
log(f"C2F v2: layer {L}, K={K}, {N} real layer-{L} inputs (avail {len(layer_mask)})")

path = f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f = open(path,'rb'); n = struct.unpack('<Q', f.read(8))[0]; hdr = json.loads(f.read(n)); base = 8+n
# gather byte ranges for every expert's w1/w3/w2 weight+scale, sorted by offset
need=[]
for e in range(N_EXPERTS):
    for mat in ("w1","w3","w2"):
        for suf in ("weight","scale"):
            name=f"layers.{L}.ffn.experts.{e}.{mat}.{suf}"
            t=hdr[name]; o0,o1=t['data_offsets']
            need.append((base+o0, base+o1, t['shape'], e, mat, suf))
need.sort()
blob={}  # (e,mat,suf)->ndarray
t0=time.time()
for o0,o1,shape,e,mat,suf in need:
    f.seek(o0); b=f.read(o1-o0)
    blob[(e,mat,suf)]=np.frombuffer(b,dtype=np.uint8).reshape(shape)
log(f"weight read (sorted single pass): {time.time()-t0:.0f}s, {len(need)} tensors")

def deqE(e,mat):
    w=blob[(e,mat,'weight')]; s=blob[(e,mat,'scale')]
    W=np.empty((w.shape[0],w.shape[1]*2),dtype=np.float32); W[:,0::2]=FP4[w&15]; W[:,1::2]=FP4[w>>4]
    return W*np.repeat(np.exp2(s.astype(np.float32)-127.),32,axis=1)
def silu(x): return x/(1.0+np.exp(-x))

t0=time.time()
O=np.empty((N_EXPERTS,N,7168),dtype=np.float32)
for e in range(N_EXPERTS):
    w1=deqE(e,'w1'); w3=deqE(e,'w3'); w2=deqE(e,'w2')
    g=np.minimum(X@w1.T,10.0); u=np.clip(X@w3.T,-10.0,10.0)
    h=silu(g)*u; O[e]=h@w2.T
    for k in (e,'w1','w3','w2'): blob.pop((e,k),None) if k in ('w1','w3','w2') else None
    if e%96==0: log(f"  fwd expert {e} t={time.time()-t0:.0f}s")
log(f"forward all experts: {time.time()-t0:.0f}s")

flat=O.reshape(N_EXPERTS,-1)
norm=flat/(np.linalg.norm(flat,axis=1,keepdims=True)+1e-30)
C=norm@norm.T; np.fill_diagonal(C,-1); best=C.max(axis=1)
log("\n=== E15 functional sibling cosine (output space) ===")
for thr in (0.99,0.95,0.90,0.80,0.70): log(f"  sibling cos>={thr:.2f}: {100*(best>=thr).mean():5.1f}%")
log(f"  mean nearest sibling={best.mean():.4f} median={np.median(best):.4f}")

# agglomerative avg-linkage -> K clusters
Dm=(1.0-(norm@norm.T)).astype(np.float64); np.fill_diagonal(Dm,np.inf)
groups=[[i] for i in range(N_EXPERTS)]; M=Dm.copy()
while len(groups)>K:
    i,j=divmod(int(np.argmin(M)),M.shape[0])
    if i>j: i,j=j,i
    ni,nj=len(groups[i]),len(groups[j])
    newrow=(ni*M[i]+nj*M[j])/(ni+nj)
    groups[i]=groups[i]+groups[j]; M[i]=newrow; M[:,i]=newrow; M[i,i]=np.inf
    M=np.delete(M,j,0); M=np.delete(M,j,1); del groups[j]
sizes=sorted(len(g) for g in groups)
log(f"\n=== C2F clustering: {len(groups)} super-experts, sizes min={sizes[0]} med={sizes[len(sizes)//2]} max={sizes[-1]} ===")

cent=np.zeros((len(groups),N,7168),dtype=np.float32); eid2grp=np.full(N_EXPERTS,-1,int)
for gi,g in enumerate(groups):
    cent[gi]=O[g].mean(axis=0)
    for e in g: eid2grp[e]=gi
def cosr(a,b):
    an=a/(np.linalg.norm(a,axis=-1,keepdims=True)+1e-30); bn=b/(np.linalg.norm(b,axis=-1,keepdims=True)+1e-30)
    return (an*bn).sum(-1)
res=np.empty((N_EXPERTS,N),dtype=np.float32)
for e in range(N_EXPERTS): res[e]=cosr(O[e],cent[eid2grp[e]])
log("\n=== served-by-super-expert residual cos(true expert out, centroid) over ALL (expert,token) ===")
for thr in (0.99,0.95,0.90,0.80,0.70,0.50): log(f"   cos>={thr:.2f}: {100*(res>=thr).mean():5.1f}% served from RAM")
log(f"  mean res={res.mean():.4f} median={np.median(res):.4f}")
tn=np.linalg.norm(O,axis=-1); cn=np.linalg.norm(cent[eid2grp],axis=-1)
log(f"  centroid/true norm ratio mean={np.nanmean(cn/(tn+1e-30)):.3f}")

# conditional on REAL top-6 routing (e4_routing.csv) for this layer if available
import csv as _csv
try:
    rr=[r for r in _csv.reader(open('e4_routing.csv')) if r and r[0].isdigit() and int(r[0])==L]
    # build set of (token,expert) that actually routed at layer L; map token->row index in sel
    tok2idx={int(hdrs[s,1]):k for k,s in enumerate(sel)}
    pairs=[]
    for r in rr:
        tok=int(r[1])
        if tok in tok2idx:
            for e in r[3:9]: pairs.append((int(e),tok2idx[tok]))
    if pairs:
        rc=np.array([res[e,t] for e,t in pairs])
        log(f"\n=== CONDITIONAL on real top-6 routing: {len(pairs)} (expert,token) invocations ===")
        for thr in (0.95,0.90,0.80,0.70): log(f"   cos>={thr:.2f}: {100*(rc>=thr).mean():5.1f}% served-from-RAM => phi_disk={1-(rc>=thr).mean():.3f}")
        log(f"  mean conditional res={rc.mean():.4f} median={np.median(rc):.4f}")
except Exception as ex:
    log(f"(conditional routing skip: {ex})")

log("\n=== projected disk fraction phi_disk (C2F, K=32 RAM-resident centroids) ===")
for thr in (0.95,0.90,0.80):
    log(f"   bar cos>={thr:.2f}: phi_disk={1-(res>=thr).mean():.3f}")
np.save(f"c2f_cosine_L{L}.npy",C); out.close(); print("C2F DONE")
