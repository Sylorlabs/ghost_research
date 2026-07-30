# Source C — the certifier tames an unreliable generator (the LLM stand-in)

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build certifier-filter --release=fast` (~10 s).

## The point

The whole value of "an LLM subordinated to the certifier" is that the LLM is an **unreliable rich source** — it
proposes a flood of candidates, mostly garbage or dressed-up recombinations, a few genuine. What makes it usable
for *invention* (not recombination) is that the certifier keeps **only** the proposals that provably escape the
current closure. This probe demonstrates that property directly, with no live LLM: a noisy proposer emits a
stream that is ~89% junk, and the certifier extracts the genuine out-of-substrate generators.

- **library:** the bits of `n`. **target:** divisible by 3, 5, or 7 (each genuine `mod_p` is decisive).
- **stream (the proposer):** GENUINE `mod_{3,5,7}` · REDUCIBLE `mod_2`, bit-copies (an LLM "rediscovering" what
  you already have) · GARBAGE random features (hallucinations).
- **certify:** accept iff ESCAPE (balanced-acc gain on **both** independent held-out folds) AND IRREDUCIBLE
  (R² from library < 0.40).

## Results

```
proposer stream: 27 candidates = 3 genuine, 4 reducible, 20 garbage (89% non-genuine)
  genuine  mod_3/5/7   gain val/test ≈ 0.25/0.27, R² ≈ −0.05   → ACCEPT
  garbage  random      gain ≈ 0.00/0.00 (or one fold only)     → reject (no replicated escape)
  reducible mod_2,bits gain ≈ 0.00,  R² = 1.000                → reject (reducible)

accepted 3 of 27.  PRECISION = 1.000,  RECALL = 1.000.
rejected: 20 garbage, 4 reducible, 0 genuine.   library → div(3,5,7) test acc 1.000 (from 0.498).
```

## Verdict

The certifier achieved **precision 1.000 on an 89%-non-genuine stream**: every accepted generator is a real
out-of-substrate escape; every garbage and every dressed-up recombination was rejected. Garbage fails ESCAPE (it
doesn't help); reducible fails IRREDUCIBILITY (the library already contains it). **That is exactly the property
that makes an unreliable rich source usable for invention:** the proposer can be an LLM hallucinating most of the
time, and the certified library is still clean. The LLM (if used) is the entropy source; **the certifier is the
inventor.**

## The methodological finding (earned the hard way, worth recording)

Getting precision to 1.0 was not free, and the failures are instructive:
1. **Irreducibility alone never rejects garbage.** A random feature is *trivially* irreducible (not
   reconstructible → low R²). So the IRRED gate filters dressed-up recombinations (mod_2, bit-copies: R²=1.0) but
   is blind to hallucinations.
2. **Single-fold ESCAPE is fooled by overfit noise.** With ~20 random proposals, some clear a small held-out gain
   by chance (multiple comparisons). First attempt: **precision 0.60.**
3. **The fix is replication.** Require the gain on **two independent** held-out folds; a genuine generator's
   signal replicates, a spurious one does not. Plus a threshold **above the noise floor** — which requires a
   target whose genuine generators are *decisive* (primality's per-`mod_p` gains are below the noise floor; "div
   by 3/5/7" is well above it). With both: **precision 1.000.**

This is the honest engineering of a real certifier: irreducibility for recombinations, **replicated** held-out
escape (above the noise floor) for hallucinations. It also bounds the claim — a certifier can only separate
signal that *clears the noise floor of the held-out evaluation*; sub-threshold genuine generators (e.g. a rare
divisor's tiny contribution to primality) are honestly indistinguishable from noise and will be rejected.

## How a real LLM slots in

Replace the hand-built stream with an LLM prompted to propose candidate generators (as code/features) for the
current target given the current library. Everything else is identical: the certifier runs ESCAPE (replicated
held-out) + IRREDUCIBILITY on each proposal and promotes only certified escapes. This is FunSearch with the
closure certifier as the evaluator — and it is *why* the LLM's unreliability is not a problem.

See: `invention_engine.md`, `world_injection.md`, `superopt.md`, `real_data.md`, `../README.md`,
`CLOSURE_PRINCIPLE.md`. Method/prior art: FunSearch (Romera-Paredes et al., *Nature* 2023).
