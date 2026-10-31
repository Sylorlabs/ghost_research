# Swarm EXP-13 (RQ A4) — atom-set minimisation after promotion

**Date:** 2026-07-05  
**Status:** **PASS** — promoted library compresses; 2 redundant atoms; coverage preserved.

## Question

After atom-forge promotion rounds, can the atom set be **minimised without losing
behavioural coverage**? Specifically: are any promoted atoms later **reducible to
other promoted atoms** (redundant relative to the enlarged library)?

## Commands

```bash
cd wcore && zig build run-invent -- atomforge      # promotion baseline (~7 s)
cd wcore && zig build run-invent -- atomminimize   # promotion + ablation (~7 s)
```

Default seed: `0xC0FFEE` (same as all wcore-invent phases).

## Protocol

1. **Promotion** — `forge.runPromotion`: 8 rounds of info-descriptor novelty search
   (`pop=90`, `gens=45`), irreducibility gate at composition depth ≤ 3, clean filter
   (OUT_R entropy > 0.30). Same protocol as `atomforge` (TESTING.md §26).
2. **Drop-each-atom ablation** — for each atom `i`, drop it and test whether its
   behaviour is composable from the other 12 atoms at depth ≤ 3 (`reducibleLib`,
   `MATCH_THRESHOLD=0.95`, 8×28 random streams).
3. **Greedy minimal set** — iteratively remove reducible atoms until fixed point.
4. **Coverage check** — every full-library atom behaviour must be composable from the
   minimal set at depth ≤ 3.

New code: `src/inv_atomforge.zig` (`runPromotion`, `dropAblation`, `greedyMinimal`,
`coveragePreserved`); phase `atomminimize` in `src/inv_main.zig`.

## Promotion result (seed 0xC0FFEE)

| Round | Atom # | Length | Status at promotion |
|-------|--------|--------|---------------------|
| 0 | #6 inv#1 | 5 | irreducible vs prior 5 |
| 1 | #7 inv#2 | 5 | irreducible vs prior 6 |
| 2 | #8 inv#3 | 2 | irreducible vs prior 7 |
| 3 | #9 inv#4 | 3 | irreducible vs prior 8 |
| 4 | #10 inv#5 | 3 | irreducible vs prior 9 |
| 5 | #11 inv#6 | 5 | irreducible vs prior 10 |
| 6 | #12 inv#7 | 5 | irreducible vs prior 11 |
| 7 | #13 inv#8 | 6 | irreducible vs prior 12 |

**Promoted library:** 13 atoms (5 base + 8 invented).

## Drop-each-atom ablation

| Atom | Label | Drop ablation |
|------|-------|---------------|
| #1 | g_xor | ESSENTIAL |
| #2 | g_add | ESSENTIAL |
| #3 | pk_xor | ESSENTIAL |
| #4 | pk_add | ESSENTIAL |
| #5 | shift | ESSENTIAL |
| #6 | inv#1 | ESSENTIAL |
| #7 | inv#2 | **REDUNDANT** |
| #8 | inv#3 | **REDUNDANT** |
| #9 | inv#4 | ESSENTIAL |
| #10 | inv#5 | ESSENTIAL |
| #11 | inv#6 | ESSENTIAL |
| #12 | inv#7 | ESSENTIAL |
| #13 | inv#8 | ESSENTIAL |

All 5 base atoms remain essential. Redundancy appears only among **promoted**
atoms — and only for the two shortest inventions (lengths 5 and 2, rounds 1–2).

## Summary metrics

| Metric | Value |
|--------|-------|
| Promoted set size | **13** |
| Redundant atoms | **2** (inv#2, inv#3 — atoms #7, #8) |
| Minimal set size | **11** |
| Coverage preserved | **YES** |
| Library compression | **PASS** |

**Minimal set (1-based indices):** 1 2 3 4 5 6 9 10 11 12 13  
(removes atoms #7 and #8; 18% compression).

## Interpretation

- **Relative irreducibility is not absolute.** Atoms #7 and #8 were certified
  irreducible *at promotion time* (vs the library then), but become composable once
  later atoms enlarge the vocabulary. This is the expected shape of RQ A4: promotion
  is a *sequential* certificate, not a global basis.
- **Base atoms are not redundant** — the 5 hand-built stage solvers each implement a
  distinct behavioural family that the invented substrate-op atoms do not subsume at
  depth ≤ 3.
- **Compression is modest** — 2/13 redundant, not a large fraction. Most promoted
  atoms remain essential even after the full 8-round run. The library is *nearly*
  minimal, not bloated.
- **Coverage is preserved** — the 11-atom minimal set still composes every behaviour
  the 13-atom library could express. Minimisation is lossless under the depth-3
  composition semantics.

## Verdict

| Criterion | Result |
|-----------|--------|
| Redundant atoms exist? | **Yes — 2** |
| Minimal set < promoted set? | **Yes — 11 < 13** |
| Coverage preserved? | **Yes** |
| **Library compression** | **PASS** |

EXP-13 answers RQ A4 affirmatively: **yes, the promoted atom set can be minimised**
without losing coverage. The mechanism is sound but the redundancy rate is low —
promotion adds mostly essential atoms, with occasional early inventions later
absorbed by the growing library.

## Relation to prior work

- `atomforge` / TESTING.md §26 — promotion loop and 8-round saturation.
- `inv_atomforge.zig` kill-test — distinct-count is irreducible to base, reducible
  after addition (the invent-then-recurse pattern).
- RQ A4 in `RESEARCH_QUESTIONS.md` — now measured, not open.