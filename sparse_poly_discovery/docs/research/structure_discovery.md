# Frontier 24 — autonomous structure discovery: one blind selector over (inner ⊗ outer)

**Status:** built, measured. Reproduce: `cd sparse_poly_discovery && zig build structure-discovery --release=fast`
(~35 s; ReleaseFast. The default `zig build structure-discovery` runs Debug and takes ~3 min.)

## The gap this closes

The project built every PIECE of a structure discoverer, one frontier at a time, but never the
loop that uses them blind:

- `spectral_discovery.md` / `period_candidate_search.md` — the accuracy-grid spectral **outer**
  operator that finds a periodic generator's ω (parity, period-3, the sparse AND-composition).
- `antisymmetric_relational.md` — the Clifford grade-2 bivector **inner** feature `sin(θ(v1−v0))`
  that exposes an oriented relation a symmetric product cannot.
- `concentration_control.md` / `representation_discovery.md` — the order statistic `max()` as an inner.
- `composed_discovery.md` — staged (inner, outer) discovery, but staged **by hand**, knowing the
  decomposition in advance.

Three docs name the same next step explicitly. `operator_inference.md`: *"the composition detector
then becomes a search: `argmax_{inner_Q} spectral_acc(Q)`."* `composed_discovery.md`: *"a search over
(inner transform, outer operator) pairs — itself a closure problem one level up."*
`period_candidate_search.md`: *"if neither period is known…"* This is that loop, assembled and run
blind across the whole predicate zoo at once.

## The discoverer

A fixed **menu**: inner transforms × outer operators.

- inner (grid → scalar): `count`, `sum`, `max`, `inversion-count`, `oriented(0,1)` = the Cl(2,0)
  grade-2 blade `sin(θ(v1−v0))`, `product(0,1)` = `c0·c1`. The two relational inners are hardwired
  to the focal pair (0,1).
- outer (scalar → label): `threshold` (logistic on `s`), `spectral` (accuracy-grid `cos(ω·s)`,
  ω chosen by validation), `poly2` (logistic on `[s, s²]`).

For each black-box predicate the loop fills the full (6 × 3) accuracy matrix and selects the pair by
**held-out** accuracy — a 3-way split: fit outer params on **train**, select (inner, outer) and ω on
**validation**, report **test**. (This tightens `period_candidate_search`, which selected ω on the
eval set.) Ties within 0.01 val break toward the simpler outer (threshold > poly2 > spectral), an
Occam preference so a flexible outer can't claim a monotone predicate that a threshold already
separates.

**The deeper test, one level up.** The menu is itself a closed set. So the zoo includes a deliberately
**out-of-menu** predicate: a degree-2 relation on a *hidden* pair (2,5), while the menu's relational
inners are pinned to the focal pair (0,1). A working discoverer must route every in-menu predicate to
its true structure (the escape) **and fail on the out-of-menu one** (the ceiling) — exactly while a
richer closed substrate (degree-2 over raw cells) cracks it, naming the generator the menu lacks.

## Results

Test accuracy; `*` marks the blind argmax pick. Closed-substrate baselines: `linear-raw` (cell values),
`poly2-raw` (cells + squares + all pairwise products).

```
predicate (chance)           discovered (inner, outer)   test   linear-raw  poly2-raw   verdict
─────────────────────────────────────────────────────────────────────────────────────────────────
P0 parity-of-count  (0.502)  (count,     spectral)       1.000     0.504       0.498     ESCAPE
P1 sum-threshold    (0.521)  (sum,       threshold)      1.000     1.000       1.000     routed; linearly solvable
P2 max-threshold    (0.771)  (max,       threshold)      1.000     0.802       0.895     ESCAPE
P3 inversion-parity (0.504)  (inversion, spectral)       1.000     0.509       0.500     ESCAPE
P4 oriented v1>v0   (0.572)  (oriented,  threshold)      1.000     1.000       1.000     routed; linearly solvable
P5 product-thresh   (0.821)  (product,   threshold)      1.000     1.000       1.000     routed; linearly solvable
P6 AND-composition  (0.888)  (count,     spectral)       1.000     0.880       0.887     ESCAPE
P7 HIDDEN pair (2,5)(0.508)  (count,     spectral) 0.591 ← best   0.512       1.000     CEILING + escape
```

Representative matrices (the routing is the evidence — only the true cell lights up):

