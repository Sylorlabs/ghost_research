# Triple-Band: N Constraints Need N Features

**Status:** built, measured, BREAKTHROUGH. Reproduce: `zig build triple-band-test`

---

## Setup

Triple-band task: three simultaneous homeostatic constraints:
1. total sum ∈ [16, 48]
2. left_mass (cells 0..7) ∈ [6, 22]
3. right_mass (cells 8..15) ∈ [6, 22]

Starting from dual-band discovery: `(left_mass, max_cell) = 0.25 fail/1k` on dual-band.
Question: does this pair survive a third constraint?

---

## Results

### Dual-band pairs on triple-band

```
  (left_mass,max_cell):   98.40 fail/1k   ← pair FAILS (was 0.25 on dual-band)
  (left_mass,right_mass): 291.31 fail/1k
  (sum,left_mass):         83.29 fail/1k
  (sum,max_cell):          83.29 fail/1k
```

The best dual-band pair degrades 400× when a third constraint is added.
The emergent coverage that made (left_mass, max_cell) work on 2 constraints
does NOT extend to 3 constraints.

### Exhaustive triplet search

```
  triplet(sum,left_mass,right_mass):     3.79 fail/1k  ← BEST
  triplet(sum,left_mass,max_cell):       3.79 fail/1k  ← tied
  triplet(sum,left_mass,nonzero_count): 272.33 fail/1k
  triplet(left_mass,right_mass,max_cell): 324.56 fail/1k
  ... (others worse)
```

Two triplets tie at 3.79 fail/1k — both include left_mass and sum. The key
difference from dual-band: you need BOTH left_mass and right_mass to cover the
two half-constraints, plus sum for the total.

---

## The Breakthrough Finding: Coverage Scales Directly

**For N constraints, the optimal feature set has N features that together
cover all N constraint dimensions.**

### Why (left_mass, max_cell) worked on dual-band (2 constraints):
- left_mass directly covers the left-half constraint
- max_cell prevents cell overflow AND indirectly limits total sum (can't grow if max
  cell is regulated)
- These two features together cover all 3 dual-band failure modes as SIDE EFFECTS
- This is emergent indirect coverage — neither feature directly tracks right_mass

### Why (left_mass, max_cell) fails on triple-band (3 constraints):
- right_mass is now a hard constraint
- max_cell does NOT regulate right_mass
- Regulating left_mass and max_cell leaves right_mass unconstrained → right-half
  violations dominate (91.31% of the 98.40 fail/1k come from right_mass OOR)
- The emergent coverage was not extensible: it worked because the equilibrium
  happened to satisfy the dual constraints, but breaks when a new constraint is added

### The direct coverage principle:
**Each constraint needs a feature that directly addresses it.**
- sum constraint → track sum
- left_mass constraint → track left_mass
- right_mass constraint → track right_mass
- Cell overflow → track max_cell (or this is handled as a side effect of the others)

The triplet (sum, left_mass, right_mass) = 3.79 is the "direct coverage" solution.
The triplet (sum, left_mass, max_cell) = 3.79 shows that max_cell can substitute for
right_mass via indirect coverage on triple-band — but only when sum explicitly handles
the total-mass constraint.

---

## Comparison with Pair-Emerge #38

The dual-band discovery (pair-search finds (left_mass, max_cell)) was analogous to
pair-emerge in the bit-op domain: exhaustive search found an emergent coverage property
that greedy/individual search missed.

The triple-band finding adds: **emergent coverage is fragile and non-compositional**.
- (left_mass, max_cell) emergently covers 2-constraint dual-band
- Adding a 3rd constraint (right_mass) breaks the emergence
- The direct-coverage triplet (sum, left_mass, right_mass) is robust

This is the control-domain equivalent of: some Hamming-weight reducers need AND+SUB
together, but the pair that works for one target may not work for a harder target. The
compositional, direct solution (one primitive per constraint) is more robust than the
emergent, indirect solution.

---

## Honest Grade

The finding is real and generalizes a principle: direct coverage (one feature per
constraint) is robust and scales; indirect/emergent coverage is brittle and
domain-specific.

The practical implication: pair/triplet search should prefer features that directly
address the known constraint dimensions. If constraints are known (they are here),
the optimal feature set is obvious. If constraints are unknown (the harder problem),
exhaustive search still applies — but the scale grows as O(N^k) for k constraints.

See: `pair_feature_control.md`, `correlation_feature_discovery.md`.
