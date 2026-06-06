# Research note: does the controller's competence GENERALIZE, or memorize?

**Status:** built and measured. Reproduce with `zig build eval-gen` (means over
5 seeds; train 10,000 / eval 4,000 steps). The environment is now parameterized
(`environment.zig: TaskParams`); the defaults reproduce the original dynamics
exactly, so `zig build eval` is unchanged (verified: every baseline number is
byte-identical).

## Why this exists

"Intelligence" lives in the gap between train and **held-out** performance — a
policy that only works on the exact regime it trained on has memorized, not
learned. The main eval trains and tests on one regime and cannot see that gap.
Here the greedy `mb_safety` controller is trained on a TRAIN regime, **frozen**
(rules + prototypes locked), and dropped cold into held-out regimes it never saw.

Three numbers per regime:
- **rest_floor** — `always rest` on that regime (how hard the regime is alone).
- **transfer** — the TRAIN-trained, frozen agent, zero-shot on the regime.
- **oracle** — an agent trained *directly on* that regime (adaptation ceiling).

## Results

```
  regime             | rest_floor |   transfer |     oracle
  -------------------+------------+------------+-----------
  train (default)    |       0.00 |       1.35 |       1.35
  faster_shocks      |       0.50 |       2.95 |       3.50
  bigger_shocks      |       2.00 |       2.00 |       2.00
  tight_threshold    |       1.00 |       1.65 |       1.65
  stochastic         |       0.00 |      11.45 |      13.05
```
(fail / 1000 steps; lower is better)

## Findings

1. **The competence generalizes — it did not memorize.** In *every* regime
   `transfer ≤ oracle` (e.g. 2.95 vs 3.50; 11.45 vs 13.05). A controller trained
   only on the default regime is, dropped cold, as good as or better than one
   trained on the target regime. There is no train-regime overfitting.

2. **But what generalizes is a SUB-TRIVIAL competence.** `transfer > rest_floor`
   in every regime: the one-line `always rest` policy beats the learned agent
   everywhere. Generalizing a mediocre policy robustly is still mediocre.

3. **Noise is the failure mode (the attractor-fragility, confirmed).** On
   `stochastic`, rest scores 0.00 but the agent scores **11.45** — far worse.
   The controller works by parking the cell on a recurring deterministic
   attractor (see `control_emergence.md`); injected noise destroys that
   regularity and the readout collapses. Stochasticity is exactly where a
   "predict-and-stay-regular" agent should break, and it does.

4. **Lethal shocks are an unavoidable floor.** On `bigger_shocks`
   (shock_mag 6 ≥ threshold 5) transfer = oracle = rest = 2.00: the shock causes
   the failure *before* any action can respond, so no policy — learned or
   trivial — can prevent it. A useful sanity check that the metric reflects real
   controllability.

## Conclusion

Generalization is **robust** (transfer ≈ oracle across all regimes), which is
genuinely good news: this learner does not overfit its training regime. But the
result reframes the path to higher "intelligence level": the bottleneck is **not**
generalization. It is (a) the controller never discovers the optimal policy (it
loses to `always rest` everywhere), and (b) it is **fragile to stochasticity**.
Raising intelligence here means a better-competence controller (planning, sharper
value learning) and noise-robustness — not better transfer, which is already
solved. The next probe (`expressiveness_ceiling.md`) asks whether the substrate
itself can even *carry* a better world-model.
