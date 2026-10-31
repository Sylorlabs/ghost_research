# Experiment E5 — meta-menu of composed pipelines (inner₁→inner₂→readout)

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery
/opt/zig-0.14.1/zig build-exe -OReleaseFast open_invention_e5.zig \
  -femit-bin=zig-out/bin/ghost_open_invention_e5
./zig-out/bin/ghost_open_invention_e5
```

(`zig build open-invention-e5` is wired in `build.zig`; full `zig build install` may fail on unrelated sibling experiment binaries.)

## What this tests

`composed_discovery.zig` staged inversion-parity and product-parity **by hand**, knowing the decomposition. E5 asks:

> Given black-box labels only, can a **meta-menu** discover which transform on an extracted scalar **S** separates classes — without being told "product" or "spectral"?

Pipeline shape:

```
inner₁(grid) → S
inner₂(S, grid) → feature(s)     # neutral names: lift_q, scan_p, bind_xy, half_p, …
readout        → logistic on [S, inner₂(·)]
```

Selection: argmax validation accuracy; report held-out **test**. Certification (menu_growth discipline):

1. **Escape** — full pipeline test ≥ 0.90 while stage-1 alone (linear on **S**) test < 0.70
2. **Irreducible** — stage-2 feature not reconstructible from linear(**S**), *or* stage-1 ≈ chance while pipeline escapes (behavioral cert for bounded-cell correlation)

## Measured results (seed `0xE5C0110BEF00`, ReleaseFast)

### F-A inversion-parity

```
S = inversion_count(grid)     y = S mod 2
```

| stage | pipeline | val | test |
|-------|----------|-----|------|
| **BEFORE** stage-1 (best linear on S) | inversion → linear(S) | 0.545 | **0.540** |
| **AFTER** discovered | inversion → half_p(S mod 2) | 1.000 | **1.000** |

- Escape: **PASS** (1.000 ≥ 0.90, stage-1 0.540 < 0.70)
- Irreducible: **PASS** (linear(S) R² = −0.006)
- Structure: **PASS** (expected inversion + periodic inner₂; `half_p` or `scan_p`)

### F-B sum-then-bind

```
inner₁ fixed: S = c0 + c1     y = sign((c0−mid)(c1−mid)) > 0
```

| stage | pipeline | val | test |
|-------|----------|-----|------|
| **BEFORE** stage-1 | sum(c0,c1) → linear(S) | 0.405 | **0.431** |
| **AFTER** discovered | sum(c0,c1) → bind_xy(c0·c1) | 1.000 | **1.000** |

- Escape: **PASS** (1.000 ≥ 0.90, stage-1 0.431 < 0.70)
- Irreducible: **PASS** behavioral (stage-1 0.431 ≈ chance 0.500; feature R² = 0.805 — bounded alphabet leaks)
- Structure: **PASS** (`bind_xy`; `lift_q` also acceptable per composed_discovery lesson)

## Verdict

| family | before (stage-1) | after (pipeline) | pass/fail |
|--------|------------------|------------------|-----------|
| F-A inversion-parity | 0.540 | 1.000 | **PASS** |
| F-B sum-then-bind | 0.431 | 1.000 | **PASS** |

**E5 overall: PASS (2/2)** — blind meta-menu recovers composed structure without product/spectral hints; pipeline certified irreducible to stage-1 alone.

## Relation to composed_discovery

- **Family A** replicates inversion-parity: relational inner₁ + periodic inner₂ (`half_p` ≡ parity; `scan_p` ≡ spectral ω≈π).
- **Family B** uses a harder bilinear label than raw product-threshold (where sum² leaked). The discoverer still routes to `bind_xy` — the neutral name for the bilinear bind — with readout `[S, c0·c1]`.
- Feature-level R² for `bind_xy` from linear(S) can be high on small alphabets; behavioral certification (stage-1 at chance, pipeline at 1.0) is the honest witness — same caveat as `composed_discovery.md` Family B.

## See also

`composed_discovery.zig`, `composed_discovery.md`, `structure_discovery.md`, `menu_growth.md`, `operator_inference.md`, `CLOSURE_PRINCIPLE.md`.