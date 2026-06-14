#!/usr/bin/env python3
# FAIR fight: a small byte-level GPT trained FROM SCRATCH on the SAME corpus our count model uses (no billion-token
# pretraining). Same de-wrapped Austen held-out, same metric: BITS-PER-BYTE. Equal data, equal playing field. CPU.
import sys, math, time, torch, torch.nn as nn, torch.nn.functional as F

TRAIN = sys.argv[1] if len(sys.argv) > 1 else "../corpus/train_dw_8mb.txt"
HELD = sys.argv[2] if len(sys.argv) > 2 else "../corpus/heldout_eval_dw.txt"
STEPS = int(sys.argv[3]) if len(sys.argv) > 3 else 3000
BLOCK, NEMB, NLAYER, NHEAD, BATCH = 128, 192, 4, 6, 32
torch.manual_seed(0)
torch.set_num_threads(torch.get_num_threads())

data = torch.tensor(list(open(TRAIN, "rb").read()), dtype=torch.long)
held = torch.tensor(list(open(HELD, "rb").read()), dtype=torch.long)
print(f"train {len(data)} bytes  held-out {len(held)} bytes  model: {NLAYER}L/{NEMB}d/{NHEAD}h block {BLOCK}")

class Block(nn.Module):
    def __init__(s):
        super().__init__()
        s.ln1, s.ln2 = nn.LayerNorm(NEMB), nn.LayerNorm(NEMB)
        s.attn = nn.MultiheadAttention(NEMB, NHEAD, batch_first=True)
        s.mlp = nn.Sequential(nn.Linear(NEMB, 4 * NEMB), nn.GELU(), nn.Linear(4 * NEMB, NEMB))
    def forward(s, x, mask):
        h = s.ln1(x)
        a, _ = s.attn(h, h, h, attn_mask=mask, need_weights=False)
        x = x + a
        return x + s.mlp(s.ln2(x))

class GPT(nn.Module):
    def __init__(s):
        super().__init__()
        s.tok = nn.Embedding(256, NEMB)
        s.pos = nn.Embedding(BLOCK, NEMB)
        s.blocks = nn.ModuleList([Block() for _ in range(NLAYER)])
        s.lnf = nn.LayerNorm(NEMB)
        s.head = nn.Linear(NEMB, 256, bias=False)
    def forward(s, idx):
        T = idx.size(1)
        x = s.tok(idx) + s.pos(torch.arange(T, device=idx.device))
        mask = torch.triu(torch.full((T, T), float("-inf")), 1)
        for b in s.blocks:
            x = b(x, mask)
        return s.head(s.lnf(x))

model = GPT()
print(f"params: {sum(p.numel() for p in model.parameters())/1e6:.2f}M")
opt = torch.optim.AdamW(model.parameters(), lr=3e-4, weight_decay=0.1)

def get_batch():
    ix = torch.randint(0, len(data) - BLOCK - 1, (BATCH,))
    x = torch.stack([data[i:i + BLOCK] for i in ix])
    y = torch.stack([data[i + 1:i + 1 + BLOCK] for i in ix])
    return x, y

@torch.no_grad()
def eval_bpb():
    model.eval()
    nll = 0.0
    n = 0
    stride = BLOCK // 2
    prev = 0
    i = 0
    while i < len(held) - 1:
        end = min(i + BLOCK, len(held))
        win = held[i:end].unsqueeze(0)
        logits = model(win)[0]
        lo = max(prev - i, 0)
        for t in range(lo, end - i - 1):
            lp = F.log_softmax(logits[t], -1)
            nll += -lp[held[i + t + 1]].item()
            n += 1
        prev = end
        if end == len(held):
            break
        i += stride
    model.train()
    return (nll / math.log(2)) / len(held), n

t0 = time.time()
for step in range(1, STEPS + 1):
    x, y = get_batch()
    logits = model(x)
    loss = F.cross_entropy(logits.reshape(-1, 256), y.reshape(-1))
    opt.zero_grad(); loss.backward(); opt.step()
    if step % 250 == 0 or step == STEPS:
        bpb, n = eval_bpb()
        print(f"step {step:5d}  train-loss(bits/byte) {loss.item()/math.log(2):.3f}  HELD-OUT BPB {bpb:.4f}  ({time.time()-t0:.0f}s)")
print("DONE. The fair number is the final HELD-OUT BPB above (equal data vs our count model on the same corpus).")
