# Source A — a real dataset injects out-of-substrate structure

**Status:** built, measured. Reproduce: `cd boundary_crossing && zig build real-data --release=fast` (~22 s, reads `corpus/austen.txt`).

## The point

Same `inject → certify` loop; the out-of-substrate ingredient is now real-world **data** (English prose). The
Closure Principle predicts real data carries structure no fixed algebraic substrate generates. Test: predict
whether the **next** character is a vowel from the **current** one. Substrate = low-degree (≤2) functions of
the current char's 8 bits. The bigram regularity is a fact about *language*, not the byte code — so it should
sit (partly) outside the substrate, captured by a generator learned from the data (the empirical per-character
next-vowel rate), and confirmed on **held-out** text.

## Results

579,288 alphabetic bigrams from Austen; marginal `P(next vowel) = 0.316`.

```
predictor                                  | held-out BALANCED accuracy
marginal baseline (always majority)        |   0.500
SUBSTRATE: low-degree (≤2) byte-bit algebra |   0.619
DATA GENERATOR: empirical bigram rate       |   0.667   ◄ +0.048 over substrate
irreducibility: substrate reconstructs the data feature rate[c] at held-out R² = 0.740
```

## Verdict — honest and nuanced

Real data **is** an out-of-substrate ingredient — and here, **mostly a recombination with a real residual.**
The data generator beats the low-degree byte-bit substrate on held-out text (0.667 vs 0.619, a real +0.048),
but the substrate already reconstructs **74%** of the data feature (R² = 0.740). So most of next-vowel **is**
low-degree-capturable; only the **~26% residual** is genuinely out of the substrate's closure. That residual is
the data-injected part — structure about language the byte code cannot forge.

This mirrors the number-theory result, where **not all** of mathematics was out-of-closure either (Thue–Morse
is a Fourier character). Here, **not all** of language is out-of-substrate; a real residual is. **The certifier's
value is exactly that it measures the split** (≈74% recombination, ≈26% genuine) rather than letting the data
look wholly novel — which is the whole point of separating invention from recombination.

## Honest scope

- This is **statistical (bigram) structure** captured by a learned lookup — the simplest out-of-substrate
  ingredient — and a target where most structure is in-substrate, so the escape is a small residual, not a clean
  break like primality. A richer target (longer context, rarer structure) would give a larger residual; the
  mechanism is the same.
- "Substrate" = low-degree (≤2) of the byte bits; a full-degree readout could memorize the lookup too (it would
  *be* the data generator). The honest claim is about the **low-degree algebraic** closure, stated as such.
- Single corpus, single split. The numbers are stable at this scale (579k bigrams) but corpus-specific.

See: `invention_engine.md`, `world_injection.md`, `superopt.md`, `certifier_filter.md`, `../README.md`,
repo-root `CLOSURE_PRINCIPLE.md`, `RESEARCH_QUESTIONS.md` §J (external-ingredient path).
