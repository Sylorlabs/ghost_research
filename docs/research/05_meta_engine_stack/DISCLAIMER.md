# Disclaimer — Thread 05: Meta-Engine Stack (2026-05-20 to 2026-05-22)

**This thread contains the main architectural development.** Most of the
core engine code was written and validated here. Results are real and
reproducible but some early readings were later corrected.

## Corrected results

- **`tier1_meta_engine.md` initial report:** first stated HALT(tier-1) because the
  MMP did not beat the hand-coded baseline. A later equal-budget re-run corrected this:
  seed 0x1111 champion validated at mean 37.68 vs baseline 28.13 on 64-seed holdout.
  The file was updated same day. Read the verdict section, not the initial summary line.
- **200-iter budget refutation:** running Tier-1 at 200 iterations made holdout WORSE
  for all 4 seeds. Anchor overfitting dominates past 24 iterations. Do not extend
  the budget without adding anchor seeds. This is documented in `tier1_meta_engine.md`.
- **"44.30 ceiling" language:** the ceiling was broken by monotone-retry + parallel
  to 47.16 (F00D sequential, gen 4) within the same thread. See `monotone_parallel.md`.
  Any document that says "44.30 is the ceiling" was written before that run.

## What remained consistent

- Tier-2 MMMP approaches Tier-1 but does NOT exceed it at single-machine budgets.
  This held across all five v2 approaches (shaped fitness, curriculum, constrained init,
  expanded opcodes, combined). Do not report Tier-2 as "working" — report it as
  "responsive to engineering, not competitive."
- MUL-necessity conjecture first appeared here (mul_free_challenge.md) and was
  confirmed by 7 independent conditions in Thread 06.
- Bit-tape inventor (bittape_inventor_2026_05_22.md) correctly identified that the
  fitness metric was being gamed — per-bit reform was tested in Thread 06 Exp1.

## Versions within this thread

| Engine | Filename indicator | Key capability added |
|--------|--------------------|---------------------|
| Engine-1 | `meta_engine.md` | Tier-0 MetaProgram; first run overfits |
| Engine-2 | `tier1_meta_engine.md`, `tier2_meta_meta_engine.md` | Tier-1 MMP beats baseline; Tier-2 approaches |
| Engine-2 v2 | `invention_engine_v2.md` | 5 combined approaches; none broke 44.30 |
| Engine-2 monotone | `monotone_parallel.md` | Broke 44.30 to 47.16 |
| Engine-3 | `recursive_engine_phase_abc_2026_05_21.md` | 47.2299 → 47.3244 with LMG |
