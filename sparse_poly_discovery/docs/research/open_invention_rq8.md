# RESEARCH Q8 — E12 hard mutators (POET curriculum fix)

**Status:** built and measured. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-rq8 --release=fast
```

Direct compile (skips broken sibling install artifacts):

```bash
zig build-exe -OReleaseFast open_invention_rq8.zig -femit-bin=zig-out/bin/ghost_open_invention_rq8
./zig-out/bin/ghost_open_invention_rq8
```

## What this is

Fix for E12's empty POET curriculum: replace easy `TargetSpec` mutators with **hard mutators** that keep solve-rates in the [0.10, 0.90] band.

Each round (50 minimum, 3 proposals/round):

1. **MUTATE** — Walsh-high mask (deg 3–5) or composed AND `atom_a ∧ atom_b` (2-feature required)
2. **NOISE** — flip 10% of training labels; held-out scored on clean ground truth
3. **SOLVE** — blind escalate: operator menu (top-3 Walsh + spectral + Clifford) → world pool → pair readout for composed targets
4. **CURATE** — retain targets with coverage ∈ [0.10, 0.90]

**Pass bar (sustained growth):**

| Criterion | Threshold |
|-----------|-----------|
| Curriculum size ≥10 | for ≥30 rounds |
| Solve rate | 40–80% |

## Measured results (seed `0xA08C0FFEE12A11CE`, 2026-06-30)

```
rounds:                 50
proposals:              150
solved (≥0.90):        66
solve rate:             44.0%
curriculum size (final): 48
curriculum peak depth:   13
rounds curriculum≥10:  44/50
curriculum pass:         PASS
solve rate pass:         PASS
sustained growth:        PASS
```

### Curriculum size trace (every 10 rounds)

| Checkpoint (round) | Curriculum size |
|--------------------|-----------------|
| 10 | 14 |
| 20 | 25 |
| 30 | 40 |
| 40 | 48 |
| 50 | 48 |

### Early-round samples

| Round | Target | Coverage | Solved |
|-------|--------|----------|--------|
| 0 | monomial∧sign_mod | 0.951 | yes |
| 0 | walsh∧walsh | 0.725 | no (in band) |
| 1 | χ(0x61,d3) | 1.000 | yes |
| 4 | walsh∧sum_mod | 0.967 | yes |
| 5 | walsh∧sign_mod | 0.971 | yes |

## Verdict

**PASS on sustained growth** — hard mutators fix E12's curriculum collapse:

| Metric | E12 baseline | RQ8 hard mutators |
|--------|--------------|-------------------|
| Solve rate | 100% | **44%** |
| Final curriculum | 1 | **48** |
| Rounds with curriculum≥10 | ~0 | **44/50** |

**Key mechanisms:**

- **10% label noise** — training on noisy labels, evaluation on clean held-out drops coverage below mastery for composed targets
- **Walsh deg 3–5** — high-degree masks resist single monomial escape; menu Walsh discovery still solves isolated Walsh targets
- **Composed AND** — `walsh∧walsh` and similar pairs land at ~0.70–0.77 (in band); single-feature readout cannot certify; pair compose closes some but not all

**Honest caveat:** Walsh-high singletons (χ with deg 3–5) still solve at ~1.00 when mutated into the stream (~15% of proposals). The curriculum is dominated by composed AND failures — exactly the 2-feature-composition stress test intended.

## Code map

| File | Role |
|------|------|
| `open_invention_rq8.zig` | Hard-mutator POET loop, noisy-label solver, pair readout |
| `open_invention_e12.zig` | Baseline (easy mutators, empty curriculum) |
| `unified_invention.zig` | Shared certifier threshold (`COVER_THRESHOLD`) |
| `build.zig` | `open-invention-rq8` step |

See also: `open_invention_e12.md`, `open_invention_experiments.md` (E12 fix item).