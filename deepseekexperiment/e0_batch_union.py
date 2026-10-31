#!/usr/bin/env python3
"""E0: batch union-saturation test (strategy doc §Experiment 0).

Decode B independent slices of stream_tokens.bin in lockstep; per score layer
measure |union of routed experts| at each token step vs B*6.

Input: one or more ROUTE_DUMP binaries from ppl_stack_route (ref stream, score
layers only). Each file = one independent sequence (offset baked into capture).
Records: [layer u32, tok u32, 6 x u32 expert ids].

Verdict:
  GRADUATE if mean per-step union << B*6 and saturates toward ~384 at modest B.
  DIE if per-step union ~ B*6 (disjoint routing -> batching buys nothing).

Usage:
  python3 e0_batch_union.py route_e0_B8_off8000.bin route_e0_B8_off8128.bin ...
  python3 e0_batch_union.py --batch 8 route_e0_B8_*.bin
"""
import argparse
import glob
import sys
import numpy as np

TOPK = 6
N_EXPERTS = 384
N_HASH = 3


def load_route(path):
    raw = open(path, "rb").read()
    arr = np.frombuffer(raw, dtype=np.uint32).reshape(-1, 2 + TOPK)
    return arr


def lockstep_unions(dumps):
    """Per-layer lockstep union sizes across independent sequences."""
    layers = sorted(set(int(x) for d in dumps for x in d[:, 0]))
    ntok = min(int(d[:, 1].max()) + 1 for d in dumps)
    B = len(dumps)
    worst = B * TOPK

    per_layer = {}
    all_step = []
    for L in layers:
        if L < N_HASH:
            continue
        step_unions = []
        for t in range(ntok):
            u = set()
            for d in dumps:
                rows = d[(d[:, 0] == L) & (d[:, 1] == t)]
                if len(rows) != 1:
                    continue
                u |= set(rows[0, 2:].tolist())
            if u:
                step_unions.append(len(u))
                all_step.append(len(u))
        if step_unions:
            per_layer[L] = {
                "mean": float(np.mean(step_unions)),
                "max": int(np.max(step_unions)),
                "p50": float(np.median(step_unions)),
                "steps": len(step_unions),
            }

    # layer-aggregate union (full pass, matches ppl_stack works.count semantics)
    layer_total = {}
    for L in layers:
        if L < N_HASH:
            continue
        u = set()
        for d in dumps:
            rows = d[d[:, 0] == L]
            for row in rows:
                u |= set(row[2:].tolist())
        layer_total[L] = len(u)

    return {
        "B": B,
        "ntok": ntok,
        "worst_per_step": worst,
        "per_layer_step": per_layer,
        "per_layer_total": layer_total,
        "all_step_mean": float(np.mean(all_step)) if all_step else 0.0,
        "all_step_max": int(np.max(all_step)) if all_step else 0,
    }


def tps_implication(B, mean_union_per_step, n_score=58, expert_mb=25.6, bw_gbs=1.08):
    """Aggregate tps if fetch-bound: B tokens/step, union experts fetched once."""
    bytes_per_step = mean_union_per_step * n_score * expert_mb * 2**20
    sec_per_step = bytes_per_step / (bw_gbs * 2**30)
    return B / sec_per_step


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("routes", nargs="*", help="route dump binaries")
    ap.add_argument("--batch", type=int, default=0)
    ap.add_argument("--glob", dest="glob_pat", default="")
    args = ap.parse_args()

    paths = list(args.routes)
    if args.glob_pat:
        paths.extend(sorted(glob.glob(args.glob_pat)))
    paths = sorted(set(paths))
    if not paths:
        print("usage: e0_batch_union.py route1.bin route2.bin ...", file=sys.stderr)
        sys.exit(1)

    dumps = [load_route(p) for p in paths]
    r = lockstep_unions(dumps)
    B = r["B"]
    worst = r["worst_per_step"]
    sat = r["all_step_mean"] / worst if worst else 0.0

    print(f"E0 batch union-saturation: B={B} independent slices, T={r['ntok']} lockstep tokens")
    print(f"  per-step union: mean={r['all_step_mean']:.1f}  max={r['all_step_max']}  vs B*6={worst}")
    print(f"  saturation ratio (mean / B*6): {sat:.3f}  |  1.0=die(disjoint)  ~{N_EXPERTS/worst:.2f}=full saturate")
    print(f"  projected aggregate tps (NTFS 1.08GB/s, P3 25.6MB/expert, union mean): "
          f"{tps_implication(B, r['all_step_mean']):.2f}")

    print("\nper-layer sample (lockstep mean | layer-total union):")
    for L in sorted(r["per_layer_step"]):
        if L < N_HASH or L % 5 != 3 and L not in (3, 10, 30, 50, 60):
            continue
        s = r["per_layer_step"][L]
        tot = r["per_layer_total"][L]
        print(f"  L{L:02d}: step_mean={s['mean']:.1f} step_max={s['max']} "
              f"| layer_total={tot} ({100*tot/N_EXPERTS:.0f}% of 384)")

    # verdict
    if sat > 0.85:
        verdict = "DIE"
        reason = f"union ~ B*6 ({sat:.0%} of worst-case) — batching buys almost nothing"
    elif r["all_step_mean"] < N_EXPERTS * 0.5 and sat < 0.6:
        verdict = "GRADUATE"
        reason = (f"union saturates well below B*6 (mean {r['all_step_mean']:.0f} vs {worst}); "
                  f"batch amortization lever is alive")
    else:
        verdict = "GRADUATE (partial)"
        reason = f"union between extremes — batching helps ~{1/sat:.1f}x at this B"

    print(f"\nVERDICT: {verdict}")
    print(f"  {reason}")
    return 0 if verdict.startswith("GRADUATE") else 1


if __name__ == "__main__":
    sys.exit(main())