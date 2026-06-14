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

## Probe 2 — `induction_recall.zig` (`zig build induction-recall`, ~6s): the decisive capacity race

Next-rune over prose is dominated by local n-grams, so it under-tests routing. The benchmark the entire field uses to
separate **real** attention-replacements from fakes is **associative recall / induction**: store m (key→value) pairs,
then recall the value for a query key. This is attention's signature **in-context** skill (the "induction head"), and
exactly where **softmax shines** and **constant-state replacements (linear attention / SSMs) fail** (bounded state).

Four associative memories, **none learned** (fixed random embeddings → a clean *capacity* comparison), sweeping load m:
A exact discrete hash table · B softmax-as-memory (keep all keys) · C linear outer-product memory `M=Σkᵢ⊗vᵢ`
(the constant-state O(n) replacement) · D LSH address. D=64, VSYM=512, 16 LSH bits, 4000 trials/point.

### Results (recall accuracy vs load m)

| m | A exact | B softmax | C linear (const-state, ≈D=64) | D LSH(16b) |
|---:|---:|---:|---:|---:|
| 4–64 | 100% | 100% | 100% → 99.9% | ~100% |
| 96 | 100% | 100% | 99.1% | 99.5% |
| 128 | 100% | 100% | 97.1% | 99.6% |
| 192 | 100% | 100% | 85.4% | 99.3% |
| 256 | 100% | 100% | 72.2% | 99.1% |
| 384 | **100%** | **100%** | **48.5%** | **98.7%** |

- **A exact (discrete-rune address): 100% at every load**, O(1)/query, **unbounded capacity, no learning, no n².** This
  is precisely the induction head that attention spends O(n²) + training to acquire — discrete runes get it for free.
- **C linear / constant-state — the standard cheap "attention replacement" — collapses as m→D** (100%→48.5%): the
  bounded-state **capacity wall** the SSM literature warns about, reproduced. A fixed D×D state can't hold many bindings.
- **B softmax keeps full recall but pays O(m)** state/compute (24,576 muls/query at m=384) — that's attention's cost.
- **D LSH: O(1) like exact, holds ~99%** (collision-limited; more bits → more capacity).

### The conclusion (research-grade)
The induction head is just **content-addressed recall**. The cheap **continuous** replacements (linear/SSM) trade
**capacity for O(n)**; **discrete-rune addressing keeps BOTH — unbounded recall AND O(1) — because a rune is already an
address.** That is the structural lever every continuous attention-replacement misses, and it's native to this stack.

## Probe 3 — `induction_lm.zig` (`zig build induction-lm`, ~6s): the synthesis on real prose

Wire attention's two jobs into ONE **O(n) streaming** next-rune predictor on real prose (Austen/Melville/Shakespeare/
Tolstoy), **prequential** eval (predict-then-update online — leak-free by construction, and the project's continual-
learning setup). The induction memory is a recency/copy backoff: for orders K=8..2 keep `map[hash(last K runes)] = the
rune that LAST followed that context`; predict the longest match = "copy the continuation of the longest earlier context"
= an induction head as a streaming hashmap, O(1)/step. 600k runes streamed, 547k scored after warmup.

### Results (online next-rune top-1)

| model | overall | long-range slice (order≥5 repeat existed, 33k pos) |
|---|---:|---:|
| order-2 count n-gram | 17.1% | 38.7% |
| **induction recency-copy** | **17.8%** | **50.3%** |
| hash-routing soft | 2.0% | — |
| **combined O(n) stack** (long-copy ▸ count ▸ hash) | **18.5%** | 50.3% |

- **The induction-copy memory beats the count n-gram overall** (17.8 vs 17.1) and **by +11.6 points on the long-range
  slice** (50.3 vs 38.7) — exactly the repeated phrases/names the order-2 n-gram is structurally blind to. It reaches
  them at **O(1)/step**; attention would pay O(n²).
- **The combined stack (18.5%) beats the n-gram (17.1%)**, all O(n) streaming, updating online (continual learning, no
  forgetting), constant work per step.
- (Online prequential numbers run higher than probe 1's held-out split because the model accumulates stats over 547k
  positions and scores all runes, not the top-400; the relative ordering is the point.)

This is **attention's capability shape — long-range copy + soft routing — without its cost**: O(n), no learned Q/K, no
softmax, no n², and it learns as it streams.

