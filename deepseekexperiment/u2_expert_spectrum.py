# U2: cross-expert shared structure — THE decisive experiment for 20 tps.
# Question: do the 384 routed experts of a layer share a low-dimensional
# row-space? If yes: store one shared basis (RAM-resident) + small per-expert
# coefficient matrices => storage and per-token bytes collapse by ~7168/k.
#
# Method (permutation-invariant): accumulate the row covariance C (7168x7168)
# over subsampled rows from TRAIN experts (0..299), eigendecompose, then
# measure held-out reconstruction error on TEST experts (350..383):
#   rel_err(k) = ||W - (W Bk^T) Bk||_F / ||W||_F   for k in grid.
# Honest control: random gaussian rows would give a flat spectrum
# (Marchenko-Pastur, q = 7168/n_rows ~ 0.047 -> tight bulk). Concentration
# far above that bulk = real shared structure.
import numpy as np, json, struct, os, sys, time

WD = next(d for d in ("/mnt/steamgames/DeepSeek-V4-Pro", "/mnt/corpus/DeepSeek-V4-Pro") if os.path.isdir(d))
FP4 = np.array([0, .5, 1, 1.5, 2, 3, 4, 6, -0, -.5, -1, -1.5, -2, -3, -4, -6], dtype=np.float32)
LAYER = int(sys.argv[1]) if len(sys.argv) > 1 else 30
MAT = sys.argv[2] if len(sys.argv) > 2 else "w1"
ROWS_PER_EXPERT = 512
TRAIN = range(0, 300)
TEST = range(350, 384)
KGRID = [128, 256, 512, 1024, 1536, 2048, 3072]

out = open(f"u2_spectrum_L{LAYER}_{MAT}.txt", "w")
def log(s):
    print(s); out.write(s + "\n"); out.flush()

path = f"{WD}/model-{LAYER + 2:05d}-of-00064.safetensors"
with open(path, "rb") as f:
    n = struct.unpack("<Q", f.read(8))[0]
    hdr = json.loads(f.read(n))
    base = 8 + n

def load_tensor(name):
    t = hdr[name]
    o0, o1 = t["data_offsets"]
    with open(path, "rb") as f:
        f.seek(base + o0)
        raw = f.read(o1 - o0)
    return np.frombuffer(raw, dtype=np.uint8).reshape(t["shape"])

def expert_mat(e):
    w = load_tensor(f"layers.{LAYER}.ffn.experts.{e}.{MAT}.weight")
    s = load_tensor(f"layers.{LAYER}.ffn.experts.{e}.{MAT}.scale")
    rows, bcols = w.shape
    W = np.empty((rows, bcols * 2), dtype=np.float32)
    W[:, 0::2] = FP4[w & 15]
    W[:, 1::2] = FP4[w >> 4]
    return W * np.repeat(np.exp2(s.astype(np.float32) - 127.0), 32, axis=1)

log(f"U2 spectrum: layer {LAYER}, {MAT}, {ROWS_PER_EXPERT} rows/expert, train={len(list(TRAIN))} test={len(list(TEST))}")
t0 = time.time()
DIM = expert_mat(0).shape[1]
C = np.zeros((DIM, DIM), dtype=np.float64)
rng = np.random.default_rng(7)
n_rows = 0
for e in TRAIN:
    W = expert_mat(e)
    idx = rng.choice(W.shape[0], min(ROWS_PER_EXPERT, W.shape[0]), replace=False)
    Xs = W[idx].astype(np.float64)
    C += Xs.T @ Xs
    n_rows += len(idx)
    if e % 50 == 0:
        log(f"  expert {e}  t={time.time()-t0:.0f}s")
log(f"covariance over {n_rows} rows done t={time.time()-t0:.0f}s; eigh...")
evals, evecs = np.linalg.eigh(C)
evals, evecs = evals[::-1], evecs[:, ::-1]
np.save(f"u2_basis_L{LAYER}_{MAT}.npy", evecs[:, :2048].astype(np.float32))
np.save(f"u2_evals_L{LAYER}_{MAT}.npy", evals)
tot = evals.sum()
cum = np.cumsum(evals) / tot
log(f"\nspectrum energy capture (train rows): ")
for k in KGRID:
    if k <= DIM:
        log(f"  top-{k:5d}: {100*cum[k-1]:6.2f}%")
# Marchenko-Pastur bulk edge for reference (flat-spectrum control)
q = DIM / n_rows
mean_ev = tot / DIM
log(f"MP control: q={q:.4f}, bulk edges ~ [{mean_ev*(1-q**.5)**2:.4g}, {mean_ev*(1+q**.5)**2:.4g}], top eigenvalue = {evals[0]:.4g} ({evals[0]/mean_ev:.1f}x mean)")

log(f"\nheld-out expert reconstruction (rel Frobenius error, experts 350..383):")
res = {k: [] for k in KGRID if k < DIM}
for e in TEST:
    W = expert_mat(e)
    nrm = np.linalg.norm(W)
    for k in res:
        B = evecs[:, :k].astype(np.float32)
        err = np.linalg.norm(W - (W @ B) @ B.T) / nrm
        res[k].append(err)
for k, v in res.items():
    log(f"  k={k:5d}: rel_err mean {np.mean(v):.4f}  (compression x{DIM/k:.1f} per expert)")
log(f"total time {time.time()-t0:.0f}s")
out.close()
print("U2 DONE")
