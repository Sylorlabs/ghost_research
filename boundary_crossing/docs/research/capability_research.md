# Capability research: is the gap data or architecture? (rune-native LM, no LLM, no GPU)

Research log for the "can a tiny CPU rune-model approach a transformer's capability?" arc.
All experiments are rune-native (no tokens, no tokenizer), CPU-only, no data center. Metric = next-**rune** top-1.

## The question
A pure count/retrieval rune-model loses to a transformer on raw capability. Is that a **data** problem
(more text closes it) or an **architecture** problem (a missing mechanism)?

## Experiments (each a probe, each measured)

### 1. `knn-lm` — retrieval vs parametric n-gram, + the online axis
- **Capability (held-out prose, next-rune top-1):** kNN-retrieval **3.6%** vs parametric trigram **8.2%** — retrieval **LOST**.
  A blurred avg-of-recent-embeddings context throws away the order/identity an exact n-gram keeps.
- **Online axis (out-of-distribution code):** FROZEN model (prose datastore, like a deployed transformer) **0.4%**;
  RETRIEVAL after *adding* the code to its datastore (instant, no retraining, no forgetting) **15.2%** — a 38× jump.
- **Verdict:** pure retrieval does NOT beat a transformer on capability (it didn't beat a trigram), but it **wins
  structurally on continual / updatable / no-forgetting** — a transformer can't match that cheaply.

### 2. `learned-organ` — add cheap learning; the HYBRID win
- Discriminative readout `w_r·context`, negative-sampling SGD, **211 ms on one CPU core, no GPU**.
- Held-out next-rune top-1: trigram 7.7%, kNN 7.1%, learned-organ-alone **4.3% (loses)**.
- On **unseen** contexts (lookup = 0% by construction): kNN 3.3%, learned 3.3% — both generalize where lookup can't.
- **The win:** COUNT-where-seen + LEARN-where-unseen = **9.6% > pure counting 7.7%** (+25% rel).
- **Verdict:** the organ's job isn't to replace counting — it's to **fill the gaps counting can't reach**.

### 3. `layers` — the SPARSITY PRINCIPLE (the core law, re-derived)
Sweep n-rune context order (memorization organ) × the learned generalizer:

| context | coverage | n-gram only | hybrid(+learn) |
|--------:|---------:|------------:|---------------:|
| 0 runes |   100%   |   4.7%      |   4.7%         |
| 2 runes |    43%   |   **7.7%**  |   **9.6%**     |
| 3 runes |    10%   |   3.6%      |   7.0%         |
| 5 runes |     1%   |   0.3%      |   4.6%         |

- Longer context = more predictive WHERE seen, but coverage **collapses** (100%→1%) = the **sparsity death**.
- Pure counting **peaks at order-2, then sinks**. The generalizer catches the sparse cases → hybrid doesn't sink.
- **It's a counting wall, not a data wall** — more text only sharpens counts you've seen, never manufactures
  coverage of contexts you haven't.

### 4. `richer-organ` — the learned encoder (MLP), 4 retraining iterations: HONEST NEGATIVE
A 2-layer net (Bengio-2003 shape) over CTX=4 runes: `concat embeddings → tanh hidden (learned features) → readout`.
Iterated: neg-sampling → zero-init readout → tiny-init + more epochs → full softmax.
- Across **all 4 runs** the MLP organ scored **1.4–2.0%** — *below the unigram floor*, and **worse than the cheap
  linear organ (5.1–5.3%)**, including on the unseen slice (MLP ~1.8% vs linear ~4.4%).
- **Verdict:** the architecture is right in principle (a learned encoder is how you use long context without
  sparsity), but **training a from-scratch net to actually beat the simple organs is the real, hard work** — naive
  SGD on CPU-seconds (even full softmax) doesn't get there. It needs proper optimization (Adam, normalization, LR
  schedule, more epochs/data, better input embeddings) — the engineering transformer training provides. **CPU-scale,
  not a data center, but NOT free.**

## The answer
**Architecture, not data.** Same data in, the n-gram (and a transformer) beat the count-retrieval model — and more
data only sharpens counts, it can't add the missing mechanism. The missing mechanism is **generalization over long
context without sparsity**, i.e. a **learned encoder**. That is the only piece that genuinely needs learning;
everything else (segment, embed, memorize, retrieve, calibrate, verify) is counting.

## The principle (the rune-LM thesis in one line)
**capability = MEMORIZE(dense) + GENERALIZE(sparse), gated by CONFIDENCE (sigil) + VERIFICATION (sound oracle).**

## The organs (what each does, what's missing)
1. **Segmenter** (byte→rune forge) — discovers units. ✅ works.
2. **Embedder** (co-occurrence / PPMI) — what's related. ✅ works.
3. **Memory/context** (n-gram / datastore) — memorizes dense patterns; strong but **sparsity-bound**. ✅.
4. **Generalizer** (learned readout) — fills sparse gaps. ✅ as a *linear* organ (+25% hybrid); ❌ as a from-scratch
   MLP so far (training is the open problem).
5. **Sigil** (ResonanceEMA + ControlPlane) — calibrated confidence / decide / edit. ✅.
6. **Verifier** (sound oracle) — certify / branch out truthfully (anti-parrot). ✅.

**Missing organ:** a *well-trained* richer generalizer (a learned encoder with real optimization). The conception is
done; the **training engineering** is the next real work — still CPU, still no data center.

## Honest scope
The whole arc keeps returning the same shape, measured not argued: this stack **wins on truth / calibration /
continual-learning / cost / auditability**, and on the *checkable* slice; it **loses on raw next-rune capability and
fluent generation**, which need a well-trained learned encoder. No experiment here closed that last gap; the honest
next rung is the *training* of the richer organ, not its conception.
