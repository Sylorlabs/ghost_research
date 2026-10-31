#!/usr/bin/env python3
# "Steal a transformer": measure a pretrained GPT-2's bits-per-BYTE on a held-out text — the fair, tokenization-agnostic
# capability metric to compare against our no-LLM rune stack. CPU only. Sliding window so every scored token has full
# context. Also reports next-token top-1 (in GPT-2 tokens, not directly comparable to next-rune — BPB is the fair number).
import sys, math, torch
from transformers import GPT2LMHeadModel, GPT2TokenizerFast

MODEL = sys.argv[1] if len(sys.argv) > 1 else "gpt2"
PATH = sys.argv[2] if len(sys.argv) > 2 else "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/heldout_eval.txt"
CTX, STRIDE = 1024, 512

text = open(PATH, "rb").read().decode("utf-8", errors="replace")
nbytes = len(text.encode("utf-8"))
tok = GPT2TokenizerFast.from_pretrained(MODEL)
model = GPT2LMHeadModel.from_pretrained(MODEL).eval()
torch.set_grad_enabled(False)

ids = tok(text, return_tensors="pt").input_ids[0]
n = ids.shape[0]
print(f"model={MODEL}  bytes={nbytes}  gpt2_tokens={n}  ({nbytes/n:.2f} bytes/token)")

total_nll = 0.0   # natural-log loss summed over scored tokens
hits = 0
scored = 0
prev = 0
for begin in range(0, n, STRIDE):
    end = min(begin + CTX, n)
    window = ids[begin:end].unsqueeze(0)
    logits = model(window).logits[0]              # [L, V]
    # score the tokens whose target index is beyond what the last window already scored (no double counting)
    lo = max(prev - begin, 0)                      # first target position within this window to score
    for t in range(lo, end - begin - 1):
        logp = torch.log_softmax(logits[t], dim=-1)
        tgt = window[0, t + 1].item()
        total_nll += -logp[tgt].item()
        if int(torch.argmax(logits[t]).item()) == tgt:
            hits += 1
        scored += 1
    prev = end
    if end == n:
        break

bits = total_nll / math.log(2)
print(f"scored_tokens={scored}  next-token top1={100*hits/max(1,scored):.1f}%")
print(f"BITS-PER-BYTE (BPB) = {bits/nbytes:.4f}   (lower = better; this is the fair cross-tokenization metric)")
print(f"   (= {bits/scored:.3f} bits/token, perplexity {math.exp(total_nll/max(1,scored)):.1f})")
