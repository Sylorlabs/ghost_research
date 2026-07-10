# RQ A10 (multi-seed replication, 2026-07-10) — Clifford geometric-product binding vs the XOR band-readout ceiling

**Status:** built, measured, 6 seeds.
**Code:** `sparse_poly_discovery/clifford_binding.zig` (standalone — no existing file touched; all needed environment/encoder code ported inline).
**Data:** `results/a10_clifford_2026_07_10.csv` (one row per seed × arm × predicate).
**Reproduce:**
```
zig build-exe -O ReleaseFast sparse_poly_discovery/clifford_binding.zig \
  -femit-bin=sparse_poly_discovery/bin/clifford_binding
./sparse_poly_discovery/bin/clifford_binding results/a10_clifford_2026_07_10.csv
```
Runtime ~25 s, single-threaded, zig 0.14.1.

This is the ≥6-seed, controlled replication of the single-seed A10 result in
`clifford_binding.md` / `clifford_closure.zig`. Both findings replicate.

## Question

The XOR/bundle VSA readout of the band predicate ("total grid mass in [16,48]") is
provably stuck at chance: the stock encoder XOR-folds all 16 cells into one 8192-bit
vector, collapsing the grid to a parity, and a linear probe over all 8192 bits confirms
the ~0.51 ceiling (`closure_escape_control.md`). A10 asks: does replacing the XOR/GF(2)
bind with a **Clifford geometric-product** bind break that ceiling? The Closure
Principle's escape corollary predicts a genuinely different algebra can act as an
out-of-closure generator.

## Setup

Same grid-cell battery statistics as the original ceiling probe: 16 cells, values iid
uniform 0..6 (mass 0..96, centered ~48), band = mass ∈ [16,48] (primary predicate),
sum ≥ 48 (secondary, linear). 4000 grids per seed, 50/50 train/test, 6 seeds
(0xA102026 + 7919·k), identical grids/labels/readout protocol across arms within a seed.

| arm | encoding | readout |
|-----|----------|---------|
| (a) XOR/bundle baseline | stock `EnvEncoder` recipe (random fillers, XOR fold), bits → ±1 | nearest-prototype; perceptron over raw 8192 bits; standardized logistic |
| (b) Clifford | Cl(13,0), 2¹³ = 8192 blades (same width as XOR — algebra, not budget). Role Pᵢ = random unit multivector; filler = rotor cos(vθ)+sin(vθ)Bᵢ (θ=0.20); bind = geometric product; bundle = sum | **same** standardized logistic as (a) |
| (c) Clifford raw probe | same encoding, **no** per-column standardization | perceptron (scale-invariant — a win cannot be a conditioning gift) |
| control | Hadamard-real: bind = scale ±1 role by value, bundle = sum (real, magnitude-carrying, NOT Clifford) | standardized logistic |
| control | shuffle-label: band labels permuted coherently (train+test), Clifford and XOR arms retrained | standardized logistic |

## Results (6 seeds, band predicate unless noted; mean ± sd, min..max)

```
  arm                          | predicate | mean  ± sd     | min..max
  -----------------------------+-----------+----------------+------------
  majority_rate (chance ref)   | band      | 0.529 ± 0.010  | 0.510..0.537
  xor_prototype                | band      | 0.509 ± 0.011  | 0.498..0.526
  xor_linear_raw   (arm a)     | band      | 0.508 ± 0.013  | 0.484..0.518
  xor_logistic_std             | band      | 0.507 ± 0.012  | 0.487..0.523
  xor_linear_raw               | sum       | 0.510 ± 0.011  | 0.496..0.525
  hadamard_logistic_std (ctrl) | band      | 0.978 ± 0.008  | 0.969..0.991
  clifford_logistic_std (arm b)| band      | 0.976 ± 0.006  | 0.971..0.987
  clifford_linear_raw  (arm c) | band      | 0.978 ± 0.016  | 0.952..0.994
  clifford_logistic_std        | sum       | 0.972 ± 0.006  | 0.965..0.983
  clifford_shuffled_labels     | band      | 0.505 ± 0.011  | 0.491..0.522
  xor_shuffled_labels          | band      | 0.502 ± 0.015  | 0.483..0.521
```

