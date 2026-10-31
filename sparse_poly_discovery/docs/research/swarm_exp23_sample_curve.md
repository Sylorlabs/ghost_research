# Swarm EXP-23 (F43) — Hidden non-salient feature: minimum failure-labels for supervised recovery

**Date:** 2026-07-05  
**Status:** measured  
**RQ:** F43 — sample-complexity curve for supervised recovery vs decoy variance

## Command

```bash
cd sparse_poly_discovery && zig build-exe -OReleaseFast swarm_exp23_sample_curve.zig && ./swarm_exp23_sample_curve
# or: zig build swarm-exp23 --release=fast
```

## Background (from `feature_discovery.md` Level 3)

The hidden-feature task rigs cell 0 as the true safety direction `e_0` while cells 8–15 form a **loud correlated decoy block** independent of failure. Prior results (20k samples, all labels):

| method | cosine to `e_0` |
|--------|-----------------|
| PCA (unsupervised variance) | **0.000** — misled by decoy |
| supervised, one-sided (`cell0 > 4`) | **0.999** — recovered |
| supervised, two-sided band | 0.139 — slab defeats linear supervision |

**F43 question:** how many **labeled failure steps** does one-sided supervised credit-assignment need before it recovers `e_0`? PCA needs zero labels but finds nothing; supervised needs labels but works.

## Harness

- **Pool:** 50,000 synthetic grids (same generative model as `dynamics_probe.zig` hidden-feature block)
- **Label:** one-sided failure = `cell0 > 4` (~28.8% positive rate; 14,378 failures in pool)
- **PCA:** top eigenvector of 16×16 cell covariance (label-free; identical at every sweep point)
- **Supervised:** direction = `mean(fail) − mean(safe)` using `n` **randomly subsampled failure labels**; safe mean from all remaining unlabeled safe samples
- **Seeds:** 12 (`0xF4300000 + s·0x9E37`)
- **Recovery threshold:** cosine ≥ 0.90 (full-pool reference: 0.995; `feature_discovery.md` reports 0.999)

> **Note:** `adaptive-feature` and `correlation-discover` target dual-band *control* discovery, not this hidden-direction recovery task. They have no failure-label sweep. This experiment uses the Level 3 hidden-feature harness directly (`swarm_exp23_sample_curve.zig`).

## Results — label-count sweep {0, 10, 50, 200, 1000}

| n_fail_labels | PCA cosine | supervised cosine | recovered (≥0.90)? |
|---------------|------------|-------------------|---------------------|
| **0** | **0.000** | — | PCA blind |
| **10** | 0.000 | **0.441** | no |
| **50** | 0.000 | **0.641** | no |
| **200** | 0.000 | **0.825** | no |
| **1000** | 0.000 | **0.903** | **YES** |

Reference (not in sweep): all 14,378 failure labels → cosine **0.995**.

## Key findings

### 1. PCA is flat at zero — decoy variance always wins

PCA cosine = **0.000** across all seeds regardless of label budget. This reproduces `feature_discovery.md` and confirms Level 2 PCA was circular: unsupervised variance tracks the decoy block (cells 8–15), not `e_0`.

### 2. Supervised recovery is sample-hungry but monotone

Supervised cosine grows smoothly with labeled failures:

```
n=10   → 0.441  (above chance ~0.25, but far from recovery)
n=50   → 0.641
n=200  → 0.825  (approaching but below threshold)
n=1000 → 0.903  (crosses 0.90)
n=all  → 0.995  (full recovery)
```

The curve is **monotone** — no instability from decoy variance once failure labels are present. Noise at low-n comes from estimating `mean(fail)` from few high-cell0 samples while `mean(safe)` is well-estimated from ~35k safe points.

### 3. Phase transition label count: **1000**

First sweep point reaching cosine ≥ 0.90: **1000 failure labels**.

Interpolating between 200 (0.825) and 1000 (0.903), the 0.90 crossing lies near **~900–1000** labels — roughly **7% of the failure pool** or **2% of total samples**.

Below 200 labels, supervised direction is detectable (above chance) but **not reliable** for control-grade recovery.

### 4. PCA vs supervised crossover: **10 labels**

- **vs PCA:** supervised exceeds PCA at **n=10** (0.441 > 0.000). Trivial in this task since PCA is exactly blind.
- **vs chance (~0.25):** also **n=10** (0.441 > 0.25).

Meaningful *control-grade* crossover (supervised ≥ 0.90) aligns with the phase transition at **1000**, not 10. The gap between "above chance" (10 labels) and "recovered" (1000 labels) is the sample-complexity wall for this non-salient feature.

## Reading

| regime | n_fail_labels | what happens |
|--------|---------------|--------------|
| unsupervised | 0 | PCA → decoy; cosine 0.000 |
| weak supervision | 10–50 | supervised beats PCA/chance; direction partial |
| pre-threshold | 200 | cosine 0.825; not yet control-grade |
| **phase transition** | **1000** | cosine crosses 0.90 |
| saturated | ~14k (all) | cosine 0.995 ≈ full recovery |

**Bottom line:** For a non-salient one-sided feature hidden behind a loud decoy, **unsupervised PCA never recovers** (0 labels, 0.000 cosine). Supervised credit-assignment needs **~1000 failure labels** (~2% of a 50k pool) to cross the recovery threshold — an order of magnitude more than "above chance" (10 labels), but still far less than the full failure population. The honest ladder from `feature_discovery.md` holds: supervised construction works for non-salient monotone features, but its **sample cost** is real and measurable.

## Connection

- `feature_discovery.md` — Level 3 non-circular test; PCA 0.000 / supervised 0.999 at full labels
- `RESEARCH_QUESTIONS.md` F43 — this note closes the sample-complexity curve
- F45 (decoy-to-signal variance ratio) — natural follow-up: sweep decoy amplitude and re-map the 1000-label threshold