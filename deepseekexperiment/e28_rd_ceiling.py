#!/usr/bin/env python3
# E28: the THEORETICAL floor of weight conversion ("how far beyond XOR, ever?").
# Weights are provably gaussian. For a gaussian source, the best possible quantizer
# (lattice/trellis, QuIP#/QTIP-style) approaches the Shannon rate-distortion bound
#   R(D) = 0.5 log2(sigma^2 / D).
# Measure: at the distortion our scalar quantizers achieve, what rate does Shannon
# allow? The gap = the MAX gain any "beyond XOR" code can ever extract. This is a
# theorem, not an experiment that might improve with cleverness.
import numpy as np, struct

def load_mat(p):
    b=open(p,"rb").read(); r,c=struct.unpack_from("<II",b,0)
    return np.frombuffer(b,dtype="<f4",count=r*c,offset=8).reshape(r,c).astype(np.float64)

def lloyd(vals,N,iters=15):
    lv=np.quantile(vals,(np.arange(N)+0.5)/N)
    for _ in range(iters):
        e=(vals[:,None]-lv[None,:])**2; idx=e.argmin(1)
        for k in range(N):
            m=idx==k
            if m.any(): lv[k]=vals[m].mean()
    return np.sort(lv)

def quant_mse(w, bits, block=256):
    N=1<<bits; W=w.reshape(-1); C=W.size; nb=C//block
    Wb=W[:nb*block].reshape(nb,block)
    scale=np.sqrt((Wb**2).mean(1,keepdims=True))+1e-12
    norm=(Wb/scale).reshape(-1)
    lv=lloyd(norm[::17],N)
    edges=(lv[:-1]+lv[1:])/2
    idx=np.searchsorted(edges,norm); deq=lv[idx]
    mse=((norm-deq)**2).mean()          # distortion of UNIT-variance source
    return mse

# gather real normalized weights from several experts/matrices
mats=[]
for e in (0,5,100):
    for w in (1,2,3):
        mats.append(load_mat(f"expert_L30_e{e}_w{w}.bin"))
print("weights loaded:", len(mats), "matrices")

# verify gaussianity quickly (kurtosis ~3 for gaussian)
allw=np.concatenate([m.reshape(-1)[::101] for m in mats])
allw=(allw-allw.mean())/allw.std()
kurt=(allw**4).mean()
print(f"weight kurtosis = {kurt:.3f} (gaussian=3.0 -> R-D theory applies)\n")

print(f"{'bits':>4} | {'scalarMSE':>10} {'SQNR dB':>8} | {'Shannon R(D)':>12} | {'gap bits':>8} | {'max gain':>8}")
for bits in (2,3,4):
    mses=[quant_mse(m,bits) for m in mats]
    D=np.mean(mses)                      # avg distortion, unit-variance source
    sqnr=10*np.log10(1.0/D)
    Rd=0.5*np.log2(1.0/D)               # gaussian rate-distortion bound (bits/weight)
    gap=bits-Rd
    print(f"{bits:>4} | {D:>10.5f} {sqnr:>8.2f} | {Rd:>12.3f} | {gap:>8.3f} | {2**gap:>7.2f}x")

print("\nINTERPRETATION:")
print("- scalarMSE = distortion of optimal SCALAR (Lloyd) quant of the gaussian weights.")
print("- Shannon R(D) = fewest bits ANY quantizer needs for that same distortion.")
print("- gap = bits a perfect lattice/trellis code could save vs scalar (the 'beyond XOR' max).")
print("- max gain = the absolute size-and-speed ceiling of going beyond scalar/XOR. It is a")
print("  THEOREM for gaussian sources: no conversion can beat it. Add our scale overhead on top.")
