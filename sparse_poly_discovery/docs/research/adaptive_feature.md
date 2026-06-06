# Adaptive Feature Discovery: Self-Directed Model Repair

**Status:** built, measured. Reproduce: `zig build adaptive-feature`

## Setup

A minimal scalar controller (`ScalarController`) tracks a single feature, learns
per-action deltas, and picks actions minimizing distance to the learned safe midpoint.
After a warmup period it measures **model disagreement**: the fraction of steps where
the feature was within the learned safe range but failure occurred.

An `AdaptiveAgent` wraps this:
1. **Warmup (1500 steps)**: run with feature=sum, accumulate disagree_rate
2. **Assess**: if disagree_rate > threshold → trigger autonomous feature search
3. **Search**: probe each feature for 2000 steps, pick lowest fail/1k
4. **Commit**: switch to discovered feature, continue

Task: DUAL_BAND (total_mass[16,48] + left_mass[6,22]).

---

## Results

### ScalarController baseline (no adaptation)

The stripped-down `ScalarController` with feature=sum achieves **31.23 fail/1k**
on dual-band — significantly better than the full `Agent`'s mb_mass(sum) = 83.31.

**The full Agent's extra machinery (VSA, connectome, rule learning) HURTS scalar
control quality on dual-band.** A simpler controller with only the scalar model
converges faster and has lower steady-state failure rate.

### Adaptive agent (threshold=0.03)

```
seed | disagree_rate | triggered? | final feat    | fail/1k
-----+---------------+------------+---------------+--------
0    | 0.006         | no         | sum           |   3.50
1    | 0.043         | yes        | nonzero_count | 414.25  ← wrong switch
2    | 0.034         | yes        | nonzero_count | 412.75  ← wrong switch
3    | 0.034         | yes        | nonzero_count |  77.88  ← wrong switch
4    | 0.010         | no         | sum           |  12.25
mean |               | 3/5 switch |               | 184.13
```

All triggered seeds switched to `nonzero_count` — which is the WORST long-run
feature for dual-band (main eval: 499.98 fail/1k). The mechanism made things
substantially worse on every triggered seed.

---

## What went right: disagreement detection

The disagree_rate correctly identifies when the model is insufficient:
- Seeds 1-3: disagree_rate 0.034-0.043, correctly flagged
- Seeds 0, 4: disagree_rate 0.006-0.010, correctly not flagged

The signal is real. The mechanism fires on the right seeds.

---

## What went wrong: probe quality

The 2000-step probe consistently picks `nonzero_count` (fail/1k 4.50-15.00 in
probe) even though it is terrible long-term (412-414 fail/1k). Why?

1. **Short probes dominated by exploration.** The first ~200-300 steps of each
   probe are random (safe_n < 30). During random exploration on the seeded grid
   (all cells = 2), the environment rarely fails — the seeded state is safe and
   random actions stay near it initially. `nonzero_count` looks good because the
   seeded grid has all 16 cells non-zero, and a fresh controller exploring randomly
   tends to keep them non-zero.

2. **Feature discrimination requires convergence.** A feature only shows its true
   failure rate after the controller has converged to a stable policy (~1000+ steps).
   At 2000 steps, most probe time is spent in exploration and early learning.

3. **Variance overwhelms signal.** With only 2000 steps, fail/1k estimates have
   ±30 fail/1k variance. The differences between features (left_mass=30.50,
   nonzero_count=7.50 in seed 3 probe) are within that variance.

**Lesson:** a probe must be long enough to (1) get through exploration, (2) converge
to a stable policy, and (3) measure controlled-phase performance. For this task,
that requires ≥10,000 probe steps — 5× what was used.

---

## What this teaches about self-directed improvement

**The disagreement signal is real and detectable.** When the model is wrong,
the agent CAN detect it via unexplained failures. This is the precursor to
self-repair: knowing something is wrong.

**Acting on a weak signal makes things worse.** Switching features based on
noisy 2000-step probes drives the agent to wrong solutions. The cost of a bad
switch (3× worse failure rate) outweighs the potential gain of finding a better
feature.

**Reliable self-repair requires a better evaluation criterion:**
- Much longer probes (≥10,000 steps per feature)
- Or probe-based disagree_rate (not fail/1k) as the selection criterion
- Or correlation-based discovery: look at what features correlate with failures
  (direct causal analysis, not black-box probing)

**The simplicity principle:** the `ScalarController` (no VSA) achieves 31.23
fail/1k vs the full `Agent`'s 83.31 on the same task. For scalar feature
control, stripping out the complex machinery improves performance. Complexity
is not free.

---

## Design implications

For any system that uses model disagreement to trigger self-repair:

1. **Warmup before measuring**: need enough steps for the model to converge
   before disagreement is meaningful (used: 1500 steps; sufficient here)
2. **Long probes before switching**: need enough steps for probes to converge
   (needed: ≥10,000; used: 2000; result: wrong switches)
3. **Cost of switching**: bad switches are expensive; be conservative
4. **Causal analysis vs probing**: correlating failures with feature values
   may be more efficient than running probes for each candidate feature

See: `dual_band.md`, `feature_discovery.md`, `closure_escape_control.md`.
