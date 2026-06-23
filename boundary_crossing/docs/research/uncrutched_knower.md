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

## Refinements (round 2): attacking systematic noise + decorrelated verification

Two attempts on the systematic-noise ceiling, both measured, both honest.

**(a) Abstract-hub demotion (`refine.zig`) — small real win.** Discovered signal, no hardcoded list: abstract
relational nouns are overwhelmingly followed by **"of"** ("the act **of**", "a kind **of** Y") while concrete
hubs (animal, tree, bird) are not. Demoting hypernyms with a high corpus "followed-by-of" rate removes the
connective attachments (`kind`, `type`, `part`, `member`, `inhabitant`, `follower` — all the "X is a *kind* **of**
Y" pattern where the *real* hypernym is Y). At a conservative threshold (of-rate > 0.80): precision **31.4% → 32.3%**,
758 connective edges removed; the oracle now loads this cleaned graph (`grounded_clean.tsv`). *Honest limits:* the
gain is modest because (i) WordNet *credits* abstract chains (it has its own upper-ontology `part→portion→thing`),
so the metric under-rewards the cleanup; (ii) word-sense errors and generic hubs (`common`, `people`) are untouched.
The bigger win is **retargeting** ("X is a kind **of** Y" ⇒ X→Y), which needs the post-"of" target from the source — future work.

**(b) Decorrelated conjecture verifier (`conjecture.zig`) — honest negative.** The witness-reach test failed
because text witnesses share noise. Replacing it with a *structurally different* verifier — **extensional
coherence** (promote B→P only if B shares ≥2 *other* supercategories with P's known members; a computed graph test,
not "a source said it") — did **not** help: raw guesses 4.0% · correlated witness test 5.1% · decorrelated
coherence test **4.4%** (all ≈ random). **Finding: graph-internal invention cannot exceed its base-graph quality** —
the noise propagates through both the analogy *and* any internal verifier, because both read the same noisy edges.
This confirms the deep requirement: invention-by-analogy needs a verifier **external to the text/graph entirely**
(world / computation / execution), exactly as hypothesized. No such verifier exists for arbitrary concept IS-A;
where one *does* exist (number theory, terminal exit codes) the project's invention loop already works.

**Net:** the knower's grounded core is now slightly cleaner (32.3%); invention beyond grounding remains gated on
external grounding, not on a cleverer internal check. `refine.zig` added; `conjecture.zig` now reports correlated
vs decorrelated verifiers head-to-head.

## Round 3: the external "world" verifier — a decisive, fundamental negative (`verify_world.zig`)

The conjecture loop needs a verifier *external* to the definitional text. The candidate: **extensional usage
grounding** — IS-A is "every dog is an animal", so verify B→P by whether B's *usage* (how it behaves in running
prose) is asymmetrically **contained** in P's (Distributional Inclusion Hypothesis). One uniform measure, every
pair, **no hardcoded structure** — no patterns, POS, lists, or ontology. The usage model is built from running
prose (literary corpora), decorrelated from the definitional witnesses.

**Result: it fails, and the calibration shows *why* — the signal does not exist.** On real IS-A pairs the
inclusion is **symmetric**, not asymmetric:

```
dog → animal : 0.055 / 0.051     oak  → tree   : 0.195 / 0.197
rose→ flower : 0.068 / 0.064     ship → vessel : 0.290 / 0.289
                                 wine → drink  : 0.186 / 0.188
```

`incl(hyponym→hypernym) ≈ incl(hypernym→hyponym)` for every pair; ranking conjectures by the score gives
top-1000 7.2% ≈ bottom-1000 7.6% (zero discrimination). **The Distributional Inclusion Hypothesis is empirically
false here**: "dog" and "animal" appear in *mutually similar* contexts, not *nested* ones. Distribution conflates
"similar to" with "is subsumed by."

