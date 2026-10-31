# EXP-6: Learned candidate policy for unified invention

**Status:** built, measured, **PASS** (certify rate unchanged; ≥1.4× certify speedup).  
**Reproduce:** `cd sparse_poly_discovery && zig build learned-guide-test --release=fast` (~2–4 min).

## Question

Can a **minimal perceptron** trained on verifier labels (CERTIFIED vs failed escape) guide
`certify()` calls in the unified invention loop (forge → menu → world) without changing the
7/7 certification rate?

This closes the “learned guide” rung from `verification_learning.md` / EXP-4 on the Fork-5
substrate (`unified_invention.zig`), complementing EXP-2’s pair router.

## Design

### Features (3-dim, no hidden layer)

| Feature | Source |
|---------|--------|
| `probe_corr` | Cheap held-out logistic acc on single-feature probe (`valAccSingle`) |
| `hardness_class` | `0=single_sufficient`, `1=unknown`, `2=q38_compound` from mono+extremal probes |
| `inner_type` | `0=monomial … 5=world_sign` (feature tag enum) |

### Guide (`learned_candidate_guide.zig`)

- **Score:** linear perceptron `z = w·[probe_corr, hardness, inner] + b`
- **Train:** online perceptron on verifier labels only (`cert.ok` → +1, else −1); lr=0.15
- **Log:** every certify attempt → `{features, certified, cov_after, r2}`

### Guided search

| Stage | Baseline | Guided |
|-------|----------|--------|
| Monomial forge | Scan all masks with full `fitLogit`, certify **best** | Cheap `valAccSingle` on all masks; rank by `2·probe_corr + perceptron`; certify top-k (k=5, **k=1** if corr≥0.95) |
| Operator menu | 3 probes + 1 certify on argmax | Same (only 3 candidates) + log/train |
| World pool | Certify **all** 12 (6 primes × sum/sign) | Probe all 12; rank; certify top-k (k=3, **k=1** if corr≥0.85) |

### Bootstrap (routing battery)

Before the 7-target run, train the guide on three hidden targets (same protocol as
`verify_learn_invent.zig` Phase 2b):

1. `parity_of_count`
2. `sum_mod` (mod 7)
3. `monomial_sign` (φ{c3})

## Measured results (2026-07-06, seed `0xF0235A11CE0FF1CE`, `--release=fast`)

```
── Baseline (exhaustive certify) ──
  unified solved: 7/7
  certify calls:  16
  forge fits:     761
  probe calls:    18

── Guided (perceptron forge-k=5 world-k=3) ──
  unified solved: 7/7
  certify calls:  11
  forge fits:     0
  probe calls:    638

target                           | base cov | guided cov | source
--------------------------------+----------+------------+--------
T1 sign φ{2,5}     (deg2)        | 1.000    | 1.000      | forge
T2 sign φ{1,3,6}    (deg3)       | 1.000    | 1.000      | forge
T3 sign φ{0,4,5,7}  (deg4)       | 1.000    | 1.000      | forge
T4 sign(c3−MID)     (deg1)       | 1.000    | 1.000      | base
T5 parity-of-count  (≠mono)      | 1.000    | 1.000      | menu
T6 oriented v1>v0   (≠mono)      | 1.000    | 1.000      | base
T7 sum(g) % 7 = 0   (world)      | 1.000    | 1.000      | world
```

### Cost breakdown (certify calls)

| Method | certify | forge logistic fits |
|--------|---------|---------------------|
| **Baseline** | **16** | **761** |
| **Guided** | **11** | **0** |

**Speedup (certify): 1.45×** (16 → 11).  
**Forge-fit elimination:** 761 → 0 (replaced by cheap single-feature probes).

Guide learned **8** perceptron steps after bootstrap (3 routing targets + 7-target run).

## Verdict

| Criterion | Result |
|-----------|--------|
| Certify rate unchanged? | **YES** — 7/7 solved, 7/7 per-target cov match |
| Speedup factor | **1.45×** certify calls; **∞** on forge fits (761→0) |
| **PASS/FAIL** | **PASS** (bar: unchanged certify + ≥1.4× certify speedup) |

## Honest limits

- **Speedup is modest on certify count** because baseline already certifies only once per
  successful forge/menu stage; the big win is **world pool** (12 exhaustive certifies → 1–3
  guided) and **eliminating 761 forge logistic fits**.
- **Perceptron is tiny (4 weights)** — no MLP; ranking is probe-dominated (`2·corr + score`).
  Sufficient here because verifier labels correlate with `probe_corr`.
- **Bootstrap required** — cold-start guide on routing battery prevents world-pool thrashing on
  saturated targets.
- **Single seed** — 7-target menu is deterministic at this seed; multi-seed sweep not run.
- Operator menu (3 candidates) sees no certify savings.

## Files

| File | Role |
|------|------|
| `sparse_poly_discovery/learned_candidate_guide.zig` | Perceptron + logging + hardness classify |
| `sparse_poly_discovery/unified_invention.zig` | Guided forge/menu/world + `runGuidedBenchmark` |
| `sparse_poly_discovery/learned_guide_test.zig` | EXP-6 harness |
| `boundary_crossing/verify_learn_invent.zig` | Parent VERIFY-LEARN + routing battery reference |

## See also

- `swarm_exp02_pair_router.md` — guided pair routing (EXP-2)
- `swarm_exp04_rq1_gap.md` — RQ1 gap + learned-guide thesis
- `verification_learning.md` — AlphaZero/RLVR guide over verifier labels
- `verify_learn_invent.md` — English routing + hardness escalation