## The thesis (three probes, measured)

Attention does two things: **soft content routing** and **sharp content recall (induction)**. Both cost O(n²) on
transformers because dense tokens are address-less. On a **discrete-rune** substrate, runes *are* addresses, so:
- soft routing → **hashed content-addressing** (probe 1): O(n), matches a single attention head, no learned Q/K;
- sharp recall → **exact addressing** (probe 2): O(1), **unbounded** capacity where the constant-state replacement
  (linear attention / SSM) craters at m≈D;
- together (probe 3): one **O(n) streaming** predictor that captures long-range copy + soft routing on real prose.

This is not piggybacking on attention — it's the observation that **attention's expensive all-pairs routing is a
workaround for not having addresses, and discrete runes already are addresses.** That is the research-grade lever, and
it's native to this no-GPU, no-LLM stack.

## Probe 4 — `sigil_router.zig` (`zig build sigil-router`, ~20s): beat attention's NUMBERS, sigil not softmax

Goal (Micah): better numbers — match/beat attention — and **use the sigil, never softmax**. Replace one expensive
attention router with a **committee of cheap O(1) routers**, combined by each router's **sigil reliability** (a
ResonanceEMA of its recent hit-rate), not a softmax. All online prequential on real prose, single-pass, 400k streamed.
Head-to-head **in the same stream** against the things to beat: an online **softmax self-attention** head (learned
Q/K/V + readout) and an online **linear-attention recurrence** (constant-state — rung 1's continuous competitor).

### Results (online next-rune top-1)

| router / baseline | top-1 | note |
|---|---:|---|
| count order-2 | 18.6% | reliab 0.22 |
| count order-3..6 | 9.4 / 4.0 / 1.9 / 1.0% | fire rarely but **reliability climbs with order** (0.48→0.70) |
| induction-copy | 18.0% | sharp recall |
| hash-routing | 3.6% | soft fallback |
| learned organ (sigil-trained) | 3.2% | neg-sampling, sigil surprise-weighted LR |
| **SOFTMAX attention (1 head)** | **2.6%** | the mechanism, with its softmax |
| **LINEAR attention (constant-state)** | **0.9%** | the standard O(n) replacement |
| **►► SIGIL ROUTER (committee)** | **20.1%** | **beats every router and both attention baselines** |
| SIGIL ROUTER + depth (layer 2) | 20.1% | no gain (honest) |

- **The committee (20.1%) beats the best single router (18.6%)** — a real ensemble win — and **beats softmax attention
  (2.6%) and linear attention (0.9%)** decisively, **with no softmax in our model**: the combiner is a sigil-reliability
  vote, the organ trains by sigil-surprise-weighted negative sampling.
- **Why it works:** the high-order count experts fire rarely but their **reliability climbs with order** (0.22→0.70), so
  the sigil-weighted vote leans on them *exactly when they speak* and falls back to order-2/induction otherwise.
- **Depth (rung 3) gave no gain.** A layer-2 corrector conditioned on (layer-1 guess ⊕ same context) is **circular** —
  it relearns what layer-1 already encodes. Genuine depth needs **features-of-features**, an open mechanism (reported,
  not hidden).

### Honest scope (critical)
The attention baselines are a **single head, online single-pass, frozen embeddings — the same budget as the committee**,
NOT a full trained transformer. So this is **"beats a single attention head at equal online CPU budget,"** not "beats
GPT." The real, defensible claims: (1) a sigil committee exceeds attention's number here at a fraction of the cost with
no softmax; (2) it strictly beats every cheap router it's built from; (3) it's O(1)/step, online, continual-learning.

## Probe 5 — `attn_verify.zig` (`zig build attn-verify`, ~30s): VERIFYING the multiple (and correcting it)

Micah asked to *verify the "15–20×" is true*. It interrogates the claim by **strengthening attention** as far as fair on
CPU — multi-head × multi-epoch, frozen PPMI embeddings, an **FFN** (real transformer block, not pool+linear), and
**scaled sinusoidal positional encoding** — on a clean offline held-out split, swept against the count/committee.

### Results (FROZEN held-out, no leakage)

| | top-1 |
|---|---:|
| count order-2 | 8.3% |
| committee (count backoff) | 8.6% |
| best attention (swept: 1–8 heads × 8–24 epochs, +FFN, +posenc) | **2.8%** |

**The "15–20×" was inflated.** Two corrections, both measured:
1. It bundled the committee's **continual-learning edge** (it adapts on the test stream; frozen attention can't) and
   compared to the **weakest** baseline (linear attention 0.9%). On a fair frozen split the multiple is **~3×**, not 15–20×.
