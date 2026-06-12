# U3: Cache-aware routing — first confirmed speed lever

**Date:** 2026-06-11
**Code:** `src/ppl_stack.zig` (lruTouch/lruFind + substitution policy in the
score-layer gate, quant stream only)
**Raw output:** `u3_cap64_eps10.txt`, `e11_positions_off8000_cap64.csv`
**Baseline:** E11b no-policy run (`e11b_hard_text.txt`, QUANT ppl 29.94,
gap +0.206 nats)

## The idea

The P8 chaos experiment proved the gate's top-6 margins are razor-thin —
read as an exploit: if the model barely distinguishes expert #6 from #9,
substitute a cache-resident near-equal for a cold pick and skip the disk
fetch. Policy: per layer, keep an LRU set of the 64 most recently used
experts (evolving over tokens = decode time); when a top-6 pick is not
resident and some resident expert keeps >= 90% of its gate score
(eps=0.10), route to the resident one. Routing weights are recomputed from
the actual (substituted) experts' scores. Hash layers (0-2) untouched. An
identical baseline LRU fed by unmodified picks counts counterfactual misses,
so one run measures both conditions.

## Result (T=256, offset 8000 held-out text, cap=64, eps=0.10)

| metric | no policy (E11b) | U3 policy |
|---|---|---|
| score-layer fetches | 27,361 | 20,273 (**-25.9%**) |
| QUANT ppl | 29.94 | 30.42 |
| quant-vs-ref NLL gap | +0.206 nats | +0.219 nats (+0.013) |
| top-1 agreement w/ ref | 86/127 | **90/127** |
| hidden cosine @L51 | 0.859 | **0.892** |

- 7,651 substitutions over 58 score layers x 256 tokens.
- Fetch savings are depth-dependent: ~45% at L03 shrinking to ~16-20% by
  L49-51 — deep layers spread usage wider than 64 slots cover. Cap is the
  binding constraint at depth (sweep it).
- **The policy improves trajectory fidelity** (cosine to ref up ~0.03 at
  depth; top-1 agreement up): preferring recently-used experts acts as
  routing hysteresis, damping the thin-margin pick-flipping that drives
  quant divergence. Speed mechanism, quality side-benefit.
- Instrument noise floor note: REF NLL differs from E11b by 0.0026 nats
  (3.1964 vs 3.1938) — expert accumulation order changes with the works-map
  shape (float non-associativity). Run-to-run REF noise ~±0.003 nats; the
  +0.013 policy cost is ~4-5x that floor: measurable, small.

## Interpretation

First measured multiplier for the tps campaign: ~1.35x on fetch-bound decode
at essentially flat quality, from a routing-policy change alone — no format
change, no retraining. Compounds with expert compression (U2): smaller
experts → more cache slots per GB → more residents to substitute toward.

## Next

- Sweep cap (128, 192) and eps (0.05, 0.2, 0.3) in T=128 screening mode
  (~35-40 min/run, 10 threads, checkpointed). Screening metric = within-run
  quant-vs-ref gap + fetch reduction (each run carries its own ref stream).
- Try biasing the top-6 selection itself (score + lambda*resident) instead
  of post-hoc substitution.
- If the hysteresis quality effect holds across settings, test pure
  hysteresis (eps applied to keep PREVIOUS token's experts) as a quality
  repair for the 0.2-nat tax independent of caching.
