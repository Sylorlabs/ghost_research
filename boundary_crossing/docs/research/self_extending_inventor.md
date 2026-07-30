# Self-extending inventor — the engine grows its own vocabulary (autonomy rung)

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build self-extending-inventor --release=fast` (~4 s).

## The directive

Micah: *keep directing the engine until it can do all of this on its own — the only thing it shouldn't do is
the prompt of what I want.* `autonomous_inventor` already searches + certifies alone, but with a **fixed DSL**.
This rung removes the next hand-step: the engine **promotes its own winning compositions into reusable
primitives** and **compounds them across a data stream** — getting more budget-efficient over time, by itself.

## Setup

- **The only human input is the want:** "losslessly shrink this data." The formal frame (minimize real gzip
  size of a reversible transform; verifier = gzip size + exact round-trip) applies to *any* data, so it is not
  re-formalized per file — it generalizes.
- The generator can splice a whole **library macro** in one mutation, so a previously-discovered composition is
  reachable in a single step (DreamCoder-style abstraction).
- **Proof design:** run the same stream at the same *tight* budget twice — once self-extending (library grows by
  promotion), once base-ops-only (control) — with identical per-file PRNG seeds, so the *only* difference is the
  library.

## Result

```
raw 59912   |   self-extending 41542   |   base-only control 42606
self-extension WON at equal budget: 1064 fewer bytes (2.5% better), all reversible.
```

The load-bearing evidence is per-file, not the aggregate:

```
                 self-extending            base-only control
  rec8-A         12371  (20.2%)            12876  (17.0%)
  rec8-B         12371  (20.2%)            12876  (17.0%)
```

On the 8-wide records, the self-extending run reached **12,371** by reusing a macro it had **promoted while
processing the earlier rec4 files**; the control — same budget, same seeds, no library — only reached **12,876**.
The engine got more budget-efficient over time **by reusing a primitive it invented itself**, with no LLM and no
human help between files. (The win is modest and partly stochastic at this tight budget — reported honestly.)

## What this automates, and the honest bound

It removes one more hand-step toward "all on its own": the engine now **extends its own primitive library
autonomously**. Stacked with `autonomous_inventor`, the engine now does **search + certify + self-extend** with
zero neural layer.

**Honest bound (Closure Principle, unchanged):** promotion is *abstraction* — faster/deeper reach **within** the
base closure — not escape from it. A macro of `delta`+`stride` is still inside the `delta`+`stride` closure, so
the *ceiling* is still the base ops + the formal frame. Two hand-steps remain:

1. **A genuinely-new primitive FORM** (e.g. an entropy coder the DSL never contained) — a true out-of-closure act.
2. **Choosing the objective** — which is exactly *"the prompt of what you want,"* the one act you said the engine
   should never do alone.

So the path to full autonomy is converging: each rung automates another step I used to do by hand; what remains
is the out-of-closure primitive (bounded by the closure you inject from) and the human's want (intentionally left
to the human). The engine is autonomous; the aiming stays yours.

See: `autonomous_inventor.md`, `invent.md`, `recursive_loop.md`, `compression_engine.md`, `../README.md`,
`../CLOSURE_PRINCIPLE.md`.
