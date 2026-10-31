# Swarm EXP-15 (B17 / RQ 17) — atom synergy: {A,B} reaches what neither alone does

**Date:** 2026-07-05  
**Status:** **PASS** (sparse_poly) — emergent escape confirmed; wcore base atoms show **0** irreducible pairs at depth ≤ 3.

## Question

Are there generator pairs **A, B** such that `{A,B}` reaches target behaviours that
**neither** `{A}` **nor** `{B}` (plus composition) reaches? This is research question #17
and the `#38 emergent escape` falsification in `sparse_poly_discovery`.

## Commands

```bash
# Primary measurement (u8 straight-line programs, exact over 256 inputs)
cd sparse_poly_discovery && zig build synergy --release=fast

# wcore cross-check (base atom library, depth ≤ 3, dedicated atom withheld per target)
cd wcore && zig build run-invent -- synergy
```

## sparse_poly_discovery — `synergy.zig`

**Substrate:** 2-register straight-line u8 programs (r0=x, r1=1), affine base
`{XOR, SHL, SHR, NOT}`, nonlinear candidates `{AND, OR, ADD, SUB, MUL}`, exhaustive
search to length **3**, exact over all 256 inputs.

### #53 — closure principle falsification attempt

Affine base reaches **0/5** nonlinear targets. Closure principle survives.

### #38 — emergent (irreducible-pair) escapes

| Target | Synergy pair | Single `base+{X}` |
|--------|--------------|-------------------|
| `x&(x-1)` | **{AND, SUB}** | neither reaches |
| `x\|(x*x)` | **{OR, MUL}** | neither reaches |

**=> 2 emergent (irreducible-pair) escapes.**

Other targets in the set are reachable by a **single** nonlinear op added to base:
`x&(x>>1)` via AND, `x*x` via MUL, `x|(x<<1)` via OR.

### Greedy vs pair-search substrate growth

| Scenario | Greedy one-op | Pair-search | Full op-set |
|----------|---------------|-------------|-------------|
| Rich set (5 targets) | 5/5 | 5/5 | 5/5 |
| Isolated `{x&(x-1)}` | **0/1** | **1/1** | 1/1 |

**Precise condition:** greedy substrate growth misses an emergent escape **iff** the
pair's component ops have **no standalone use** on the available target set. Tuple
search is needed exactly there — not in general.

### Pair-power ranking (targets/5)

| Pair | Reach |
|------|-------|
| OR+MUL | **3/5** |
| AND+OR, AND+SUB, AND+MUL | 2/5 |
| ADD+SUB | 0/5 |

No target requires a **triplet** simultaneously; emergence saturates at depth 2 for
this target set.

## wcore cross-check — base atom library

**Protocol:** For each of the four canonical tasks (`g_xor`, `g_add`, `pk_xor`,
`pk_add`), withhold the dedicated same-named atom and ask whether any **other** single
atom or **pair** of atoms (composed to depth ≤ 3) reproduces the task behaviour
(≥95% stream agreement, 16×28-symbol streams, seed `0xB17`).

```
target g_xor  (excluding g_xor):  no single, no pair synergy
target g_add  (excluding g_add):  no single, no pair synergy
target pk_xor (excluding pk_xor): no single, no pair synergy
target pk_add (excluding pk_add): no single, no pair synergy

=> 0 atom-pair synergies (dedicated atom withheld per target).
```

**Interpretation:** The five hand-built wcore atoms are **complete solvers**, not
decomposable substrate ops. Each task has a dedicated atom; the remaining atoms do
not compose into that behaviour at depth ≤ 3. Atom-level synergy in the
`sparse_poly` sense does **not** appear among the base library.

**Related wcore phenomenon (substrate/search, not atom-pair synergy):**

- `pk_add` is a 3-op RMW **conjunction** that `fuse` never found in 16M evals
  (TESTING.md §20).
- Coevolution with **transfer** assembles `pk_add` reliably by mutating a discovered
  `pk_xor` RMW shape (TESTING.md §23) — synergy at the **mechanism** level, not
  among named base atoms.
- Atom-forge promotion adds **one atom at a time** when irreducible (analogous to
  `greedyGrow()`); no pair-certification step exists yet.

## Summary

| Metric | sparse_poly | wcore base atoms |
|--------|-------------|------------------|
| Synergy pairs found | **2** — {AND,SUB}, {OR,MUL} | **0** |
| Emergent escape confirmed | **YES** | N/A (different substrate) |
| Greedy misses isolated case | **YES** (0/1 → pair 1/1) | Not tested at atom level |
| Pair-search fixes isolated case | **YES** | Not implemented |

## Verdict

| Criterion | Result |
|-----------|--------|
| Irreducible generator pairs exist? | **Yes — 2 pairs** in `synergy.zig` |
| Neither component alone suffices? | **Yes** for both pairs (exact, MAXL=3) |
| Emergent escape real? | **YES** |
| Transfers to wcore atom library? | **No** — base atoms are task-complete solvers |
| Design implication | Atom-forge should **escalate to pair-search** when greedy single-op promotion stalls on components with no standalone use |

## Relation to prior work

- `sparse_poly_discovery/docs/research/emergent_escape.md` — primary measurement
- `sparse_poly_discovery/docs/research/pair_feature_control.md` — synergy transfers to
  control (left_mass + max_cell pair)
- `sparse_poly_discovery/docs/research/pair_search.md` — pair-growth certification
- `wcore/TESTING.md` §20 (`fuse`), §23 (`coevo` transfer) — conjunction assembly
- `wcore/docs/research/swarm_exp13_atom_minimize.md` — atom library compression (EXP-13)
- RQ 17 in `RESEARCH_QUESTIONS.md` — now measured

## Harness

| File | Role |
|------|------|
| `sparse_poly_discovery/synergy.zig` | Primary EXP-15 / #38+#53 experiment |
| `wcore/src/inv_synergy_check.zig` | wcore atom-level cross-check |
| `wcore/src/inv_main.zig` | `synergy` / `exp15` phase |