**The deep boundary this establishes.** The extensional fact that defines IS-A — *the set of dogs ⊆ the set of
animals* — is about **referents in the world**, not about word co-occurrence statistics. Text *describes* the
world but its distributional statistics **do not encode set-inclusion**. So a text-only "world" cannot be the
external verifier for IS-A direction. Verifying IS-A needs one of: (i) **hardcoded structure** (WordNet/patterns
— rejected by the project's premise), or (ii) genuine **referents** — perception, a world model, or instance-level
extension ("Lassie is a dog" ∧ "Lassie is an animal" ⇒ dog ⊆ animal). Pure distributional usage gives neither.
This is consistent across every distributional attempt in this project (generator 3%, graph-coherence 4.4%,
usage-inclusion symmetric) — distribution is a *similarity* signal, never a *subsumption* one.

**Constructive next step** (instance-extension grounding): mine instance→type assertions for named entities and
verify type⊆type by **instance-set inclusion** — the one text-derivable signal that is asymmetric by construction.
It is still text (and likely sparse/correlated), but it is the honest next thing short of perception.

## Round 4: instance-extension grounding — the first asymmetric IS-A signal (`instances.zig`)

After distributional usage inclusion failed (symmetric), the honest next signal is **instance-extension**: IS-A is
extensional (set of dogs ⊆ set of animals), so mine **instance→type** assertions ("Einstein is a physicist",
"Einstein is a scientist") and verify **T1 ⊆ T2 by SUBJECT-SET inclusion** — the entities text predicates of T1
are also predicated T2. This is asymmetric **by construction** (instance sets nest) and grounds in *referents*,
not co-occurrence. One uniform measure, no hardcoded structure.

**Mining (scale).**
| corpus | entities | types | instance→type assertions |
|---|---|---|---|
| Simple Wikipedia | 206,857 | 16,746 | 511,748 |
| **English Wikipedia** (1.2 GB defs, 7.07M lines) | **4,468,260** | **120,223** | **13,301,835** |

**The headline — DIRECTIONALITY ACCURACY** (over WordNet IS-A pairs present in the data, does
`incl(hyponym→hypernym) > incl(hypernym→hyponym)`?):

| corpus | decisive pairs | **correct** | backwards | no-overlap |
|---|---|---|---|---|
| Simple Wikipedia | 1,069 | **65.5%** | 369 | 7,506 |
| English Wikipedia | 10,475 | **69.8%** | 3,166 | 26,207 |

**This is the first real positive.** Distributional usage inclusion was a flat ~50% (symmetric — no direction);
instance-extension is **65.5% → 69.8%, and improves with data** (26× more text → +4.3 points *and* 10× more
judgeable pairs). The signal genuinely carries IS-A direction, grounded in referents, with zero hardcoded structure.

**Calibration (full enwiki), `incl(hypo→hyper)/incl(hyper→hypo)`** — works for multiply-labeled entities, fails on
label-frequency confounds:
```
physicist→scientist 0.020/0.011 ✓   poet→writer 0.192/0.080 ✓   painter→artist 0.074/0.055 ✓   dog→animal 0.010/0.005 ✓
city→place 0.067/0.125 ✗ (backwards)   town→place 0.036/0.168 ✗   village→settlement 0.012/0.158 ✗
```

**Generator precision vs WordNet (sweep, full enwiki):** 5.2–9.8% (minsup 3–10 × incl 0.4–0.7). Sample discovered
edges carry instance evidence: real (`telugu→language`✓, `racehorse→thoroughbred`, `golfer→professional`,
`emeritus→professor`, `midfielder→football`), corpus-extensional (`lawyer→politician` — true *of Wikipedia*),
and artifacts (`refer→may` from disambiguation pages, `http→ref` from citations, `gram→negative`).

**Three honest limits this study establishes:**
1. **Confounded direction (~70%, not ~95%).** Direction is governed by *which label is applied more often* among
   shared entities, not pure taxonomy: professions align (the broader term is used more — scientist > physicist),
   geography inverts ("place/settlement" are rarer labels whose instances nest inside "city"). 30% backwards.
2. **Sparse.** Only ~29% of WordNet pairs are even judgeable (71% have zero instance overlap) — most entities are
   *not* multiply-labeled even across 4.5M of them. Extension is real but thin in text.
3. **Generator precision ~8%** because "extension in a biased corpus" ⊋ "universal IS-A" (Wikipedia's lawyers
   really are mostly politicians) plus extraction artifacts.

**Scaling law (directionality vs data, full English Wikipedia, `instances.zig <N> <corpus>`):**
| lines | entities | assertions | directionality | judgeable pairs |
|---|---|---|---|---|
| 250K | 144K | 394K | 63.7% | 1,299 |
| 1M | 623K | 1.85M | 66.9% | 3,885 |
| 2.5M | 1.59M | 4.63M | 68.5% | 6,445 |
| 5M | 3.19M | 9.32M | 69.4% | 8,949 |
| 7.08M (full) | 4.47M | 13.3M | 69.8% | 10,487 |

Directionality rises monotonically **63.7% → 69.8%** over 28× data but **decelerates toward a ~70% asymptote** —
the label-frequency confound is a structural ceiling data cannot break. Coverage (judgeable pairs) scales ~linearly
(8×). The honest scaling law: **more data buys coverage freely and accuracy with diminishing returns to ~70%.**

**Verdict.** Instance-extension is the **first no-hardcoding signal that is asymmetric, better-than-chance, and
scales** — a genuine step past the distributional wall, vindicating that *referents*, not co-occurrence, carry
IS-A. But at ~70% directional and ~29% coverage it is a *weak* world-signal: text names referents too rarely and
labels them by convention, not taxonomy. The clean conclusion of the whole arc: **text is a thin, biased trace of
the world's extension** — enough for a measurable signal, not enough for reliable IS-A. Stronger grounding
(perception / interaction / a structured instance store) is the true ceiling-breaker; instance-extension is the
best a CPU-text system can do, and we measured exactly how far that is.

## Chatting with the knower

`oracle_grounded.zig` is an interactive natural-language REPL over the self-learned grounded graph (no WordNet).
Build & run:
```
zig build-exe oracle_grounded.zig -O ReleaseFast -femit-bin=/tmp/og && /tmp/og
```
It loads `corpus/grounded_clean.tsv` (falls back to `grounded_isa.tsv`) and answers in three states with a proof
chain: **KNOWN** (verified), **CONJECTURE** (labelled analogy guess, never asserted), **REFUSED** (no basis).
Understands: `is a dog an animal?` · `what is a cathedral?` · teach it `a poodle is a dog` · `why` (last proof) ·
`quit`. Composition works (`poodle → dog → … → animal`). Honest note: the graph is ~32–44% precise (cross-source
frontier), so KNOWN proofs occasionally route through a noisy intermediate (`dog → cat → animal`) — the answer is
usually right, the path shows the seams; coverage is ~6k concepts so out-of-graph queries REFUSE.

## Honest limitations / open frontier
- Grounded precision caps **~44%** due to **systematic** (not random) noise: word-sense collisions + abstract-hub
  attachments shared by all text sources. The next real lever is **sense disambiguation + extensional grounding**
  (verify against the world / computation / execution), and **a conjecture verifier decorrelated from text noise**.
- Coverage is data-bound and scales with witnesses/streaming (full enwiki was still streaming at writing).
- No fluent generation yet (architecture, not data — `babble` showed small count models babble); the path is
  *grounded* generation: emit only verified content, decline otherwise = fluency without hallucination.