2. **Even ~3× is not a clean capability KO.** My from-scratch CPU attention **cannot fit the training set above ~4%** in
   *any* config tried — so I **cannot certify it as a strong attention baseline**. A deep, well-optimized transformer
   (learned embeddings, many layers, Adam/warmup) would very likely beat counting at scale.

### What's true vs not (the honest verdict)
- **True / defensible:** at this tiny CPU scale, exact **counting out-predicts the attention I can train** (next-rune is
  memorization-heavy; counting is exact where pooling blurs), and the committee is **far cheaper (O(1)/O(n) vs O(n²)) and
  continually learning**.
- **Not proven:** that any of this beats a *real* transformer on raw capability. The honest headline is **"cheaper +
  continual + competitive at tiny scale,"** NOT "15–20× better than attention."
- Bugs/handicaps found and fixed during verification (each was making attention look artificially weak): no positional
  encoding (permutation-blind), positional encoding **swamping** content (scale mismatch with L2-normed embeddings),
  linear-only readout (added the FFN). After all fixes attention still plateaus ~2.8% — but the fact that it can't fit
  *train* means the bottleneck is **my CPU attention training**, not a proven structural defeat.

## Probe 6 — `hier_runes.zig` (`zig build hier-runes`, ~15s): DEPTH via composition (and it works)

The giant swing at the open frontier — **depth without attention**. Compose discovered units bottom-up: **bytes →
runes → phrases → concepts**, each level a *feature-of-features* (a phrase is a learned unit over runes, a concept over
phrases — three BPE levels). For each rune position we know the last **completed** phrase id and concept id (causal,
abstract, long-range context). Predict next-rune from a sigil committee of: rune order-2, rune order-3, **phrase-
conditioned**, **concept-conditioned**. Online prequential, 500k runes.

### Results (online next-rune top-1)

| expert | top-1 |
|---|---:|
| E0 rune order-2 | 23.4% |
| E1 rune order-3 | 13.1% |
| **E2 phrase-conditioned (level 2)** | **21.0%** |
| **E3 concept-conditioned (level 3)** | **20.2%** |
| rune-only committee (E0+E1) | 24.2% |
| **►► full hierarchical committee** | **26.9%** |

- **Depth helps: 24.2% → 26.9% (+2.7, +11% relative).** The abstract phrase/concept experts (21%, 20%) are nearly as
  strong as the local n-gram *on their own* and capture **different** signal, so combining lifts the committee.