```
P0 parity-of-count            P3 inversion-parity           P6 AND-composition (sparse)
 inner \ outer  thr  spec poly  inner \ outer  thr  spec poly  inner \ outer  thr  spec poly
 count          .474 1.00*.502  count          .504 .500 .498  count          .884 1.00*.884
 sum            .501 .532 .504  sum            .504 .505 .504  sum            .883 .890 .888
 max            .517 .513 .517  max            .504 .505 .502  max            .888 .893 .893
 inversion      .496 .504 .501  inversion      .504 1.00*.504  inversion      .888 .888 .888
 oriented(0,1)  .502 .495 .502  oriented(0,1)  .504 .504 .506  oriented(0,1)  .888 .888 .888
 product(0,1)   .502 .506 .502  product(0,1)   .504 .505 .515  product(0,1)   .888 .888 .888
```

**Verdict:** 7/7 structure correctly discovered; 4/7 are genuine out-of-linear-closure **escapes**
(parity, max, inversion-parity, AND — `linear-raw` at or near chance, only the structured route works);
1/1 out-of-menu **ceiling**.

## What it shows

1. **The pieces compose into one blind discoverer.** A single argmax loop, with no per-predicate hint,
   routes periodic (→ spectral), threshold, order-statistic, and oriented/relational predicates to their
   true (inner, outer) — including the sparse AND-composition that needs the *fixed* accuracy-grid
   spectral, not the power-peak. The scattered frontiers are now one selector. The held-out 3-way split
   makes "discovery" a generalisation claim, not selection-on-test.

2. **The menu is itself a closure — measured, one level up.** On the hidden-pair predicate every menu
   pick sits at chance (best 0.591), while `poly2-raw` cracks it at 1.000. The failure is **not** that
   the predicate is hard: it is degree-2 separable. It is that the menu's relational inner is pinned to
   the focal pair (0,1), and the predicate lives on (2,5). The escaping generator is concrete and named:
   the `c2·c5` cross-term — *the product of the right pair*. The menu **has** product-of-a-pair; it just
   can't choose which pair. So "discover the generator" has moved up exactly one level: from discovering
   the operator to discovering **which cells** — i.e. growing the menu. This is the same wcore Claim-C
   conclusion (`CLOSURE_PRINCIPLE.md`) instantiated for the discoverer's own menu: closure all the way up.

## Honest caveats

- **Assembly + a meta-ceiling, not a new mechanism.** Every operator here already existed; the
  contribution is the blind selector over them and the clean demonstration of where the menu's own
  closure bites. No new escape primitive was invented.
- **"Linearly solvable" ≠ linear structure.** P5's `product>12` happens to coincide with `sum≥8` on the
  0..5 integer grid, so `linear-raw` reaches 1.000 by a grid coincidence — yet the discoverer still names
  the faithful generator (`product`), not the coincidence. The escape/no-escape split is about whether a
  *linear raw readout* suffices, not about the predicate's true algebra.
- **Accuracy is not a sufficient structure certificate in general.** Here the Occam tie-break sufficed
  (no misroutes), but a sufficiently flexible outer can clear validation on a wrong inner. A stronger
  discoverer would certify the pick (irreducibility / minimum-description-length), not just rank accuracy.
  No misroute occurred at this menu size; that is a property of this zoo, not a theorem.
- Single seed, single grid distribution, NCELL=8. The numbers are clean (0.5/1.0 separations) so seed
  noise is not load-bearing, but the phase behaviour under scale/noise is untested here.

## What this opens — the on-ramp to #3 (an inventable-primitive substrate)

The ceiling names its own escape: a discoverer that can **grow its menu** rather than select from a
fixed one. Concretely, the next rung is *inner-transform discovery*: search over **which** cells/pair a
relational inner addresses (and, more generally, propose new inner transforms), then certify the new
entry escapes — pair-selection is the minimal case (focal (0,1) → discovered (2,5)). That is #3 stated
operationally: make the menu itself growable, with each promoted primitive certified irreducible to the
current menu (the wcore atom-forge loop, lifted from opcodes to inner transforms). The present frontier
is the fixed-menu baseline that #3 must beat on exactly the hidden-pair predicate it currently fails.

See: `operator_inference.md`, `composed_discovery.md`, `antisymmetric_relational.md`,
`spectral_discovery.md`, `period_candidate_search.md`, repo-root `CLOSURE_PRINCIPLE.md`,
and `wcore/docs/research/alien_novelty_limit.md` (the atom-forge conclusion this re-instantiates).
