# Span/consecutive expert locality on COHERENT text (gates MTP + span-batching).
# Input: ROUTE_DUMP [layer u32, tok u32, 6 expert ids], score layers only.
import numpy as np, sys
src=sys.argv[1] if len(sys.argv)>1 else "route_coherent.bin"
arr=np.frombuffer(open(src,'rb').read(),dtype=np.uint32).reshape(-1,8)
layers=sorted(set(arr[:,0].tolist())); ntok=int(arr[:,1].max())+1
out=open("span_locality_results.txt","w")
def log(s): print(s); out.write(s+"\n"); out.flush()
log(f"span locality (COHERENT text): {src}, score-layers={len(layers)}, tokens={ntok}")
# consecutive-span union: over K consecutive tokens, distinct experts / (K*6)
for K in (1,2,4,8,16):
    amort=[]
    for L in layers:
        r=arr[arr[:,0]==L][:,2:]
        for i in range(0, len(r)-K+1, K):
            u=set()
            for j in range(K): u|=set(r[i+j].tolist())
            amort.append(K*6/len(u))
    if amort: log(f"  K={K:2d} consecutive: fetch amortization {np.mean(amort):.2f}x (union {K*6/np.mean(amort):.1f} of {K*6})")
# consecutive-pair overlap
ov=[]
for L in layers:
    r=arr[arr[:,0]==L][:,2:]
    for i in range(1,len(r)): ov.append(len(set(r[i-1])&set(r[i]))/6.0)
log(f"consecutive-pair overlap: {np.mean(ov):.2f}")
# session working set: distinct experts over the whole stream, per layer
ws=[len(np.unique(arr[arr[:,0]==L][:,2:])) for L in layers]
log(f"session working set: {np.mean(ws):.0f} distinct experts/layer over {ntok} coherent tokens (of 384)")
log(f"  -> if cached, that's {np.mean(ws)*58*27/1000:.0f}GB/layer-set; RAM holds ~{16000/(58*27):.0f}/layer")
out.close(); print("DONE")
