# Intent recognizer — NL want → formal objective, engine-native (step 2)

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build intent-recognizer --release=fast` (~1 s).

## The question (Micah)

Do step 2 — turn a natural-language want into a formal objective+verifier — **by the engine**, engine-native,
*not a wasteful LLM*; training is allowed.

## The honest framing

Turning *arbitrary, open-ended* language into a formal objective is genuinely language understanding — the one
place a general language model is irreducible; no substrate trick escapes it the way step 1 did. **But this
engine's wants are a tiny fixed set of shapes** — minimize `{SIZE, TIME, MEMORY}` under `{COLD, LIVE}` — and
both halves are things the engine already *measures*. So NL→formal is not "comprehend language," it is "classify
the want into which measurement + which constraint, from a menu the engine already owns." That is a **small
trained classifier**, not a 100-billion-parameter model.

## What was built

A two-head **averaged-style perceptron** over word features, trained on **22 labelled wants**, plus two pieces of
standard bag-of-words hygiene that make it honest rather than a brittle keyword table:

- **Generalization:** it classifies by summing learned per-word weights, so it routes *recombined / re-worded*
  wants it never saw.
- **Abstention (the hard part):** a want is *out of scope* unless it contains a **content word** — a token whose
  training occurrences **concentrate in one class** (≥66%) **and** that is not a closed-class function word
  (a tiny stopword list). This is what lets it *refuse* "make it prettier" instead of force-fitting it.

## Result — 10/10 held-out

```
"make the file smaller and keep it live"        → minimize SIZE  s.t. LIVE     ✓  (recombined)
"i want less memory offline is ok"              → minimize MEMORY s.t. COLD     ✓  (recombined)
"make decoding faster for realtime use"         → minimize TIME   s.t. LIVE     ✓  (new wording)
"shrink it as much as possible for cold storage"→ minimize SIZE   s.t. COLD     ✓  (new wording)
"compress with random access please"           → minimize SIZE   s.t. LIVE     ✓  (new wording)
"make it more beautiful"                        → OUT OF SCOPE                  ✓  (refused)
"make the users happier"                        → OUT OF SCOPE                  ✓  (refused)
"make full mode compress more offline is fine"  → minimize SIZE   s.t. COLD     ✓  ← Micah's want → FULL
"make regular mode smaller but it must run live"→ minimize SIZE   s.t. LIVE     ✓  ← Micah's want → REGULAR
"make regular decoding faster and keep it live" → minimize TIME   s.t. LIVE     ✓  ← Micah's want → live speed
```

None of these phrasings were in training. The recognizer **generalized**, **abstained** on the two wants outside
its menu, and **formalized Micah's own original mathpressor request** into the exact objectives that were built
by hand earlier in the session — the loop closing on itself.

## The full loop, now with no LLM anywhere

```
you type a sentence
   → [intent_recognizer, a tiny trained perceptron — NO LLM]   → formal objective (minimize X s.t. Y)
   → [autonomous_inventor / primitive_synthesizer — NO LLM]    → search + invent + certify
   → certified result
```

The only human input is the sentence — exactly the line Micah drew ("the only thing it shouldn't do is the
prompt of what I want").

## Honest bound

It covers the wants in its menu and refuses the rest. A want needing a measurement the engine **doesn't have**
("make it prettier") is out of scope — and that's out of scope for *any* automated system, LLM or not, because
no measurement grounds it. Widening coverage = adding (measurement, examples) pairs to the menu, which is
engineering, not a new neural capability. The "understanding" the LLM seemed to provide was mostly overkill: the
depth was always in the search (which the engine does alone), never in parsing three keywords.

See: `primitive_synthesizer.md` (step 1), `autonomous_inventor.md`, `self_extending_inventor.md`, `../README.md`.
