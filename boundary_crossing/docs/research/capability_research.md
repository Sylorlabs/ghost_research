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
- **Verdict (superseded by #5):** the architecture is right in principle, but a *plain* from-scratch net loses — naive
  SGD on CPU-seconds doesn't get there. **What was missing wasn't optimizer exotica — it was the residual/identity path
  with a small scaling gain (ReZero).** Experiment #5 adds exactly that and the learned organ finally beats the linear
  organ on generalization. So this is **not** a fundamental negative; it was a missing architectural piece. CPU-scale,
  no GPU.

### 5. `sigil-organ` — "use the sigil, not softmax": the RESIDUAL fix + selective prediction
The user's push ("use sigil not softmax; if you can't find the solution, experiment more") forced two real results.

**The MLP collapse and its fix (residual + ReZero).** A from-scratch 2-layer net kept dying *below the unigram floor*
(1.3–2.0%) because random hidden features swamp the signal. Sweep of training rules, all measured:

| organ variant | unseen-slice top-1 | note |
|---|---:|---|
| pure MLP (sigil-margin) | 1.3% | margin perceptron = weak multiclass learner |
| pure MLP (neg-sampling, sigil-LR) | 1.3% | random features dominate the argmax |
| residual, **jointly**-trained linear path | 2.0% | noisy branch corrupts the linear path too |
| residual, **frozen** identity, no α | 1.5% | frozen identity, but MLP path still swamps it |
| **residual, frozen identity + ReZero α=0.3** | **4.1%** | **beats linear organ (3.3%) — the delta generalizes** |

The fix is the actual transformer ingredient I'd been omitting: a **residual/identity path with a small scaling gain**
(ReZero/LayerScale). Freeze the already-good linear organ as the identity, add `α·(W2·tanh(W1·ft))` with `α=0.3` and
`W2=0` at init → the organ *starts* at the linear score and the nonlinear delta can only ADD. Result: the delta wins on
the UNSEEN slice (**4.1% vs 3.3%**), lifting the count+organ **hybrid to 10.1%** (past the prior 9.6% ceiling). The
earlier "MLP can't beat linear" negative was a **training-architecture** problem (no identity path, no residual
scaling), not a fundamental one — surprise-weighted-LR neg-sampling + residual scaling cleared it.

**The sigil is a DECISION organ, not a loss.** Two sigil-in-the-loss ideas failed: sigil-margin training (1.3%) and a
sigil hybrid *gate* that routes weak-count contexts to the organ (8.0% < hard gate's 10.1% — even a count-of-1 beats a
4% organ, so routing away from counts is always wrong). Where the sigil *does* win is **selective prediction**: calibrate
a confidence per prediction (count purity / organ margin, z-scored by the ResonanceEMA) and accuracy CLIMBS as you keep
only the confident ones — **10.1% (full) → 15.4% (top-50%)**. (Tail is noisy: top-25% 12.6%, top-10% 15.7% on ~70 pos,
and merging two z-scaled pools isn't perfectly monotone — but the macro "confident half is ~1.5× more accurate" holds.)
That "know when you're right" property is the deployable thing a softmax's miscalibrated probs don't give you.

- **Verdict:** the residual+ReZero organ is the first learned organ here to *beat* the linear organ on generalization
  (4.1 vs 3.3) and raise the hybrid (10.1%). The sigil's home is **calibration/selective-prediction and surprise-weighted
  training**, not replacing the loss. Both are CPU-seconds, no GPU, no softmax.

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
4. **Generalizer** (learned readout) — fills sparse gaps. ✅ as a *linear* organ (+25% hybrid); ✅ as a **residual**
   organ (frozen linear identity + ReZero-scaled nonlinear delta) — beats the linear organ on the unseen slice
   (4.1 vs 3.3), hybrid 10.1%. The pure-MLP failure was a missing residual path, not a data-center training problem.
5. **Sigil** (ResonanceEMA + ControlPlane) — calibrated confidence / decide / edit. ✅.
6. **Verifier** (sound oracle) — certify / branch out truthfully (anti-parrot). ✅.

**Missing organ — now built:** the richer generalizer needed a **residual/identity path + small residual scaling
(ReZero)**, not a bigger optimizer. With it, the learned organ beats the linear one on generalization (4.1 vs 3.3) and
the hybrid hits 10.1%, all in CPU-seconds. Open next rungs: bigger CTX/HID, attention over the window, and a cleaner
single-pool confidence so the selective-prediction curve is monotone to the tail.

## Honest scope
The whole arc keeps returning the same shape, measured not argued: this stack **wins on truth / calibration /
continual-learning / cost / auditability**, and on the *checkable* slice; it **loses on raw next-rune capability and
fluent generation**, which need a well-trained learned encoder. No experiment here closed that last gap; the honest
next rung is the *training* of the richer organ, not its conception.
