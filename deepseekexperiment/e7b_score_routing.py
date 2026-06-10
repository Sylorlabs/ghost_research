#!/usr/bin/env python3
"""E7b: score-layer routing analysis from the E4 stack run (e4_routing.csv).

Questions:
  - how concentrated is score-layer expert selection across tokens?
    (cross-token expert sharing => cache effectiveness for batch/sequence)
  - how much does routing diverge between ref and quant streams, by depth?
  - per-layer union size: experts needed for 8 tokens vs 48 worst-case
"""
import csv
from collections import defaultdict

rows = list(csv.DictReader(open("e4_routing_p3.csv")))
by_layer_stream = defaultdict(lambda: defaultdict(list))
for r in rows:
    by_layer_stream[int(r["layer"])][int(r["stream"])].append(
        (int(r["token"]), [int(r[f"e{i}"]) for i in range(6)]))

print("layer | uniq_ref (of 48 slots) | route_overlap ref-vs-quant | jaccard(ref experts, quant experts)")
tot_uniq, n_score = 0, 0
for layer in sorted(by_layer_stream):
    ref = by_layer_stream[layer][0]
    quant = by_layer_stream[layer][1]
    uniq_ref = set(e for _, es in ref for e in es)
    uniq_q = set(e for _, es in quant for e in es)
    ov = []
    qd = dict(quant)
    for tok, es in ref:
        ov.append(len(set(es) & set(qd[tok])) / 6)
    jac = len(uniq_ref & uniq_q) / len(uniq_ref | uniq_q)
    kind = "hash " if layer < 3 else "score"
    if layer >= 3:
        tot_uniq += len(uniq_ref)
        n_score += 1
    if layer < 6 or layer % 10 == 0 or layer >= 58:
        print(f"L{layer:02d} {kind} | {len(uniq_ref):2d} | {sum(ov)/len(ov):.2f} | {jac:.2f}")

print(f"\nscore layers mean unique experts per layer (8 tokens, 48 slots): {tot_uniq/max(n_score,1):.1f}")
print("=> cross-token sharing factor:", f"{48/(tot_uniq/max(n_score,1)):.2f}x")
