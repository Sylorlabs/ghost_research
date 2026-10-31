# Swarm EXP-14 (RQ A6) — invented-on-invented tasks

**Date:** 2026-07-05  
**Status:** **PASS** — 764 tasks flip solvability only at promotion round ≥ 2; 437 require ≥ 2 invented atoms.

## Question

Is there a task solvable **only after ≥ 2 promotion rounds** (invented-on-invented)?  
That is: a behavioural target whose minimal composition witness needs atoms that did not
exist until the library had grown through at least two forge rounds — and, in the
stronger reading, a composition that chains **two or more invented atoms** together.

## Commands

```bash
cd wcore && zig build -Doptimize=ReleaseFast
cd wcore && zig build run-invent -- exp14
```

Default seed: `0xC0FFEE` (same as all wcore-invent phases).

## Protocol

1. **Promotion snapshots** — `forge.runPromotionSnapshots`: same 8-round info-descriptor
   novelty search as `atomforge` (`pop=90`, `gens=45`, irreducibility gate depth ≤ 3,
   clean filter OUT_R entropy > 0.30). Retain the atom library after each round
   (round 0 = 5 base atoms only).
2. **Task catalogue** — enumerate every distinct composition behaviour up to depth 3 in
   the **final** promoted library (13 atoms). Deduplicate by behavioural fingerprint
   (4 × 28-symbol random streams, Wyhash). Skip base-only chains (solvable at round 0).
3. **Per-round solvability** — for each round `r`, precompute the set of all behaviours
   composable from `lib_r` at depth ≤ 3 (one exhaustive pass per round).
4. **Late flip** — task whose first solvable round is **≥ 2** (needs ≥ 2 promotions).
5. **Invented-on-invented** — late-flip task whose witness chain in the final library
   uses **≥ 2 invented atoms** (indices ≥ 6).

New code: `src/inv_atomforge.zig` (`runPromotionSnapshots`, `analyzeInventedOnInvented`);
phase `exp14` / `inventedoninvented` in `src/inv_main.zig`.

## Promotion result (seed 0xC0FFEE)

| Round | Atoms | Invented |
|-------|-------|----------|
| 0 | 5 | 0 |
| 1 | 6 | 1 |
| 2 | 7 | 2 |
| 3 | 8 | 3 |
| 4 | 9 | 4 |
| 5 | 10 | 5 |
| 6 | 11 | 6 |
| 7 | 12 | 7 |
| 8 | 13 | 8 |

Same trajectory as EXP-13 / `atomforge` (TESTING.md §26).

## Summary metrics

| Metric | Value |
|--------|-------|
| Late-flip tasks (first solvable round ≥ 2) | **764** |
| Invented-on-invented (≥ 2 invented atoms in witness) | **437** |
| **Verdict** | **PASS** |

## Examples

### Late flips (single invented atom — each atom appears at its own round)

| First round | Chain |
|-------------|-------|
| 2 | `inv#2` |
| 3 | `inv#3` |
| 4 | `inv#4` |
| 8 | `inv#8` |

These are the promoted atoms themselves: behaviour `inv#k` is not composable until atom
`#k` exists (round `k−1` in 0-based promotion indexing, or round `k` when counting
invented atoms added).

### Invented-on-invented (≥ 2 invented atoms in witness chain)

| First round | Chain |
|-------------|-------|
| 3 | `inv#1∘inv#3` |
| 4 | `inv#4∘inv#1` |
| 4 | `inv#4∘inv#3` |
| 5 | `inv#5∘inv#1` |
| 8 | `inv#8∘inv#1` |

The earliest strict invented-on-invented composition is `inv#1∘inv#3` at **round 3**
(both `inv#1` and `inv#3` must be in the library; neither alone suffices for this
behaviour at depth ≤ 3).

## Interpretation

- **Promotion is load-bearing for downstream composition.** Hundreds of behaviours in the
  final library's closure are unreachable at round 0–1; they flip in only as invented
  atoms accumulate. This is the wcore analogue of boundary_crossing's T2→T3 compounding
  (a promoted conjunction making the next target solvable inside the budget).
- **Invented-on-invented is real, not vacuous.** 437 tasks require chaining ≥ 2 invented
  atoms. The witness chains are not reducible to a single new primitive — they are
  genuinely **composition over composition**.
- **Round index = dependency depth.** An atom promoted at round `r` is typically first
  solvable at round `r` (as a depth-1 task). Compositions of two invented atoms flip
  later, when the *later* atom in the dependency order enters the library.
- **Honest bound.** Every invented atom is still a short substrate-op program; promotion
  relocates claim C rather than escaping it. EXP-14 shows that **relative** to a growing
  library, compounding across invented primitives is measurable and abundant — not that
  the substrate invents ex nihilo.

## Verdict

| Criterion | Result |
|-----------|--------|
| Any task flipping only at round ≥ 2? | **Yes — 764** |
| Any invented-on-invented (≥ 2 inv atoms)? | **Yes — 437** |
| **RQ A6** | **PASS** |

## Relation to prior work

- `atomforge` / EXP-13 — same promotion loop and 8-round saturation.
- `autonomous_engine.zig` — T2 promotion made T3 solvable (DSL compounding).
- RQ A6 in `RESEARCH_QUESTIONS.md` — now measured affirmatively.