## Controls — all clean

1. **Arm (a) reproduces the known ceiling.** XOR linear probe 0.508 ± 0.013 and
   nearest-prototype 0.509 ± 0.011, matching the published 0.51/0.502 within noise, on
   every seed. The port is faithful; the ceiling is real here too.
2. **Shuffle-label control at chance.** With band labels coherently permuted, the
   Clifford readout falls to 0.505 ± 0.011 (XOR 0.502) — the Clifford encoding/protocol
   does not trivially leak the answer; the 0.976 is signal, not leakage.
3. **Raw probe (arm c) matches the standardized readout (arm b)** — 0.978 vs 0.976 —
   so the escape is not a per-column-standardization/conditioning artifact either
   (the failure mode `clifford_binding.md` caught in the Hadamard arm the first time).

## Verdict

**Ceiling broken — on all 6 seeds, by a wide margin.** Replacing the XOR/GF(2) bind
with the Clifford geometric-product bind takes the band readout from 0.508 (chance)
to 0.976 ± 0.006 (standardized logistic) / 0.978 ± 0.016 (raw perceptron), with the sum
predicate likewise 0.510 → 0.972. Zero overlap between the XOR and Clifford
distributions across seeds.

**With the mandatory deflation (replicated):** the Hadamard-real control — a one-line
bind that merely scales a ±1 role by the cell value — scores 0.978 ± 0.008,
statistically indistinguishable from Clifford (0.976 ± 0.006). The load-bearing
generator is **"leave GF(2) for a magnitude-carrying real algebra,"** not the geometric
product, its grades, or its non-commutativity. On this mass-symmetric predicate,
Clifford earns nothing beyond what plain real binding provides.

## What this means for the Closure Principle

- **Escape corollary: confirmed, now at 6 seeds.** The band predicate lies outside the
  XOR/bundle closure (the ceiling survives standardization, a better readout, and every
  seed); injecting a binding algebra outside GF(2) collapses the plateau in one step.
  The binding algebra itself is a closure lever.
- **Generator specificity: the minimal escape suffices.** The Closure Principle says
  escape needs *a* generator outside the closure — it does not promise fancier
  generators help more. Measured: the cheapest out-of-closure move (real
  magnitude-carrying bind) saturates the task; the elaborate one (Clifford) adds
  nothing here. Same repo pattern as "VSA semantic grounding was non-load-bearing"
  and "more tiers wasn't the lever."

## Honest caveats

- **The band is effectively one-sided.** With cells 0..6, mass centers ~48, so
  mass < 16 is near-impossible and the band reduces to ~`mass ≤ 48` — linearly
  separable once the sum is readable at all. This experiment settles the *ceiling*
  question, not two-sided-quadratic readout.
- **Clifford's distinctive grade-2 (bivector, pairwise xᵢxⱼ) capacity is not exercised
  by any mass-symmetric predicate.** Whether the geometric product beats a plain real
  bind on a genuinely relational/two-sided predicate was tested separately in
  `swarm_exp03_clifford_relational.md` / `clifford_relational.zig`; this replication
  makes no claim there.
- Cl(13,0) Euclidean, single rotor bivector per cell, θ=0.20 fixed, random roles —
  the simplest faithful GA construction, not a tuned one.

## Relation to prior A10 files

`clifford_closure.zig` (single seed, `zig build clifford`) found XOR 0.486–0.503 /
Hadamard 0.974–0.984 / Clifford 0.967–0.978. This standalone replication confirms all
of it at 6 seeds with the two controls (shuffle-label, raw-probe) the original lacked,
without modifying any existing file.
