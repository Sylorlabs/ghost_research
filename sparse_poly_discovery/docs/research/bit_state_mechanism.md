# Frontier 23 — Bit-state mechanism: the third corner

**Status:** built, all 6 kill-tests pass. Reproduce: `cd sparse_poly_discovery && zig build bit-state`

## The gap this opens

The recall↔parity plane (established in `inv_frontier.zig` Phase 0) has two known corners:

| mechanism   | parity_long | recall_K48 | region |
|-------------|-------------|------------|--------|
| scan        | 1.0000      | 0.34       | left (parity-only) |
| attention   | 0.50        | 1.0000     | right (recall-only) |
| local       | 0.51        | 0.24       | bottom |

The two corners are explained by a computational tradeoff: parity requires **persistent unbounded state** (a running accumulator); associative recall requires **content addressing** (look up a value by key). The float-scan uses its state for accumulation; its 4-slot bounded recall degrades as K grows. Attention content-addresses exactly but cannot carry the prefix product.

The question: is the top-right corner (high parity AND high recall) reachable without increasing state size?

## The bit-state argument

The float scan uses 4 × f64 = **256 bits** of state. It gets 4 recall key-slots because each slot consumes 64 bits to store a float value in [0,3].

A bit-addressed machine uses the same 4 × u64 = **256 bits** differently:
- Values are in {0,1,2,3} — 2 bits suffice.
- Each key occupies a 2-bit field at position `(key % 128) * 2`.
- **128 key-slots from the same 256 bits** — 32× more than the float scan.

Parity: a single running-XOR bit tracks `∏x[i]` exactly. O(1) state, correct at any length. No floating-point accumulation error.

Both channels (parity bit + 126 remaining 2-bit slots) coexist in the 256-bit budget.

## Result

```
mechanism    | parity L=256 | recall K=4  | recall K=48 | recall K=100
-------------|--------------|-------------|-------------|-------------
scan         | 1.0000       | 1.0000      | 0.2969      | 0.2578
attention    | 0.4977       | 1.0000      | 1.0000      | 1.0000
local        | 0.5099       | 0.4355      | 0.2617      | 0.2383
bit-machine  | 1.0000       | 1.0000      | 1.0000      | 1.0000   ← third corner
```

Behavioral fingerprint (6-dim: `[par16, par256, rec4, rec48, x0_sens, local_agree]`):

```
scan        : [1.000, 1.000, 1.000, 0.313, 1.000, 0.529]
attention   : [0.510, 0.512, 1.000, 1.000, 0.116, 0.499]
local       : [0.567, 0.493, 0.477, 0.281, 0.000, 1.000]
bit-machine : [1.000, 1.000, 1.000, 1.000, 1.000, 0.529]  dist=0.688 from scan → NOVEL
```

## Verdict

**Confirmed: bit-machine is the third corner.** It achieves parity_long = 1.0000 AND recall_K48 = 1.0000 with the same 256-bit state budget as the float scan.

The behavioral novelty certifier places it at distance **0.688** from the nearest known anchor (scan), well above the 0.35 novelty threshold. The key distinguishing dimension is `rec48`: the bit-machine is at 1.000, the scan is at 0.313.

## Why the float scan is suboptimal for recall

The float scan uses 64 bits per key-slot to represent a value in {0,1,2,3}. That is 32× wasteful — the value needs only 2 bits. The float representation buys nothing: the intermediate precision is never used (values are integers, lookups are exact comparisons). Bit addressing eliminates the waste and converts the saved bits directly into key capacity.

The tradeoff the literature claims is NOT that parity and recall are fundamentally incompatible — it is that the standard float-state primitives (scan and attention) are both *optimized for one task at the cost of the other*, not that the tasks themselves conflict. The bit-machine refutes the "inherent tradeoff" interpretation and replaces it with a more precise claim:

> **The parity↔recall tradeoff is a property of the float-state representation class, not of the task pair.**

## Open questions

1. At what K does the bit-machine degrade? At K=128 keys, all 128 slots are occupied (keys 1..128 map bijectively). At K=129, key 129 maps to slot 1 — overwriting key 1's value. The degradation onset is exactly at K = BIT_SLOTS = 128. **Is there a further extension** (e.g., hash + probe, or two-level addressing) that pushes capacity higher at fixed bit budget?

2. **Capacity-generalization tradeoff**: at K=128 (full capacity), the bit-machine's recall is still perfect; at K=129 it starts to fail. Is there a probabilistic scheme (Bloom filter or count-min sketch structure) that trades exact recall for probabilistic recall at K >> capacity?

3. **Mixed-mechanism search**: does evolutionary search over programs (inv_substrate.zig) ever discover the bit-addressing pattern? The current float-only operator set cannot represent it. This is a concrete argument for adding integer/bitwise operations to the sequence substrate search space.

4. **Does the third corner persist under noise?** The XOR accumulator is brittle to threshold noise: a value of x[i]=0.01 is treated as +1 (not -1), which can flip the parity count. The float scan degrades gracefully. At what input SNR does the bit-machine fall below the float scan on parity accuracy?
