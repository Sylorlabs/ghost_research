#!/bin/bash
# Spec-decode draft acceptance: cheap-draft top-1 agreement vs f32 full model.
# Each = full 61-layer forward, T=64 held-out (offset 8000). ~30 min each.
# args: ntok max_layers offset cache eps threads topk_use freq_topn gplanes
cd /home/micah/Desktop/Sylorlabs/ghost_research/deepseekexperiment
echo "RUN START $(date)"
echo "===== DRAFT A: topk=0 (shared-expert only, FULLY RAM-RESIDENT) ====="
./ppl_stack 64 61 8000 0 0 10 0 6 3 2>&1 | tail -6
echo "===== DRAFT B: topk=1 (top-1 routed expert, 1/6 fetch) ====="
./ppl_stack 64 61 8000 0 0 10 1 6 3 2>&1 | tail -6
echo "===== DRAFT C: gplanes=1 (P1 weights, ~1/3.4 fetch) ====="
./ppl_stack 64 61 8000 0 0 10 6 6 1 2>&1 | tail -6
echo "===== REFERENCE: full P3 (topk=6, P3) — the deployable verifier ====="
./ppl_stack 64 61 8000 0 0 10 6 6 3 2>&1 | tail -6
echo "RUN DONE $(date)"
