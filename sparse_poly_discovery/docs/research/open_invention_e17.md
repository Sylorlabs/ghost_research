# Experiment E17 — pipeline grammar invention (E5++)

**Status:** complete (built, run, documented). Official run: `e17_run.log`. Reproduce:

```bash
cd sparse_poly_discovery
zig build open-invention-e17 --release=fast
```

## What this tests

E5 fixed a **2-stage** menu (`inner₁ → inner₂ → readout`). RQ5 froze that grammar and transferred to 30 held-out composed targets (24/30). E17 asks:

> Can **meta-search over 2–3 stage grammars** certify **50** composed targets, including **≥2 novel** stage compositions not representable as E5 2-stage templates?

Extended pipeline:

```
inner₁(grid) → T
inner_mid(T, grid) → S    # novel glue (optional 3rd stage)
inner₃(S, grid) → features
readout → logistic
```

**Pass bar:** ≥35/50 certified escape (pipeline test ≥0.90, stage-1 best-linear test <0.70); ≥2 distinct novel 3-stage compositions (`inner_mid ≠ relay`).

## Grammar searched

| layer | operators |
|-------|-----------|
| inner₁ | E5 menu (7): count, sum_all, sum01, inversion, max, min01, mean01 |
| inner_mid | 6 novel: inversion, pair_prod, spread, delta01, bind_T·sum01, parity_sum |
| inner₂/₃ | E5 menu (7): linear, lift_q, half_p, scan_p, bind_xy, bind_abs, bind_max |

Per target: full 2-stage E5 search + 8 **novel probes** + limited 3-stage escape if 2-stage test <0.90. Novel ties within ε=0.015 prefer 3-stage.

## Measured results (grid seed `0xF0235A11CE0FF1CE`, held-out seed `0xE17C0110BA5E50`, ReleaseFast)

### Phase 1 — meta-search training (F-A + F-B)

| family | stage-1 test | best 2-stage test | best 3-stage (novel) | winner |
|--------|--------------|-------------------|----------------------|--------|
| F-A inversion-parity | 0.493 | **1.000** | 1.000 (`count→inversion→half_p`) | 2-stage `inversion→half_p` |
| F-B sum-then-bind | 0.620 | **1.000** | 0.894 (`count→pair_prod→bind_abs`) | 2-stage `sum01→bind_xy` |

Training certified: **2/2**.

### Phase 3 — 50 held-out composed specs (shuffled pool)

| metric | value |
|--------|-------|
| Certified (escape) | **33/50 = 66.0%** |
| Novel 3-stage (distinct, certified) | **3** |
| Certify bar (≥35/50) | **MISSED** (by 2; 17 failures) |
| Novel bar (≥2) | **MET** |

**Novel compositions observed (certified):**

1. `mean(c0,c1) → delta01 → bind_abs`
2. `count≥thr → inversion → scan_p`
3. `sum_all → parity_sum → scan_p`

**Typical failures:** `|c0−c1| > 2.0` specs where stage-1 best test ≈ **0.704** (pipeline solves at 1.000 but escape certification is tight — same cluster as RQ5).

## Verdict

| criterion | result |
|-----------|--------|
| Train A+B | **2/2 certified** |
| Held-out ≥35/50 | **33/50 — FAIL** |
| Novel ≥2 compositions | **3 — PASS** |
| **E17 overall** | **FAIL** (missed certify bar by 2) |

3-stage `inner_mid` grammars **do** certify on held-out targets and produce compositions outside the E5 2-stage template. Residual gap is the same borderline stage-1 cluster RQ5 reported (~0.70 on `bind_abs` routes), not missing 3-stage expressivity.

## See also

`open_invention_e5.zig`, `open_invention_rq5.zig`, `open_invention_e5.md`, `open_invention_rq5.md`, `composed_discovery.md`.