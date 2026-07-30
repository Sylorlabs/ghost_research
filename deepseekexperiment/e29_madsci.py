#!/usr/bin/env python3
# E29: risky conversions Shannon does NOT bound (they change WHAT/HOW MUCH we compute):
#  (A) adaptive-k: gate is peaked? -> most tokens need <6 experts -> less fetch/token.
#  (B) per-matrix sensitivity: w1/w2/w3 may tolerate different bits -> adaptive precision.
import numpy as np, struct
DIM=7168
def load_mat(p):
    b=open(p,"rb").read(); r,c=struct.unpack_from("<II",b,0)
    return np.frombuffer(b,dtype="<f4",count=r*c,offset=8).reshape(r,c).astype(np.float64)
def load_acts(p,layer):
    raw=open(p,"rb").read(); rec=8+DIM*4; n=len(raw)//rec; out=[]; off=0
    for _ in range(n):
        l,t=struct.unpack_from("<II",raw,off)
        if l==layer: out.append(np.frombuffer(raw,dtype="<f4",count=DIM,offset=off+8))
        off+=rec
    return np.stack(out).astype(np.float64)
def sqrtsoftplus(x): return np.sqrt(np.where(x>20,x,np.log1p(np.exp(x))))
def silu(x): return x/(1+np.exp(-x))

X=load_acts("acts_T128.bin",30)
gate=load_mat("gate_L30_w.bin")        # [384,7168]
S=sqrtsoftplus(X@gate.T)               # [128,384] scores
TOPK=6
print("=== (A) ADAPTIVE-K: route-weight concentration among top-6 (real L30 tokens) ===")
ks=[]; shares=np.zeros(TOPK)
for i in range(X.shape[0]):
    idx=np.argsort(-S[i])[:TOPK]; w=S[i,idx]; w=w/w.sum()
    shares+=np.sort(w)[::-1]
    c=np.cumsum(np.sort(w)[::-1]); ks.append(int(np.searchsorted(c,0.90)+1))
shares/=X.shape[0]
print("  avg route-weight by rank: "+" ".join(f"{s:.3f}" for s in shares))
print(f"  cumulative: top1={shares[0]:.2f} top2={shares[:2].sum():.2f} top3={shares[:3].sum():.2f} top4={shares[:4].sum():.2f}")
print(f"  avg #experts for 90% route weight = {np.mean(ks):.2f} (of 6)  -> fetch cut = {6/np.mean(ks):.2f}x if adaptive-k viable")
print(f"  (note: dropped experts still contribute their gate-weight to the residual; this bounds potential, real quality test needs all experts)")

print("\n=== (B) PER-MATRIX SENSITIVITY: quantize ONE matrix, others f32 (output cos) ===")
def quant(W,bits,block=256):
    qmax=(1<<(bits-1))-1; out=W.reshape(W.shape[0],-1).copy(); C=out.shape[1]; nb=C//block
    Wb=out[:,:nb*block].reshape(out.shape[0],nb,block)
    sc=np.abs(Wb).max(2,keepdims=True)/qmax+1e-12
    out[:,:nb*block]=(np.round(Wb/sc).clip(-qmax,qmax)*sc).reshape(out.shape[0],nb*block)
    return out.reshape(W.shape)
def cos(a,b):a=a.ravel();b=b.ravel();return float(a@b/(np.linalg.norm(a)*np.linalg.norm(b)+1e-30))
def eout(w1,w2,w3,X): h=silu(X@w1.T)*(X@w3.T); return h@w2.T
for bits in (2,3):
    rows=[]
    for e in (0,5,100):
        w1=load_mat(f"expert_L30_e{e}_w1.bin");w2=load_mat(f"expert_L30_e{e}_w2.bin");w3=load_mat(f"expert_L30_e{e}_w3.bin")
        Yr=eout(w1,w2,w3,X)
        c1=cos(eout(quant(w1,bits),w2,w3,X),Yr)
        c2=cos(eout(w1,quant(w2,bits),w3,X),Yr)
        c3=cos(eout(w1,w2,quant(w3,bits),X),Yr)
        rows.append((c1,c2,c3))
    r=np.mean(rows,0)
    print(f"  {bits}-bit: w1-only={r[0]:.4f}  w2-only={r[1]:.4f}  w3-only={r[2]:.4f}  (higher=more tolerant -> give it fewer bits)")
print("\nif one matrix is far more tolerant, store it at lower bits (adaptive precision, free-ish).")
