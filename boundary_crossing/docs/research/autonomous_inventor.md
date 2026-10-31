# The engine without the neural layer — autonomy on a formal objective

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build autonomous-inventor --release=fast` (~3 s).

## The question

Micah, after the mathpressor work: *leave that project alone and see if it can make its own that can do things
by itself without needing you — the neural layer — to understand human intent.*

The realization that makes this testable: across every experiment, the LLM's one irreducible job was
**understanding intent** — turning a loose human wish ("make x cheap", "improve mathpressor") into a *formal
target + a verifier*. Everything after that (search, certify, promote) is mechanical. So to remove the neural
layer, hand the engine a **formal, self-measurable objective** and let it run.

## What was built

A self-contained engine with **no LLM in the loop**:

- **Objective (formal, stated once, never interpreted at runtime):** find a *reversible* byte-transform that
  minimizes the **real gzip size** of the data.
- **Verifier = real measurement:** `std.compress.gzip` output size **+ exact round-trip** (forward then inverse
  must reproduce the original byte-for-byte). A non-invertible candidate scores infinity — it can never win.
- **Generator = blind evolution:** a fixed PRNG mutates short programs in a tiny filter-DSL
  (`delta` / `xor` / `add` / `stride` / `move-to-front`). **No LLM proposes anything.** Mutation + measurement
  keep the winners; hill-climb with restarts.
- The engine is told **nothing** about each data type. It must *discover* the right filter by measurement alone.

## Results — it invented the right filter for each type, by itself

```
counter/ramp   gzip   396 →    51   (87.1% smaller)   INVENTED: delta(d=1)
sensor walk    gzip 14455 →  6923   (52.1% smaller)   INVENTED: delta(d=1) → stride(6) → add(255)
record array   gzip 15344 →  8335   (45.7% smaller)   INVENTED: stride(8) → delta(d=1)
text           gzip  2545 →  2545   ( 0.0% smaller)   INVENTED: identity (correctly declined)
TOTAL                                 45.5% smaller    all reversible ✓
```

- **counter/ramp → `delta(1)`**: a counter becomes all-ones; textbook-correct, found with no hint.
- **record array → `stride(8) → delta(1)`**: the engine **inferred the 8-byte record width** purely from
  compressed size, de-interleaved the columns, then delta'd them. This is exactly the columnar route I proposed
  *by hand* for mathpressor — here the engine discovered it **itself**.
- **text → `identity`**: where no filter helps, it correctly invents *nothing* — no hallucinated transform,
  the same honest "decline" the math probes showed on structureless targets.

## The honest answer to the question

**Yes — for a fixed, formal, machine-measurable objective, the engine runs entirely by itself.** No human intent
understood at runtime, no LLM proposal: just a formal goal + blind mutation + real measurement. It *is* FunSearch
with the LLM replaced by mutation — and it works, inventing and certifying genuinely useful structure (including
discovering record width) on its own.

**And the precise boundary (Closure Principle, unchanged):** two acts still need an out-of-closure source:

1. **Extending the substrate** — inventing a primitive *outside* the DSL (the engine can compose delta/stride,
   it cannot invent an entropy coder it was never given).
2. **Choosing the objective** — deciding *what* to optimize.

**Understanding a new human intent is exactly act (2).** That is the one irreducible job of the neural layer.
So the full, honest answer: *the engine is autonomous; the aiming is not.* Point it at a formal objective and it
needs no LLM. Ask it "what should I even build, and what does this vague wish mean" — that still needs the
neural layer, and the whole research arc proved that gap is structural, not a missing feature.

See: `invent.md` (the LLM-in-the-loop front-end this is the autonomous counterpart of), `autonomous_engine.md`,
`real_invention.md`, `dial_three.md`, `../README.md`, repo-root `CLOSURE_PRINCIPLE.md`.
