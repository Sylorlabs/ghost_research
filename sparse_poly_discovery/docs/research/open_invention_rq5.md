# RESEARCH Q5 — E5 pipeline transfer (freeze grammar → held-out composed targets)

**Status:** built, measured. Reproduce:

```bash
cd sparse_poly_discovery
zig build-exe -OReleaseFast open_invention_rq5.zig \
  -femit-bin=zig-out/bin/ghost_open_invention_rq5
./zig-out/bin/ghost_open_invention_rq5
```

(`zig build open-invention-rq5` is wired in `build.zig`.)

## What this tests

`open_invention_e5.zig` certifies blind pipeline discovery on **two hand-picked families** (F-A inversion-parity, F-B sum-then-bind). RQ5 asks:

> After training on A+B, if we **freeze** the E5 pipeline grammar (7 inner₁ × 7 inner₂, no minting), does it **transfer** to **30 novel** random two-stage label specs never seen in training?

Protocol:

1. **Train** — discover pipelines on composed_discovery F-A + F-B (same labels as E5).
2. **Freeze** — lock menu: `{count, sum_all, sum01, inversion, max, min01, mean01} × {linear, lift_q, half_p, scan_p, bind_xy, bind_abs, bind_max}`.
3. **Transfer** — generate 30 held-out `TwoStageSpec` targets (inner₁ scalar + outer readout), excluding F-A/F-B fingerprints; pre-filter for non-degenerate labels and stage-1 weakness on the spec's inner₁.
4. **Certify** — escape: pipeline test ≥ 0.90 **and** stage-1 best-linear test < 0.70.

**Pass bar:** ≥50% of 30 held-out targets certified.

## Measured results (grid seed `0xF0235A11CE0FF1CE`, held-out seed `0x5110C0110BA5E`, ReleaseFast)

### Phase 1 — training (F-A + F-B)

| family | stage-1 test | pipeline test | discovered | verdict |
|--------|--------------|---------------|------------|---------|
| F-A inversion-parity | 0.493 | **1.000** | inversion → half_p | CERTIFIED |
| F-B sum-then-bind | 0.620 | **1.000** | sum(c0,c1) → bind_xy | CERTIFIED |

Training: **2/2 certified** (matches E5).

### Phase 3 — transfer (30 held-out two-stage specs)

| metric | value |
|--------|-------|
| Certified (escape) | **24/30 = 80.0%** |
| Pass bar (≥50%) | **MET** |
| Typical failures | `|c0−c1| > T` targets where stage-1 best test ≈ 0.704 (bind_abs route nearly sufficient alone) |

Representative passes:

- `mean(c0,c1) → S mod 2` — sum(c0,c1) → scan_p, test 1.000
- `sum_all → S mod 3 > 3/2` — sum_all → scan_p, test 1.000
- `inversion → S mod 5 > 5/2` — inversion → scan_p, test 0.913
- `sum(c0,c1) → S mod 7 > 7/2` — sum(c0,c1) → lift_q, test 1.000

Representative failures (pipeline solves, escape fails):

- `max_cell → |c0−c1| > 2.0` — pipe 1.000 but stage-1 0.704 ≥ 0.70

## Verdict

| phase | result |
|-------|--------|
| Train A+B | **2/2 certified** |
| Transfer (frozen grammar) | **24/30 = 80.0%** |
| **RQ5 overall** | **PASS** |

The frozen E5 meta-menu generalizes to novel composed label specs without grammar growth. Residual failures cluster on bilinear `bind_abs` targets where stage-1 linear readout is borderline (≈0.70) — the menu solves them but escape certification is tight.

## Relation to E5 and composed_discovery

- Training replicates E5 on the same two families; grammar is then frozen (no E4-style minting).
- Held-out specs are **random** `(inner₁, outer_readout)` pairs — not the training fingerprints.
- Transfer confirms the E5 pipeline search is a reusable **composed-discovery engine**, not a two-target memorizer.

## See also

`open_invention_e5.zig`, `open_invention_e5.md`, `composed_discovery.zig`, `composed_discovery.md`, `structure_discovery.md`, `CLOSURE_PRINCIPLE.md`.