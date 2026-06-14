# Replacing attention (not piggybacking): hashed content-addressing as O(n) soft routing

Goal (Micah, 2026-06-14): a *research-grade replacement* for attention, not another method that piggybacks on it.
Attention is expensive (O(n²) compute, O(n) memory) and has known issues; the field's "replacements" (linear attention,
SSMs/Mamba, RWKV, Hyena) are still **learned, GPU-trained** sequence mixers. We want something that fits this stack:
rune-native, CPU, no GPU, no LLM — and is a genuinely different mechanism.

## The decomposition (what attention actually does)

Attention = **content-based soft routing**: each position gathers information from earlier positions, weighted by
similarity. Three parts: (1) **compare** query to every key, (2) **softmax weight**, (3) **aggregate** values. The
**O(n²) lives entirely in (1)** — all-pairs comparison. And the reason attention *needs* learned all-pairs dot products
is that transformer tokens are **dense, address-less embeddings**: to find what's relevant you must compute similarity
against everything.

**Our structural advantage:** we don't have address-less tokens. We have **discrete discovered runes** — they already
*are* addresses. So content routing need not be all-pairs; it can be a **hashed lookup**. Three ways to route to context:

| route | mechanism | cost | learns? |
|---|---|---|---|
| **exact address** | the n-gram (key = last runes) | O(1) lookup, but **sparse** (dies on long context) | no |
| **soft via softmax** | **attention** (all-pairs QK + softmax) | **O(n²)·D**, learned Q/K/V | yes |
| **soft via hashing** | **our candidate**: LSH-bucket the recent-context embedding → similar contexts share a bucket → shared next-rune evidence | **O(n)**, O(1) query, memory = #buckets | no |

The bet: **hashing gets attention's generalization-over-context at the n-gram's cost** — no softmax, no learned Q/K, no n².

## Probe 1 — `attention_replacement.zig` (`zig build attention-replacement`, ~5s)

Race exact n-gram vs a real single-head softmax self-attention (learned Wq/Wk/Wv + readout, full backprop, *not* a
strawman) vs hash-routing, on next-rune over forged runes (Austen/Melville/Shakespeare/Tolstoy), **position-based split
(no leakage)**, **frozen PPMI embeddings for every model** (symmetric handicap). D=48, W=16, NRC=400.

### Results (next-rune top-1, held-out)

| model | overall | unseen-by-n-gram slice | cost |
|---|---:|---:|---|
| A exact n-gram (order-2) | **7.9%** | 0% (by construction) | O(1), no learning |
| B softmax attention (1 head) | 1.9% | 2.1% | learned QKV, 5159 ms train |
| C hash-routing (14 bits) | 2.6% | 2.5% | **no learning, 11 ms build** |
| **A+B** n-gram + attention | 9.1% | — | learned |
| **A+C** n-gram + hash-routing | **9.4%** | — | **O(n), zero learned params** |

- **Exact local memorization dominates next-rune** (7.9% ≫ both soft routers). Soft routing only matters where the
  n-gram is blind (the unseen slice).
- **On the unseen slice — where soft routing *is* the task — hash (2.5%) ≥ the attention head (2.1%).**
- **The practical hybrid** (exact where seen + soft where unseen): n-gram+hash **9.4%** ≥ n-gram+attention 9.1%, both
  above the n-gram's 7.9% — and the hash hybrid is O(n) with **no learned parameters**.
- **Cost** is the headline: attention scales n²·D, hash scales n·PBITS·D → a measured **1170× gap at n=16384**, and hash
  memory is **context-length independent**. This run: 11 ms to build hash vs 5159 ms to train one attention head.

### Honest scope
- One attention head + frozen embeddings — **not a full transformer** (no multi-head, multi-layer, FFN, learned
  embeddings). But the comparison is **fair** (every model gets the same frozen embeddings) and the **cost asymptotics
  are per-head**, so they hold under multi-head/multi-layer.
- Absolute accuracies are low because next-rune over prose is hard and the substrate is tiny; the **relative** result
  (hash ≥ a single attention head at >100× less compute) is the claim.
- A cheap **learned** organ (the ReZero residual organ, `sigil_organ.zig`) still beats hash on the unseen slice
  (4.1% vs 2.5%), so the honest menu is: **hash-routing = zero-learning, O(n), cheapest; residual organ = cheap-learning,
  O(n), stronger**. Both beat a single attention head here.

## The decisive next test (probe 2): associative recall / induction

Next-rune over prose is dominated by local n-grams, so it under-tests routing. The benchmark the entire
attention-replacement field uses to separate **real** replacements from fakes is **associative recall / induction**:
the sequence contains `… a b … a ?` and the model must recall `b` by matching the earlier `a`. This is exactly where
**softmax attention shines** (sharp content-based retrieval) and **linear attention / SSMs struggle** (bounded state).
Our claim to test: **discrete rune addresses give exact-match recall** that should hold up where soft linear methods
fail. If hash/exact-address routing handles induction as well as softmax — and far better than a linear-attention
recurrence — that is the research-grade result. Probe 2 builds this synthetic task with perfect ground truth.

## Status
Probe 1 done, measured, committed. Open rungs: (2) induction/associative-recall benchmark, (3) linear-attention
recurrence baseline (the real O(n) competitor), (4) bucket-count / decay / key-construction sweeps, (5) a learned-metric
hash (cheap CPU projection trained contrastively) to lift the soft-routing accuracy toward the residual organ's.
