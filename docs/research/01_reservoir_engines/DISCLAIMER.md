# Disclaimer — Thread 01: Reservoir Engines (VSA era)

**These documents predate the program synthesis work (Threads 04–06).**
They describe the reservoir computer's evolution, not the invention engine.

## What was true when written

- Flame/Flare/Flux/Fractal/Frost are real, runnable Zig engines
- The "51x improvement" is a real benchmark number (closureError L1 loss reduction over 6 engine generations)
- Trigger edge, closure delta, and lattice fingerprint are real measurable signals per input
- 8 calibration prompts produce 8 distinct edge values — this discrimination is real

## What was later revised

- **VSA grounding is non-load-bearing.** A 2026-05-17 control experiment swapped VSA-derived
  coefficients for random PRNG of equal magnitude. Result: byte-identical lattice fingerprints.
  The "semantic grounding" framing is structural, not semantic.
- **"Transformer killer" claims** in the Flux and Frost invention files were narrative framing
  by an earlier agent, not an engineering claim. The engine cannot generate language.
- **GF(2)-linearity** was not understood in this era. The Bit-tape inventor (Thread 05)
  revealed why XOR/AND/NOT substrates fail PractRand regardless of how well the reservoir
  discriminates inputs.

## Safe to use these docs for

Reading about the reservoir computer architecture and the engine evolution benchmarks.

## Do not use these docs for

Claims about program synthesis quality, MUL-necessity, or bijectivity — those experiments
did not exist yet.
