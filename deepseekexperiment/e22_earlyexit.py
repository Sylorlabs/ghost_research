# E22: early-exit feasibility. Does the representation CONVERGE across layers
# (consecutive-layer activation cosine -> 1 in late layers = layers doing less
# = skippable for easy tokens)? Data: acts_long_off8000 (post-ffn_norm, L0-30).
import numpy as np
rec=8+7168*4
raw=open("acts_long_off8000.bin","rb").read()
a=np.frombuffer(raw,dtype=np.uint8).reshape(-1,rec)
lay=a[:,:4].view(np.uint32).reshape(-1); tok=a[:,4:8].view(np.uint32).reshape(-1)
X=a[:,8:].view(np.float32).reshape(-1,7168)
layers=sorted(set(lay.tolist()))
out=open("e22_results.txt","w")
def log(s):print(s);out.write(s+"\n");out.flush()
log(f"E22 early-exit probe: layers {min(layers)}-{max(layers)}, {len(set(tok.tolist()))} tokens")
# build [layer][token] -> activation, compute consecutive-layer cosine per token
ntok=int(tok.max())+1
def cos(u,v): return float((u*v).sum()/(np.linalg.norm(u)*np.linalg.norm(v)+1e-30))
log("\nconsecutive-layer activation cosine (mean over tokens) — rising->convergence:")
prev=None; cons=[]
for L in layers:
    cur={int(tok[i]):X[i] for i in range(len(X)) if lay[i]==L}
    if prev is not None:
        cs=[cos(prev[t],cur[t]) for t in cur if t in prev]
        cons.append((L,np.mean(cs)))
    prev=cur
for L,c in cons[::4]: log(f"  L{L-1}->L{L}: {c:.3f}")
# is it rising (convergence) or flat/falling?
early=np.mean([c for L,c in cons if L<=10]); late=np.mean([c for L,c in cons if L>20])
log(f"\nmean consecutive cosine: early layers (<=10) {early:.3f} | late (>20) {late:.3f}")
log(f"VERDICT: {'CONVERGING (late layers change less -> early-exit promising, capture 30-60 to confirm)' if late>early+0.05 else 'NOT converging in 0-30 (layers keep transforming -> early-exit weak here)'}")
out.close();print("E22 DONE")
