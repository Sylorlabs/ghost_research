#!/usr/bin/env python3
"""E0 hash-layer proxy: B independent token streams, lockstep union via tid2eid.

Score layers need full forward; hash layers 0-2 are deterministic from token id.
Quick upper/lower bound on batch diversity without model execution.
"""
import struct, json, sys
import numpy as np

WD = "/mnt/corpus/DeepSeek-V4-Pro"
TOPK = 6


def load_tid2eid(layer, shard):
    p = f"{WD}/model-{shard:05d}-of-00064.safetensors"
    with open(p, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        h = json.loads(f.read(n))
        name = f"layers.{layer}.ffn.gate.tid2eid"
        t = h[name]
        f.seek(8 + n + t["data_offsets"][0])
        raw = f.read(t["data_offsets"][1] - t["data_offsets"][0])
    return np.frombuffer(raw, dtype=np.int64).reshape(t["shape"])


def main():
    B = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    T = int(sys.argv[2]) if len(sys.argv) > 2 else 128
    base = int(sys.argv[3]) if len(sys.argv) > 3 else 8000

    toks = np.fromfile("stream_tokens.bin", dtype=np.uint32)
    tables = {L: load_tid2eid(L, L + 2) for L in range(3)}

    print(f"E0 hash proxy: B={B} T={T} base={base}")
    for L in range(3):
        unions = []
        for t in range(T):
            u = set()
            for b in range(B):
                off = base + b * T + t
                if off >= len(toks):
                    break
                u |= set(tables[L][toks[off]].tolist())
            unions.append(len(u))
        worst = B * TOPK
        print(f"  L{L}: lockstep mean union={np.mean(unions):.1f} max={max(unions)} vs {worst}")


if __name__ == "__main__":
    main()