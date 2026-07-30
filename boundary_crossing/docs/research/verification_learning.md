# Learning better than LLMs and JEPA — the verification axis (research)

**Status:** research brief (web-grounded, June 2026). The honest case for how this engine can *learn* in a way
that beats LLM- and JEPA-style learning — on a specific, important axis — plus the concrete architecture to do it.

## The two ways everyone else learns — both are PREDICTION

- **LLMs** learn by predicting the next **token** (generative, raw output space). Sample-hungry (internet-scale
  text), and can be confidently wrong — there is no ground-truth check at inference.
- **JEPA** (LeCun) learns by predicting an abstract **latent representation** instead of raw pixels/tokens, so it
  spends no compute reconstructing irrelevant detail. This is genuinely better: V-JEPA 2 learns world dynamics
  from video and does zero-shot robot control after only ~62 h of robot data. But it is **still prediction** —
  it minimizes prediction error on observed data, learns *correlations*, and (like the LLM) has no notion of
  *certainly correct*.

Both are bounded by their data distribution, both can hallucinate, both need lots of data because every label is
**noisy** (a real-world sample, not a guaranteed-true one).

## The engine learns a third way — VERIFICATION

This engine doesn't predict data; it **searches structures and keeps what a sound verifier certifies** (exact
measurement: gzip size + round-trip; full-domain equivalence; a proof). The learning signal is not "what's
likely" but "what's **provably correct**." Three consequences, each a measurable advantage *on verifiable tasks*:

1. **Perfect labels, self-generated, unlimited.** The verifier hands out *certified* correct/incorrect for free.
   So the engine manufactures its own perfectly-labelled training data by searching + verifying — exactly how
   **AlphaZero** learns from self-play game outcomes, and what 2025–26 **RLVR** ("RL from verifiable rewards")
   and **"Propose, Solve, Verify"** self-play are built on. JEPA needs 1M h of video; the engine needs **zero
   external data** — it generates perfect data itself.
2. **Cannot hallucinate.** The verifier gates every result. The learned part may *guess*, but the verifier
   *decides*, so wrong answers never leave the box. LLM/JEPA have no such gate.
3. **Invents beyond the distribution.** Search + certify finds *new* certified structure (proven here: Fermat's
   divisor theorem undirected, shorter addition chains, the `2·in[i-2]−in[i-4]` predictor). Prediction can only
   interpolate its data.

This is not hype: it is precisely **why AlphaZero beats imitation learning**, and why the frontier is racing
toward verifiable rewards. The engine is **verifier-native**; LLMs and JEPA are prediction-native and have to
bolt verification on afterwards.

## How to make it actually LEARN (it currently searches *blind*)

Today the inventor does **blind** evolutionary search — no learned guidance. The upgrade is the AlphaZero /
DreamCoder recipe, stealing the *good* idea from JEPA (latent abstraction) while keeping the verifier as truth:

```
        ┌───────────────────────── the self-improvement loop ─────────────────────────┐
  1. LATENT SUBSTRATE   (steal from JEPA)  learn an abstract representation of the data/problem →
                                            search in THAT space, not hand-coded ops  → richer primitives
  2. POLICY/ENERGY GUIDE (JEPA EBM + AlphaZero policy)  a small net predicts which candidates are PROMISING →
                                            guides the search instead of trying blindly → 10–100× faster search
  3. SOUND VERIFIER     (the engine's core; the thing JEPA/LLM lack)  exact measurement certifies → PERFECT LABEL
  4. TRAIN ON THE LABELS (DreamCoder wake-sleep / AlphaZero self-play)  the verifier's perfect labels train the
                                            guide + grow the library → compounding, no external data, no noise
        └──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Why this **learns better** than LLM/JEPA *on verifiable tasks*:
- the training labels are **perfect** (certified), not predicted-from-noise → far more sample-efficient than
  JEPA's masked-latent prediction or LLM next-token loss;
- the data is **self-generated and unlimited** (the engine searches + verifies to make more) → no data-collection
  wall;
- the guide is a small net (cheap, fast) yet the *results are certain* because the verifier, not the net, decides;
- it **discovers** (search beyond data), which neither can.

DreamCoder already shows the sample-efficiency end of this: "just a few examples are often sufficient to specify
a function," because it learns a DSL + neural search guide. We have the DSL-growth (`self_extending_inventor`)
and the verifier; the missing rung is the **learned guide** trained on the verifier's labels.

## The honest scope (where it does NOT beat them)

This wins **only where a verifier/measurement exists** — algorithms, transforms, proofs, certified facts,
optimization under a measurable objective. For perception, language, and open-world modelling — *JEPA's home* —
there is no crisp verifier, and JEPA/LLM win. So the honest claim is sharp, not grandiose:

> **For learning verifiable structure, verification-based search-and-certify learns more sample-efficiently,
> more reliably (no hallucination), and more inventively than prediction-based LLM/JEPA learning — because a
> verifier yields perfect, self-generated, unlimited labels. It does not beat them at perception or language;
> it beats them at learning things that can be checked.**

## The concrete next build

Add the **learned guide** to the inventor: a tiny policy/value net (features of the data + partial program →
predicted final compressed size / "is this branch promising"), trained on the verifier's certified outcomes
(perfect labels, self-generated). Measure: does guided search reach the same certified filter in far fewer
evaluations than blind search? That single experiment *demonstrates* "learns better" the project's way — by
measurement, not assertion. It is the AlphaZero loop with gzip as the game and reversibility as the rules.

## Concrete implementation: VERIFY-LEARN-INVENT (measured, June 2026)

`verify_learn_invent.zig` is the first end-to-end wiring of this axis — not a brief, a running binary.

**Reproduce:** `cd boundary_crossing && zig build verify-learn-invent --release=fast`  
**Full doc:** `verify_learn_invent.md`

### What it demonstrates

| Verification-learning property | Measured in verify-learn-invent |
|-------------------------------|--------------------------------|
| Labels from certifiers, not next-token | Weights update only on CERTIFIED/SURPRISE/FAILED/ABSTAIN (surprise **3.0×**, certified **2.0×**) |
| Perfect self-generated labels | gzip round-trip, chain minimality proof, held-out acc **≥0.90** |
| No hallucination past verifier | `meaning of life` → **ABSTAIN**; failed mono forge → no promotion |
| Sample-efficient routing | **28-phrase** corpus bootstrap; **3/3** novel task-specific routing after verify-learn |
| Invent beyond training dist | mono **0.541** → spectral **1.000** on hidden parity; l(1023)=**13** from English |

### Routing numbers (2026-06-30 run)

```
Bootstrap held-out (supervised seed, 22/6 split):  3/6 = 50.0%
English → certified invention:                    4/4
Verify-learn novel routing (squeeze/511/parity):  3/3
Explore unknown:                                  mono 0.541 → spectral 1.000
```

### Parallel fork: hardness-guided routing (Fork 2)

The same verification axis applied to **control feature discovery** (not English):

```
cd sparse_poly_discovery && zig build hardness-router-test --release=fast
```

| Metric | Measured |
|--------|----------|
| Q38 compound on DUAL_BAND | **CONFIRMED** (deg1 ∧ extremal both fail alone) |
| Guided vs brute pair quality | **35.13** vs **35.13** fail/1k (gap **0.00**) |
| Search cost | **5** probe+verify ops vs **12** brute pair runs → **2.4×** cheaper |

Hardness probes classify substrate before search — analogous to verify-learn classifying intent before invent.
See `sparse_poly_discovery/docs/research/parallel_forks_2026.md` (Fork 2).

### Honest ceiling (unchanged)

VERIFY-LEARN-INVENT **does not** beat transformers on open-ended language (`attention_replacement.md`: gpt2-124M
**1.91** BPB vs our **2.06** at ~7% gap on held-out prose). It wins on the **verification axis** only: bounded
intent menu, certifier-gated outputs, RLVR-weighted updates. The learned **guide** for blind invent search
(AlphaZero policy) remains the next measured rung in this doc's "concrete next build" section.

## Sources

- Turing Post, *What is JEPA?* — https://www.turingpost.com/p/jepa
- Meta AI, *I-JEPA* — https://ai.meta.com/blog/yann-lecun-ai-model-i-jepa/
- *V-JEPA 2: Self-Supervised Video Models Enable Understanding, Prediction and Planning* — https://arxiv.org/abs/2506.09985 ; https://ai.meta.com/blog/v-jepa-2-world-model-benchmarks/
- *LLM-JEPA: Large Language Models Meet Joint Embedding Predictive Architecture* — https://arxiv.org/pdf/2509.14252
- DreamCoder (wake–sleep Bayesian program learning) — https://royalsocietypublishing.org/rsta/article/381/2251/20220050/112456/
- *Propose, Solve, Verify: Self-Play Through Formal Verification* (2025) — https://arxiv.org/html/2512.18160v1
- AlphaZero (self-play + search) — https://www.science.org/doi/10.1126/science.aar6404