- **Why this is real depth (unlike probe 4's circular stacking):** the higher levels are **genuinely different composed
  features**, not a re-conditioning on the same context. A phrase/concept is an abstraction *over* the runes — exactly
  the features-of-features a transformer's layers build, here by discrete composition, **O(1)/step, no attention, no
  softmax, no n².**
- **Causal:** the context is the *previous completed* phrase/concept (determined by runes strictly before the predicted
  position) — no future leakage.

This is the depth lever that was missing. It's the honest **positive** after probe 5's honest **negative** (the inflated
multiple): depth-by-hierarchy adds signal that flat counting can't reach, cheaply.

## Probe 7 — `hier_deep.zig` (`zig build hier-deep`, ~15s): push the depth (ablation ladder)

Pushed probe 6 further: **4 composed levels** (runes→phrases→concepts→super-concepts) + deeper local context (o2/o3/o4)
+ richer **joint couplings** (phrase×2-runes, concept×phrase) + long-range induction, as an **ablation ladder** that
shows the committee climbing rung by rung. Online prequential, 500k runes.

| rung (each adds a depth feature) | committee top-1 | Δ |
|---|---:|---:|
| rune o2 only | 23.4% | — |
| + deeper local (o3, o4) | 24.3% | +0.9 |
| **+ phrase (L2)** | **28.1%** | **+3.8** |
| + concept (L3) | 28.6% | +0.5 |
| + super (L4) | 28.3% | −0.3 |
| + induction (long-range) | 28.8% | +0.6 |

- **Depth climbs 23.4% → 28.8% (+5.4, +23% relative).** The **phrase level is the workhorse** (+3.8); the single expert
  `phrase(prevP, r1, r2)` scores 24.2% *alone* — beating the rune order-2 n-gram.
- **Honest saturation:** the 4th level (super-concept) gives **no gain** (−0.3). Depth-by-hierarchy pays off for ~3
  levels on this data/scale, then flattens — reported, not hidden.
- Each rung is a genuinely different *composed* feature, O(1)/step, no attention/softmax/n². The ladder localizes the
  depth: most of it is the phrase abstraction, a little more from concepts, then diminishing returns.

## Probe 8 — `lm_bpc.zig` + `gpt2_bpb.py`: vs a STOLEN GPT-2, the fair metric (bits-per-byte)

Instead of training a transformer (Micah: "steal one from HuggingFace"), we pull a pretrained **GPT-2** and compare on
**bits-per-byte (BPB)** — the tokenization-agnostic capability metric: whoever encodes the same held-out bytes in fewer
bits wins, regardless of token vs rune granularity. Held-out = a 172 KB **Austen** slice; our stack warm-starts on
Melville+Shakespeare+Tolstoy (**disjoint**) and the GPT-2 is frozen (pretrained on billions of tokens). Our model is an
interpolated hierarchical backoff (rune orders 1–5 + phrase + concept), CPU, tens of MB.

### Results (BPB, lower = better; same 172 KB held-out)

| model | BPB | notes |
|---|---:|---|
| **distilgpt2** (82M, frozen) | **2.0241** | pretrained on billions of tokens |
| our stack — **frozen** (warm-start only) | 2.2917 | raw transfer, no adaptation |
| our stack — **prequential** (continual) | **2.0551** | learns from the stream as it reads (our mode) |
| *gpt2* (124M, frozen) | *pending* | stronger baseline |

- **Raw frozen capability: the transformer wins** (distilgpt2 2.02 vs our 2.29, ~13%) — as expected; a real LM
  pretrained on billions of tokens out-transfers our 2 MB warm-start. **This is the honest "they're better at capability."**
- **With continual learning** (our cheap structural advantage — the count tables adapt to Austen as they read it), the
  gap nearly closes: **our 2.0551 vs distilgpt2 2.0241 (~1.5%)** — *a tiny CPU, no-GPU, no-LLM, tens-of-MB stack within
  1.5% of an 82M-parameter transformer on bits-per-byte.*
- Caveat (honest): the Gutenberg text has hard line-wrapping that inflates BPB for **both** (same bytes, so fair, but
  the absolute ~2.0 is high); and our prequential mode adapts on the held-out while GPT-2 is frozen — that's *our* value
  prop (continual learning), stated plainly, not hidden.

**The settled answer to "is the committee better than attention?"**: on *raw capability*, **no** — a real transformer is
better (probe 5 hinted it; probe 8 measures it: ~13% on frozen BPB). On *cost + continual learning + competitiveness at
tiny scale*, **yes** — we sit within ~1.5% of a small GPT-2 on the fair metric while running on a CPU in seconds at tens
of MB, and we keep learning with no forgetting. That is the true, defensible claim.

## Status
Probes 1–8 done, measured, committed — including a self-correction (probe 5), real depth wins (probes 6–7, +23% rel,
saturating ~3 levels), and a **stolen-GPT-2 head-to-head** (probe 8): transformer wins raw capability (~13% BPB), our
continual stack within ~1.5% at a fraction of the cost. The whole
arc, honestly: (1) attention's soft routing → hashing, O(n), probe 1; (2) sharp recall/induction → exact discrete
address, O(1), unbounded capacity where continuous replacements crater, probe 2 (decisive); (3) both jobs as one O(n)
streaming predictor, probe 3; (4) a sigil committee that beats a single attention head online, no softmax, probe 4;
(5) **verification** correcting the multiple from "15–20×" to "~3× vs an attention I can't certify as strong — cheaper +
continual + competitive at tiny scale," probe 5; (6) **depth via hierarchical runes, +2.7, it works**, probe 6. Open
next: couple the levels more richly (joint phrase×concept×rune keys), more levels, and a properly-trained transformer
baseline to make the capability comparison unimpeachable.
