# Primitive synthesizer — the engine invents new primitive FORMS, engine-native (step 1)

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build primitive-synthesizer --release=fast` (~6 s).

## The question (Micah)

The two remaining ⏳ steps must be done **by the engine** — engine-native, *not a wasteful LLM*. This is step 1:
**invent a genuinely-new primitive form.** The Closure Principle says a search closed under a primitive set
reaches only that closure, so where can a *new* primitive come from without an out-of-closure LLM?

## The answer: move the substrate, then synthesize

A *fixed op-menu* (delta/stride/…) can only ever reach its closure. So **stop fixing the ops**: a primitive
becomes a **short program the engine synthesizes** — a tiny stack-machine *predictor* over past bytes. Inventing
a new primitive = **program search**. The reversibility trap (arbitrary transforms aren't invertible) is solved
by **structure**: every invented primitive is a predictor, applied as `out[i] = in[i] −% predict(past)`. That is
reversible for *any* predictor program (decode: `in[i] = out[i] +% predict(reconstructed past)`), so the engine
can synthesize **arbitrary** new predictors safely — scored by real gzip size, with **no LLM**.

## Result — it invented primitives the fixed menu can't express

```
                baseline (delta, best the OLD menu offers)   SYNTHESIZED        invented primitive
  quadratic     gzip 228                                      gzip  47 (−79.4%)  2·in[i-2] − in[i-4]
  smooth walk   gzip 3521                                     gzip 2677 (−24.0%) in[i-1] + in[i-3] − in[i-4]
  linear ramp   gzip 44                                       gzip  44 (tie)     in[i-1]  (delta already optimal)
```

The quadratic result is the proof: the engine **synthesized a second-difference predictor** (`2·in[i-2] −
in[i-4]`, a multi-tap linear extrapolator) — a primitive the delta/stride menu *cannot represent* — and crushed
data plain delta couldn't, by 79%. The smooth-walk 3-tap predictor is another genuinely-new form. Where delta
was already optimal, it honestly tied. All reversible, all found by blind program search, no LLM.

## How this respects the Closure Principle

The closure didn't vanish — it **moved**. From "5 fixed ops" to "all programs in the predictor substrate," a
vastly larger space the engine reaches by synthesis. That is the engine-native way to invent new primitive
forms: *not* magic from nothing (impossible — the Kolmogorov limit), and *not* an LLM — **program synthesis over
a richer substrate**. The new bound is the substrate's own closure (and the search budget): widen the substrate
(more ops, memory, 2-byte output, learned predictors) and the reachable primitive forms widen with it. This is
the same lever `compression_engine.md` and `autonomous_engine.md` identified (primitives-as-programs), here run
to a concrete new-primitive invention with zero neural layer.

**Step 1 — invent a new primitive form — is engine-native and done.** The honest residual is unchanged: a
substrate-bounded, search-bounded escape, not omnipotence. Step 2 (NL want → formal objective) is a different
problem — see the report and `intent_recognizer.md` when built.

See: `autonomous_inventor.md`, `self_extending_inventor.md`, `compression_engine.md`, `../README.md`,
`../CLOSURE_PRINCIPLE.md`.
