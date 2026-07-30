# E20: is a real expert distinguishable from pure gaussian noise by ANY math?
# If yes -> the distinguishing statistic is structure to exploit (new-math door).
# If no -> information-theoretically dense; all linear/spectral math precluded.
import numpy as np, json, struct, os
WD=next(d for d in("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4=np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L=30
path=f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f=open(path,'rb');n=struct.unpack('<Q',f.read(8))[0];hdr=json.loads(f.read(n));base=8+n
def deq(nm):
    t=hdr[nm+".weight"];o0,o1=t['data_offsets'];f.seek(base+o0);w=np.frombuffer(f.read(o1-o0),dtype=np.uint8).reshape(t['shape'])
    s=hdr[nm+".scale"];so0,so1=s['data_offsets'];f.seek(base+so0);sc=np.frombuffer(f.read(so1-so0),dtype=np.uint8).reshape(s['shape'])
    W=np.empty((w.shape[0],w.shape[1]*2),dtype=np.float32);W[:,0::2]=FP4[w&15];W[:,1::2]=FP4[w>>4]
    return W*np.repeat(np.exp2(sc.astype(np.float32)-127.),32,axis=1)
out=open("e20_results.txt","w")
def log(s):print(s);out.write(s+"\n");out.flush()
W=deq(f"layers.{L}.ffn.experts.0.w1")  # [3072,7168]
G=np.random.default_rng(0).standard_normal(W.shape).astype(np.float32)*W.std()
log(f"E20 new-math probe: real expert L30 e0 {W.shape} vs matched gaussian")

def wht(x):  # fast Walsh-Hadamard on padded rows
    m=1
    while m< x.shape[1]: m*=2
    xp=np.zeros((x.shape[0],m),dtype=np.float32); xp[:,:x.shape[1]]=x
    h=1
    while h<m:
        for i in range(0,m,h*2):
            a=xp[:,i:i+h].copy(); b=xp[:,i+h:i+2*h].copy()
            xp[:,i:i+h]=a+b; xp[:,i+h:i+2*h]=a-b
        h*=2
    return xp

def kurt(x):
    m=x.mean();v=x.var();return float(((x-m)**4).mean()/v**2 - 3)
def concentration(x):  # WHT energy in top-1% coeffs (gaussian=flat~1%)
    w=wht(x); e=w**2; e=np.sort(e,axis=1)[:,::-1]; cum=np.cumsum(e,axis=1)/e.sum(axis=1,keepdims=True)
    k=max(1,w.shape[1]//100); return float(cum[:,k-1].mean())
log("\n-- distinguishing statistics (real vs matched gaussian) --")
log(f"  kurtosis (excess):      real {kurt(W.flatten()):+.4f}  | gauss {kurt(G.flatten()):+.4f}")
log(f"  WHT energy in top-1%:   real {100*concentration(W):.2f}% | gauss {100*concentration(G):.2f}%  (flat=1%)")
# row-norm variation (structure across rows)
rn=np.linalg.norm(W,axis=1); gn=np.linalg.norm(G,axis=1)
log(f"  row-norm CV:            real {rn.std()/rn.mean():.4f}     | gauss {gn.std()/gn.mean():.4f}")
# autocorrelation (smoothness/periodicity along K)
def ac1(x): return float(np.mean([np.corrcoef(r[:-1],r[1:])[0,1] for r in x[:64]]))
log(f"  lag-1 autocorr (rows):  real {ac1(W):+.4f}     | gauss {ac1(G):+.4f}")
log("\nVERDICT: if real ~= gauss on all stats -> information-theoretically dense, math space closed.")
log("if real differs sharply on some stat -> that statistic is the structure to exploit.")
out.close();print("E20 DONE")
