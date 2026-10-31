#!/usr/bin/env python3
# E27: activation-aware ("beyond XOR") quantization. Every quantizer so far minimizes
# WEIGHT error. What's expensive is OUTPUT error, which depends on the (strongly
# anisotropic, 50-sigma, e26) activations. Spend bits on weight columns the activations
# actually excite. Metric = FULL EXPERT OUTPUT cosine on REAL L30 activations, vs bits/w.
import numpy as np, struct, sys, collections

DIM = 7168
def load_mat(p):
    b = open(p, "rb").read()
    r, c = struct.unpack_from("<II", b, 0)
    W = np.frombuffer(b, dtype="<f4", count=r*c, offset=8).reshape(r, c).astype(np.float32)
    return W

def load_acts_layer(p, layer):
    raw = open(p, "rb").read(); rec = 8 + DIM*4; n = len(raw)//rec; out=[]
    off=0
    for _ in range(n):
        l,t = struct.unpack_from("<II", raw, off)
        if l==layer:
            out.append(np.frombuffer(raw, dtype="<f4", count=DIM, offset=off+8))
        off+=rec
    return np.stack(out).astype(np.float32)  # [ntok, DIM]

def silu(x): return x/(1.0+np.exp(-x))

def quant_uniform(W, bits, block=256):
    qmax = (1<<(bits-1))-1
    out = W.copy().reshape(W.shape[0], -1)
    C = out.shape[1]; nb = C//block
    Wb = out[:, :nb*block].reshape(out.shape[0], nb, block)
    scale = np.abs(Wb).max(axis=2, keepdims=True)/qmax + 1e-12
    Wb_q = np.round(Wb/scale).clip(-qmax, qmax)*scale
    out[:, :nb*block] = Wb_q.reshape(out.shape[0], nb*block)
    return out.reshape(W.shape)

def lloyd_levels(vals, N, iters=12):
    lv = np.quantile(vals, (np.arange(N)+0.5)/N)
    for _ in range(iters):
        idx = np.abs(vals[:,None]-lv[None,:]).argmin(1)
        for k in range(N):
            m = idx==k
            if m.any(): lv[k]=vals[m].mean()
    return lv

def quant_lloyd(W, bits, block=256):
    N = 1<<bits
    out = W.copy().reshape(W.shape[0], -1)
    C = out.shape[1]; nb=C//block
    Wb = out[:, :nb*block].reshape(out.shape[0], nb, block)
    scale = np.sqrt((Wb**2).mean(axis=2, keepdims=True))+1e-12
    norm = (Wb/scale).reshape(-1)
    lv = np.sort(lloyd_levels(norm[::13], N))   # subsample to fit levels
    edges = (lv[:-1]+lv[1:])/2                   # bin boundaries
    idx = np.searchsorted(edges, norm)           # O(n log N), no [n,N] broadcast
    deq = (lv[idx].reshape(Wb.shape))*scale
    out[:, :nb*block] = deq.reshape(out.shape[0], nb*block)
    return out.reshape(W.shape)

def cos(a,b):
    a=a.reshape(-1); b=b.reshape(-1)
    return float(a@b/(np.linalg.norm(a)*np.linalg.norm(b)+1e-30))

def expert_out(w1,w2,w3,X):           # X:[n,DIM] -> Y:[n, DIM]
    g = X@w1.T; u = X@w3.T            # [n, inter]
    h = silu(g)*u
    return h@w2.T

def awq_scale(W, s, alpha):           # scale input-columns (axis=1) by s^alpha
    sc = (s**alpha); sc = sc/sc.mean()
    return W*sc[None,:], sc

EXPERTS=[0,5,100]
X = load_acts_layer("acts_T128.bin", 30)
print(f"L30 acts: {X.shape}, per-channel |x| anisotropy: max/median = "
      f"{np.abs(X).mean(0).max()/np.median(np.abs(X).mean(0)):.1f}x")
s_in = np.sqrt((X**2).mean(0))        # per-input-channel activation scale (for w1,w3)

def eval_quant(bits, mode, alpha=0.5):
    coss=[]
    for e in EXPERTS:
        w1=load_mat(f"expert_L30_e{e}_w1.bin"); w2=load_mat(f"expert_L30_e{e}_w2.bin"); w3=load_mat(f"expert_L30_e{e}_w3.bin")
        Yref=expert_out(w1,w2,w3,X)
        # intermediate scale for w2 (input = h)
        g=X@w1.T; u=X@w3.T; h=silu(g)*u; s_mid=np.sqrt((h**2).mean(0))
        if mode=="uniform":
            q1,q2,q3=quant_uniform(w1,bits),quant_uniform(w2,bits),quant_uniform(w3,bits)
        elif mode=="lloyd":
            q1,q2,q3=quant_lloyd(w1,bits),quant_lloyd(w2,bits),quant_lloyd(w3,bits)
        elif mode=="awq-uniform":
            a1,sc1=awq_scale(w1,s_in,alpha); a3,sc3=awq_scale(w3,s_in,alpha); a2,sc2=awq_scale(w2,s_mid,alpha)
            q1=quant_uniform(a1,bits)/sc1[None,:]; q3=quant_uniform(a3,bits)/sc3[None,:]; q2=quant_uniform(a2,bits)/sc2[None,:]
        elif mode=="awq-lloyd":
            a1,sc1=awq_scale(w1,s_in,alpha); a3,sc3=awq_scale(w3,s_in,alpha); a2,sc2=awq_scale(w2,s_mid,alpha)
            q1=quant_lloyd(a1,bits)/sc1[None,:]; q3=quant_lloyd(a3,bits)/sc3[None,:]; q2=quant_lloyd(a2,bits)/sc2[None,:]
        Yq=expert_out(q1,q2,q3,X)
        coss.append(cos(Yq,Yref))
    return np.mean(coss)

print(f"\n{'bits':>4} | {'uniform':>9} {'lloyd':>9} | {'awq-unif':>9} {'awq-lloyd':>9}")
for bits in (2,3,4):
    u=eval_quant(bits,"uniform"); l=eval_quant(bits,"lloyd")
    au=eval_quant(bits,"awq-uniform"); al=eval_quant(bits,"awq-lloyd")
    print(f"{bits:>4} | {u:>9.5f} {l:>9.5f} | {au:>9.5f} {al:>9.5f}")
print("\nOUTPUT cosine (full swiglu) on real acts. If awq-* beats lloyd at same bits,")
print("activation-aware conversion is a NEW lever beyond the ~1.2x weight-fidelity ceiling.")
