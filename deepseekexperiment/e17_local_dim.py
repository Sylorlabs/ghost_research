# E17: is a SINGLE context's per-layer activation manifold low-dim enough that
# a ~0.8MB local surrogate could replace a 27MB expert? Compare single-context
# vs pooled per-layer effective rank. Data: ACT_DUMP files already on disk.
import numpy as np, struct, sys
rec = 8 + 7168*4
def load(path):
    raw = open(path,'rb').read()
    a = np.frombuffer(raw, dtype=np.uint8).reshape(-1, rec)
    layer = a[:, :4].view(np.uint32).reshape(-1)
    x = a[:, 8:].view(np.float32).reshape(-1, 7168)
    return layer, x
out = open("e17_results.txt","w")
def log(s): print(s); out.write(s+"\n"); out.flush()

L8, X8 = load("acts_T128_off8000.bin")     # context A (CLAUDE.md)
L21, X21 = load("acts_T128_off21601.bin")  # context B (wiki)
log(f"E17 local dimensionality: ctxA={X8.shape} ctxB={X21.shape}")

def eff_rank(M, q=0.90):
    M = M - M.mean(0)
    s = np.linalg.svd(M, compute_uv=False)
    en = np.cumsum(s**2)/np.sum(s**2)
    return np.searchsorted(en, q)+1

log("\nper-layer effective rank (dims for 90% energy):")
log(f"{'layer':>5} {'ctxA(128v)':>11} {'ctxB(128v)':>11} {'pooled(256v)':>13}")
ranks_a, ranks_pool = [], []
for L in sorted(set(L8.tolist()))[::8]:
    a = X8[L8==L]; b = X21[L21==L]
    if len(a) < 10: continue
    ra = eff_rank(a); rb = eff_rank(b)
    pooled = np.vstack([a,b]); rp = eff_rank(pooled)
    ranks_a.append(ra); ranks_pool.append(rp)
    log(f"{L:>5} {ra:>11} {rb:>11} {rp:>13}")
log(f"\nmean single-context rank {np.mean(ranks_a):.0f} vs pooled {np.mean(ranks_pool):.0f} (cap is #vectors: 128 / 256)")
# surrogate size implication
d = np.mean(ranks_a)
sz = d*3072*4/1e6
log(f"\nif a local surrogate = rank-{d:.0f} projection -> {sz:.2f}MB/expert (vs 27MB P3, target <=0.8MB)")
log(f"working set 250 exp/layer x 58 layers x {sz:.2f}MB = {250*58*sz/1000:.1f}GB in RAM (target <=12GB)")
log("CAVEAT: 128 vectors cap measurable rank at 128; a real long session has more tokens, so true single-context rank may be higher. This is a lower-bound probe; the route-dump + more tokens refine it.")
out.close(); print("E17 DONE")
