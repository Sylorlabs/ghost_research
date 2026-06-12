# B8: is a SINGLE expert internally low-rank? (U2 tested a SHARED basis and
# failed; per-expert SVD is the independent fallback compression axis.)
import numpy as np, json, struct, os, sys
WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro","/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4 = np.array([0,.5,1,1.5,2,3,4,6,-0,-.5,-1,-1.5,-2,-3,-4,-6],dtype=np.float32)
L=30
path=f"{WD}/model-{L+2:05d}-of-00064.safetensors"
f=open(path,'rb'); n=struct.unpack('<Q',f.read(8))[0]; hdr=json.loads(f.read(n)); base=8+n
def T(name):
    t=hdr[name]; o0,o1=t['data_offsets']; f.seek(base+o0); return np.frombuffer(f.read(o1-o0),dtype=np.uint8).reshape(t['shape'])
out=open('b8_results.txt','w')
for e in (0, 100, 350):
    w=T(f"layers.{L}.ffn.experts.{e}.w1.weight"); s=T(f"layers.{L}.ffn.experts.{e}.w1.scale")
    W=np.empty((w.shape[0],w.shape[1]*2),dtype=np.float32); W[:,0::2]=FP4[w&15]; W[:,1::2]=FP4[w>>4]
    W*=np.repeat(np.exp2(s.astype(np.float32)-127.),32,axis=1)
    sv=np.linalg.svd(W,compute_uv=False)
    en=np.cumsum(sv**2)/np.sum(sv**2)
    line=f"expert {e}: rank for 50/80/90/95% energy = {np.searchsorted(en,.5)+1}/{np.searchsorted(en,.8)+1}/{np.searchsorted(en,.9)+1}/{np.searchsorted(en,.95)+1} of 3072"
    print(line); out.write(line+"\n"); out.flush()
out.close(); print("B8 DONE")
