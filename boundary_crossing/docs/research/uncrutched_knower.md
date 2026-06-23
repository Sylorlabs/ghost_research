# The Un-crutched Knower — learning a verified IS-A graph from raw text, no WordNet, no hardcoding, no LLM

**Goal.** Build a *knower, not a guesser*: a system that learns its concept structure (IS-A / hypernymy) from
**raw streamed text with zero hardcoding** — no handed ontology (WordNet), no handed patterns (Hearst), no
part-of-speech lists, no stop-word lists — then **commits only to what it can verify, abstains otherwise, and
shows its proof.** WordNet is used **only to grade** precision/recall; it never answers. No neural net, no
backprop, no LLM. CPU, seconds, tens of MB of working set.

This is the counter-architecture to a transformer: a transformer is a next-token *guesser* whose objective
[rewards confident bluffing](https://arxiv.org/pdf/2509.04664) (OpenAI 2025 — that is the root of hallucination);
this is a *knower* whose default is "I don't know."

---

## The arc (every step measured against WordNet, which is grade-only)

| stage | method | precision | recall |
|---|---|---|---|
| literature, 4 discovery methods | distributional / frame / structure / funnel | ~2–3% | 0–8% |
| Simple Wikipedia + funnel | discovered copula frames | 9% | 2% |
| Simple Wikipedia + funnel + self-closure | relation-identity filter | **14.5%** | 1% |
| English Wikipedia + funnel | more data | 8.9% | **9.3%** |
| 2-witness grounding (wiki ∩ lit) | cross-source convergence | 40–83% | — |
| **3-witness grounding, ≥3 unanimous (wiki+lit+wikt)** | + Wiktionary | **44%** | — |
| 3-witness grounding, ≥2 | high coverage | 31% | — |
| conjecture → test → auto-promote | sibling analogy + witness test | ~5% (FAILED) | — |
| *hand-patterns (HARDCODED, reference)* | *Hearst + Webster genus* | *37%* | *4%* |

**Headline:** with everything *discovered* and *cross-source-verified*, the unanimous grounded core
(**44%**) **beats the hardcoded baseline (37%)** — and the WordNet metric *underestimates* (many grounded
edges are correct but absent or differently-filed in WordNet).

---

## What was learned (the findings)

1. **Source wall.** Pure literature + a 1913 dictionary do not *state* taxonomy at learnable density. Four
   zero-hardcoding methods and 4× more data all stalled at single digits — it is a *source-type* problem, not
   an algorithm or volume problem. (`discover_isa.zig`, `compare_discovery.zig`.)

2. **Direction wall.** The copula "is a" *appears* but scores **50% (chance)** on every unsupervised
   direction signal (context breadth, entropy). Knowing a relation exists ≠ knowing which word is the category.
   Direction lives in phrase structure (what hardcoding secretly supplies). (`compare_discovery.zig`.)

3. **Streaming Wikipedia breaks the source wall.** On definitional text the funnel *discovers the copula*
   (`is a` / `was an` / `are an`) as the top IS-A structure — impossible on fiction — lifting precision 2%→15%.
   (`wiki_extract.zig` + `funnel_discover.zig`.)

4. **Self-closure isolates the IS-A relation.** Among many concentrated frames (most are naming / locative /
   temporal, e.g. `born on`, `known as`, `in the united`), the IS-A ones are those that *close on themselves*:
   their objects re-appear as their own subjects (categories have their own definitions). That signature picks
   out the true copulas. (`funnel_discover.zig`.)

5. **Grounding breaks the precision ceiling.** Pure-structure discovery ceilings ~12–15%. Requiring an edge to
   be **confirmed by ≥2 independent witnesses** (encyclopedia / dictionary / crowd-dictionary), with transitive
   matching so divergent vocab converges at shared ancestors, jumps precision to **40–83%**. Uncorrelated
   per-source noise fails to reach quorum. This is the project's certifier principle (replicated escape).
   (`ground.zig`.)

6. **Conjecture auto-promotion failed — honestly.** Sibling-analogy *generates* hypotheses fine, but
   auto-promoting "confirmed" ones stays ~5% (≈random): analogy under abstract hubs (`act`/`part`/`person`)
   explodes combinatorially, and the witness-reach test cannot filter it **because the noise is correlated
   across witnesses.** (`conjecture.zig`.)

7. **Deep composition manufactures false certainty.** Transitive chaining over a ~31% graph produced
   `oak → high → sea → animal` asserted as KNOWN. Fix: shallow composition (depth 2) + label everything else
   CONJECTURE. (`oracle_grounded.zig`.)

8. **The deepest finding — the real ceiling.** Cross-source voting removes *random* noise but **not
   *correlated/systematic* noise**: every dictionary-style source shares the same abstract-hub attachments and
   word-sense errors (English-Wikipedia "Dog" = the 2022 film). That systematic error survives even ≥3 agreement,
   capping precision ~44%. **Killing it needs true grounding — word-sense disambiguation and extensional
   verification — not more witnesses and not more analogy.**

---

## The engine (KNOWN / CONJECTURE / REFUSED)

The final oracle (`oracle_grounded.zig`) answers IS-A from the **self-learned grounded graph** (no WordNet) in
three epistemic states — the realization of *"guessing is allowed, but it must be labeled and tested; never pass
a guess off as knowledge"*:

- **KNOWN** — grounded edge or short (≤2-hop) grounded chain; answered with a provenance chain.
- **CONJECTURE** — a guess by sibling analogy; explicitly labeled *not verified*; never trusted, only a source
  can promote it. (This is the invention fuel: hypothesis → test → KNOWN, the scientific method = the project's
  inject→certify→promote loop.)
- **REFUSED** — no basis even to conjecture.

**Memorization-proof test (WordNet-free):** teach a brand-new word `blorch is an oak`, then ask a consequence it
was never told — `is a blorch a tree?` → **KNOWN** (`blorch → oak → tree`); `is a blorch an animal?` → **REFUSED**.
It composes a fresh fact over knowledge it discovered itself.

### Why this is beyond transformers and beyond neurosymbolic
- **Vs transformer:** runes are *discovered* discrete addresses (O(1) exact lookup) vs learned O(n²) attention;
  the sigil (ResonanceEMA) is *intrinsic* calibration vs a miscalibrated bluffing softmax; **context lives in
  RAM** — persistent, unbounded, O(1), online, **no catastrophic forgetting**, flat ~1.1 GB — vs a bounded,
  degrading ("lost in the middle"), frozen, forgetful attention window. At *equal data* a count-rune LM already
  beats a from-scratch GPT (1.82 vs 2.26 bpb); the LLM's edge is purely its data hoard.
- **Vs neurosymbolic:** that paradigm *keeps* the neural guesser and bolts a symbolic verifier on to patch
  hallucination. This has **no neural guesser at all** — discovered+counted+grounded throughout. We removed the
  guesser instead of refereeing it.

---

## Files (all build with `zig build-exe <file>.zig -O ReleaseFast -femit-bin=/tmp/<x>`)

| file | role |
|---|---|
| `discover_isa.zig` | pure distributional inclusion (zero hardcoding) — fails (~3%), proves the wall |
| `compare_discovery.zig` | head-to-head of discovery methods; the "is a" direction diagnostic (50% = chance) |
| `concept_precision.zig` | precision metric + POS-filter experiment (rejected as hardcoding) |
| `wiki_extract.zig` | **streams** Wikipedia pages-articles bz2 → one definition sentence per article (no hoarding) |
| `funnel_discover.zig` | discovers copula frames by funnel + certifies IS-A by self-closure; dumps edges (arg 2) |
| `wikt_extract.zig` | streams Wiktionary → `headword is <gloss>` (third witness) |
| `wikt_edges.zig` | turns one-shot Wiktionary defs into high-recall candidate edges (funnel can't — freq=1) |
| `ground.zig` | **N-witness cross-source grounding** (≥K-vote); persists `corpus/grounded_isa.tsv` |
| `conjecture.zig` | conjecture→test→KNOWN loop (sibling analogy); honest negative on auto-promotion |
| `oracle_grounded.zig` | **the knower**: KNOWN/CONJECTURE/REFUSED over the self-learned grounded graph |
| `concept_learn.zig` | (pre-existing) Webster-genus + Hearst witness; now also dumps edges for grounding |

**Pipeline to reproduce:**
```
# witnesses (stream, no hoarding):
curl -s <enwiki>.bz2     | bzip2 -d | /tmp/wx  > corpus/wiki_en_defs.txt
curl -s <enwiktionary>.bz2 | bzip2 -d | /tmp/wkx > corpus/wikt_defs.txt
/tmp/fun corpus/wiki_en_defs.txt /tmp/src_wiki.tsv     # Wikipedia witness edges
/tmp/cl                                                  # Webster+Hearst witness → /tmp/src_lit.tsv
/tmp/we < corpus/wikt_defs.txt > /tmp/src_wikt.tsv      # Wiktionary witness edges
/tmp/grd                                                 # 3-witness grounding → corpus/grounded_isa.tsv
/tmp/og                                                  # the grounded knower (KNOWN/CONJECTURE/REFUSED)
```
Generated corpora and `*.tsv` are git-ignored (regenerate via the probes).

---

## Honest limitations / open frontier
- Grounded precision caps **~44%** due to **systematic** (not random) noise: word-sense collisions + abstract-hub
  attachments shared by all text sources. The next real lever is **sense disambiguation + extensional grounding**
  (verify against the world / computation / execution), and **a conjecture verifier decorrelated from text noise**.
- Coverage is data-bound and scales with witnesses/streaming (full enwiki was still streaming at writing).
- No fluent generation yet (architecture, not data — `babble` showed small count models babble); the path is
  *grounded* generation: emit only verified content, decline otherwise = fluency without hallucination.
