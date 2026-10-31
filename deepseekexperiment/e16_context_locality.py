# E16: the cold-token-fraction / context-locality measurement.
# THE key unmeasured quantity: during coherent single-context inference, what
# fraction of tokens actually require a COLD expert fetch (one not in a
# realistic RAM cache)? The 0.23 tps floor assumes this is ~1.0. If a single
# coherent context reuses a small, cacheable expert set, the floor moves.
#
# Input: ROUTE_DUMP from ppl_stack_route — records [layer u32, tok u32,
# 6x u32 expert ids] for the ref stream, score layers only.
import numpy as np, sys, struct
src = sys.argv[1] if len(sys.argv) > 1 else "route_off8000.bin"
out = open(sys.argv[2] if len(sys.argv) > 2 else "e16_results.txt", "w")
def log(s): print(s); out.write(s+"\n"); out.flush()

raw = open(src, "rb").read()
rec = (2 + 6) * 4
arr = np.frombuffer(raw, dtype=np.uint32).reshape(-1, 8)
layers = sorted(set(arr[:, 0].tolist()))
ntok = int(arr[:, 1].max()) + 1
log(f"E16 context-locality: {src}  score-layers={len(layers)}  tokens={ntok}")

# Per layer: build [ntok, 6] routing; simulate LRU cache of capacity C over the
# token sequence (decode order). Measure cold fetches/token and the fraction of
# tokens needing >=1 cold fetch. Also working-set growth (cumulative unique).
def lru_sim(route, C):
    # route: [ntok,6] expert ids; returns (cold_per_tok mean, frac_tokens_cold)
    cache = {}  # eid -> last-use clock
    clock = 0
    cold = np.zeros(len(route))
    for t in range(len(route)):
        c = 0
        for e in route[t]:
            e = int(e)
            if e in cache:
                cache[e] = clock
            else:
                c += 1
                if len(cache) >= C:
                    victim = min(cache, key=cache.get)
                    del cache[victim]
                cache[e] = clock
            clock += 1
        cold[t] = c
    return cold.mean(), (cold > 0).mean()

# aggregate across layers
for C in (32, 64, 96, 128, 192, 256, 384):
    cold_means, frac_cold = [], []
    ws_sat = []
    for L in layers:
        r = arr[arr[:, 0] == L][:, 2:]
        cm, fc = lru_sim(r, C)
        cold_means.append(cm); frac_cold.append(fc)
    log(f"  cache cap {C:3d}/layer: mean cold experts/token = {np.mean(cold_means):.3f} (of 6)  |  tokens needing >=1 cold fetch = {100*np.mean(frac_cold):.1f}%  ->  effective fetch vs uncached = {np.mean(cold_means)/6*100:.0f}%")

# working-set saturation: cumulative unique experts vs token position (layer-mean)
log("\nworking-set growth (cumulative unique experts/layer vs token count, layer-mean of 384):")
for upto in (16, 32, 64, 128, 256):
    if upto > ntok: break
    us = []
    for L in layers:
        r = arr[arr[:, 0] == L][:upto, 2:]
        us.append(len(np.unique(r)))
    log(f"  first {upto:3d} tokens: {np.mean(us):.0f} unique experts/layer ({100*np.mean(us)/384:.0f}% of 384)")

# the headline number
cm128, fc128 = [], []
for L in layers:
    r = arr[arr[:, 0] == L][:, 2:]
    cm, fc = lru_sim(r, 128)
    cm128.append(cm); fc128.append(fc)
log(f"\nHEADLINE (cap-128 RAM cache, coherent context): cold-token fraction = {100*np.mean(fc128):.0f}%, mean cold experts/token = {np.mean(cm128):.2f}/6")
log(f"=> if this holds, per-token fetch shrinks to ~{np.mean(cm128)/6*100:.0f}% of the uncached 9-11GB, i.e. ~{np.mean(cm128)/6*10:.1f}GB/token single-stream")
out.close(); print("E16 DONE")
