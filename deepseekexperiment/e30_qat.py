#!/usr/bin/env python3
# E30: per-expert QAT (Micah lifts no-retrain, but: FAST + NO new corpus).
# Optimize the QUANTIZED weights to preserve the expert's OUTPUT on activations we
# ALREADY captured (acts_T128.bin). Local (1 expert in RAM), fast (a few hundred steps),
# zero new data. Question: does output-aware fine-tuning recover low-bit (P2/P1) quality
# that naive quant loses? If yes -> fewer bits at full quality -> smaller+faster, beyond
# the weight-reconstruction Shannon bound (QAT exploits output-insensitive directions).
import numpy as np, struct, torch, sys
torch.manual_seed(0)
DIM=7168
def load_mat(p):
    b=open(p,"rb").read(); r,c=struct.unpack_from("<II",b,0)
    return torch.from_numpy(np.frombuffer(b,dtype="<f4",count=r*c,offset=8).reshape(r,c).copy())
def load_acts(p,layer):
    raw=open(p,"rb").read(); rec=8+DIM*4; n=len(raw)//rec; out=[]; off=0
    for _ in range(n):
        l,t=struct.unpack_from("<II",raw,off)
        if l==layer: out.append(np.frombuffer(raw,dtype="<f4",count=DIM,offset=off+8))
        off+=rec
    return torch.from_numpy(np.stack(out).copy())

def quant_ste(W, bits, block=256):
    r,c=W.shape; nb=c//block
    Wb=W[:,:nb*block].reshape(r,nb,block)
    if bits==1:
        scale=(Wb.detach().abs().mean(2,keepdim=True)+1e-12)
        q=(torch.sign(Wb)*scale).reshape(r,nb*block)
    else:
        qmax=(1<<(bits-1))-1
        scale=(Wb.detach().abs().amax(2,keepdim=True)/qmax+1e-12)
        q=(torch.round(Wb/scale).clamp(-qmax,qmax)*scale).reshape(r,nb*block)
    out=W.clone(); out[:,:nb*block]=W[:,:nb*block]+(q-W[:,:nb*block]).detach()  # STE
    return out

def swiglu(w1,w2,w3,X):
    g=X@w1.t(); u=X@w3.t(); h=torch.nn.functional.silu(g)*u; return h@w2.t()
def cos(a,b): a=a.reshape(-1);b=b.reshape(-1); return float((a@b)/(a.norm()*b.norm()+1e-30))

E=int(sys.argv[1]) if len(sys.argv)>1 else 0
w1=load_mat(f"expert_L30_e{E}_w1.bin"); w2=load_mat(f"expert_L30_e{E}_w2.bin"); w3=load_mat(f"expert_L30_e{E}_w3.bin")
X=load_acts("acts_T128.bin",30)
ntr=96; Xtr,Xte=X[:ntr],X[ntr:]
with torch.no_grad():
    Ytr=swiglu(w1,w2,w3,Xtr); Yte=swiglu(w1,w2,w3,Xte)
print(f"expert {E}: train {Xtr.shape[0]} tok, test {Xte.shape[0]} tok (held-out, same context)")
print(f"{'bits':>4} | {'naive in':>8} {'naive te':>8} | {'QAT in':>8} {'QAT te':>8} | {'recovered':>9}")
for bits in (1,2,3):
    # naive
    with torch.no_grad():
        q1=quant_ste(w1,bits); q2=quant_ste(w2,bits); q3=quant_ste(w3,bits)
        ni=cos(swiglu(q1,q2,q3,Xtr),Ytr); nte=cos(swiglu(q1,q2,q3,Xte),Yte)
    # QAT: learnable shadow weights, STE quant in forward, fit OUTPUT on train acts
    w1o,w2o,w3o=w1.clone(),w2.clone(),w3.clone()
    s1=w1.clone().requires_grad_(True); s2=w2.clone().requires_grad_(True); s3=w3.clone().requires_grad_(True)
    opt=torch.optim.Adam([s1,s2,s3],lr=8e-4)
    yscale=(Ytr**2).mean()
    for step in range(150):
        opt.zero_grad()
        out=swiglu(quant_ste(s1,bits),quant_ste(s2,bits),quant_ste(s3,bits),Xtr)
        reg=((s1-w1o)**2).mean()+((s2-w2o)**2).mean()+((s3-w3o)**2).mean()  # stay near init (anti-overfit)
        loss=((out-Ytr)**2).mean()/yscale + 0.5*reg
        loss.backward(); opt.step()
    with torch.no_grad():
        q1=quant_ste(s1,bits);q2=quant_ste(s2,bits);q3=quant_ste(s3,bits)
        qi=cos(swiglu(q1,q2,q3,Xtr),Ytr); qte=cos(swiglu(q1,q2,q3,Xte),Yte)
    print(f"{bits:>4} | {ni:>8.4f} {nte:>8.4f} | {qi:>8.4f} {qte:>8.4f} | {qte-nte:>+9.4f}")
print("\nQAT te > naive te (held-out) => fast no-new-corpus retrain recovers low-bit quality.")
print("Watch QAT-in vs QAT-te gap: large gap = overfitting the 128-token context (need diverse acts).")
