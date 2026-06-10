#!/usr/bin/env python3
"""E7: expert working-set + cache hit-rate on real token streams (hash layers).

Layers 0-2 of DeepSeek V4 Pro route deterministically: gate.tid2eid[token_id]
gives the 6 routed experts. So hash-layer expert traffic is computable from a
token stream alone, with zero model execution. Measures:
  - unique experts touched vs stream length (working set growth)
  - LRU cache hit rate vs cache capacity (per layer)
  - token-level reuse (consecutive-window overlap)
Also writes probe token ids for the E4/E9 stack experiment.
"""
import json, struct, sys
import numpy as np
from tokenizers import Tokenizer

WD = "/mnt/steamgames/DeepSeek-V4-Pro"

def load_tensor(shard, name):
    p = f"{WD}/model-{shard:05d}-of-00064.safetensors"
    with open(p, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        h = json.loads(f.read(n))
        t = h[name]
        f.seek(8 + n + t["data_offsets"][0])
        raw = f.read(t["data_offsets"][1] - t["data_offsets"][0])
    dt = {"I64": np.int64, "BF16": np.uint16, "F32": np.float32}[t["dtype"]]
    return np.frombuffer(raw, dtype=dt).reshape(t["shape"])

tok = Tokenizer.from_file(f"{WD}/tokenizer.json")

# real mixed text: model README + project docs (code + prose)
texts = []
for p in [f"{WD}/README.md",
          "/home/micah/Desktop/Sylorlabs/ghost_research/CLAUDE.md",
          "/home/micah/Desktop/Sylorlabs/ghost_research/ARCHITECTURE.md",
          "/mnt/steamgames/DeepSeek-V4-Pro/inference/model.py"]:
    try:
        texts.append(open(p, encoding="utf-8", errors="ignore").read())
    except FileNotFoundError:
        pass
stream = tok.encode("\n\n".join(texts)).ids
print(f"token stream: {len(stream)} tokens, {len(set(stream))} unique ids")

# probe tokens for E4/E9 (varied content)
probe = tok.encode("The derivative of x squared is 2x. def reverse(lst): return lst[::-1] # Paris is the capital of France").ids
np.array(probe, dtype=np.uint32).tofile("probe_tokens.bin")
np.array(stream, dtype=np.uint32).tofile("stream_tokens.bin")
print(f"probe tokens ({len(probe)}): {probe[:16]}...")

# hash-layer routing tables (layer L is in shard L+2)
for layer, shard in [(0, 2), (1, 3), (2, 4)]:
    t2e = load_tensor(shard, f"layers.{layer}.ffn.gate.tid2eid")
    seq = t2e[stream]  # [T, 6] expert ids per position

    uniq_curve = []
    seen = set()
    for i, row in enumerate(seq):
        seen.update(row.tolist())
        if i + 1 in (64, 256, 1024, 4096, len(seq)):
            uniq_curve.append((i + 1, len(seen)))
    print(f"\nlayer {layer}: working set growth {uniq_curve}")

    # LRU simulation at various capacities (of 384 experts)
    for cap in (32, 64, 128, 192, 256, 384):
        cache, order = set(), []
        hits = misses = 0
        for row in seq:
            for e in row.tolist():
                if e in cache:
                    hits += 1
                    order.remove(e)
                    order.append(e)
                else:
                    misses += 1
                    if len(cache) >= cap:
                        cache.discard(order.pop(0))
                    cache.add(e)
                    order.append(e)
        print(f"  LRU cap={cap:3d}: hit rate {hits/(hits+misses):.3f}")

    # consecutive-window overlap: of the 6 experts at position t, how many
    # were used in the previous W positions?
    for W in (8, 32, 128):
        overl = []
        for i in range(W, len(seq)):
            window = set(seq[i - W:i].flatten().tolist())
            overl.append(len(set(seq[i].tolist()) & window) / 6.0)
        print(f"  prev-{W}-token overlap: {np.mean(overl):.3f}")
