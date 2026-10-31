# Experiment E20 — POET curriculum stress test (E12/RQ8 hardened)

**Status:** built and measured. Reproduce:

```bash
cd sparse_poly_discovery && zig build open-invention-e20 --release=fast
```

Direct compile (skips broken sibling install artifacts):

```bash
zig build-exe -OReleaseFast open_invention_e20.zig -femit-bin=zig-out/bin/ghost_open_invention_e20
./zig-out/bin/ghost_open_invention_e20
```

## What this is

Long-horizon stress test for the RQ8 hard-mutator POET fix. Extends the 50-round RQ8 probe to **200 rounds** and applies a stricter pass bar to verify the curriculum stays rich and the solve rate stays in band under sustained coevolution.

Each round (200 × 3 proposals):

1. **MUTATE** — RQ8 hard mutators: Walsh-high (deg 3–5) or composed AND `atom_a ∧ atom_b`
2. **NOISE** — 10% training-label flip; held-out scored on clean ground truth
3. **SOLVE** — RQ8 blind escalate: operator menu → world pool → pair readout
4. **CURATE** — retain targets with coverage ∈ [0.10, 0.90]
5. **TRACK** — curriculum size, rolling solve rate, solved frontier depth (E12 ratchet pattern)

**Pass bar (stress test):**

| Criterion | Threshold |
|-----------|-----------|
| Curriculum size ≥20 | for ≥**50 consecutive** rounds |
| Solve rate | **30–60%** |

## Measured results (seed `0xE20C0FFEE12A11CE`, 2026-06-29)

```
rounds:                      200
proposals:                   600
solved (≥0.90):             304
solve rate:                  50.7%
curriculum size (final):     48
curriculum peak depth:       18
solved frontier depth:       17
rounds curriculum≥20:       187/200
max consecutive curriculum≥20: 187/50
consecutive curriculum pass: PASS
solve rate pass:             PASS
stress test pass:            PASS
```

### Curriculum / frontier trace (every 20 rounds)

| Checkpoint (round) | Curriculum size | Solved frontier | Solve rate |
|--------------------|-----------------|-----------------|------------|
| 20 | 28 | 12 | 41.7% |
| 40 | 48 | 17 | 53.3% |
| 60 | 48 | 17 | 47.8% |
| 80 | 48 | 17 | 50.8% |
| 100 | 48 | 17 | 50.7% |
| 120 | 48 | 17 | 50.6% |
| 140 | 48 | 17 | 51.0% |
| 160 | 48 | 17 | 51.5% |
| 180 | 48 | 17 | 50.2% |
| 200 | 48 | 17 | 50.7% |

### Early-round samples

| Round | Target | Coverage | Solved |
|-------|--------|----------|--------|
| 0 | χ(0x69,d4) | 1.000 | yes |
| 0 | walsh∧monomial | 0.704 | no (in band) |
| 0 | oriented∧walsh | 0.948 | yes |
| 1 | walsh∧sum_mod | 0.939 | yes |
| 3 | walsh∧monomial | 0.733 | no (in band) |

## Verdict

**PASS on stress test** — hard mutators sustain a full POET curriculum over 200 rounds:

| Metric | E12 baseline | RQ8 (50r) | E20 (200r) |
|--------|--------------|-----------|------------|
| Solve rate | 100% | 44.0% | **50.7%** |
| Final curriculum | 1 | 48 | **48** |
| Curriculum≥20 sustained | ~0 | 44/50 total | **187/200 consecutive** |
| Solved frontier depth | 7 | 13 | **17** |

**Key findings:**

- Curriculum saturates at **48** (MAX_CURRICULUM cap) by round ~40 and holds through round 200.
- Solve rate stabilizes at **~51%** — inside the 30–60% band for the entire second half of the run.
- **187 consecutive rounds** with curriculum≥20 — far above the 50-round pass bar.
- Solved frontier depth reaches **17** (composed-AND tiers); curriculum peak depth **18** (in-band hardest targets).
- Walsh-high singletons still solve at ~1.00 (~15% of stream); composed AND targets dominate the in-band population — same honest caveat as RQ8.

## Code map

| File | Role |
|------|------|
| `open_invention_e20.zig` | 200-round stress loop, consecutive-streak tracking, E12 frontier ratchet |
| `open_invention_rq8.zig` | Hard mutators, noisy-label solver, pair readout (reused via import) |
| `open_invention_e12.zig` | Baseline POET + frontier depth ladder (referenced) |
| `unified_invention.zig` | Shared certifier threshold (`COVER_THRESHOLD`) |
| `build.zig` | `open-invention-e20` step |

See also: `open_invention_e12.md`, `open_invention_rq8.md`, `open_invention_experiments.md`.