# Pair-Search Substrate Growth (#38 follow-up + #30 op-power ranking)

**Status:** built, measured, **exact** (full 256-input truth table).
Reproduce: `zig build synergy` (the same binary as emergent_escape.md).

This is the experiment that `emergent_escape.md` predicted: modify the
atom-forge's growth rule to escalate to pair-search when single-op greedy
stalls, and verify it fixes the isolated emergent escape case.

---

## The predicted experiment: pair-grow on the isolated case

The emergent escape showed `x&(x-1)` is unreachable by `base+{AND}` and
`base+{SUB}` individually, but reachable by `base+{AND,SUB}`. Greedy
growth fails on the isolated `{x&(x-1)}` task (0/1) because AND and SUB
each have gain=0 alone, so greedy never picks either.

**Prediction**: a pair-search variant that escalates from single-op to
pair-search when greedy stalls should fix this.

**Result (confirmed)**:

```
  isolated {x&(x-1)}: pair-grow 1/1   greedy 0/1   full 1/1
```

Pair-search finds `{AND,SUB}` immediately when greedy stalls. On the rich
5-target set both reach 5/5 — pair-search doesn't hurt, it only helps.

### How `pairGrow()` works

1. Try all single ops (same as `greedyGrow`). If any makes progress, take the best.
2. If no single op makes progress, try all O(n²) op pairs.
3. If any pair makes progress, add both ops and continue.
4. If no pair makes progress, stop.

Cost: O(n) per step normally; O(n²) at stall points. In practice, the stall
is rare (greedy handles the rich case fine), so pair-search is a cheap fallback.

---

## #30: Op-power ranking (single-op reach at MAXL=3)

Which nonlinear op individually unlocks the most of the 5 nonlinear targets?

```
  op   | targets/5 | min-lengths
  -----+-----------+--------------------------------------------
  AND  | 1/5       | 2 - - - -     (reaches x&(x>>1) at length 2)
  OR   | 1/5       | - - - 2 -     (reaches x|(x<<1) at length 2)
  ADD  | 0/5       | - - - - -     (carry is nonlinear but not enough alone)
  SUB  | 0/5       | - - - - -     (same)
  MUL  | 1/5       | - - 1 - -     (reaches x*x at length 1 directly)
```

**Key findings:**

1. **No op is clearly more powerful than others at single-op reach** — AND, OR,
   MUL each reach 1/5. ADD and SUB reach 0/5 individually.

2. **MUL reaches x*x at program length 1** — the most direct, but still just 1/5.

3. **The 2 emergent targets need PAIRS**: `x&(x-1)` needs {AND,SUB}; `x|(x*x)`
   needs {OR,MUL}. No single op touches them. This is why the power ranking
   at single-op level looks flat — the structure is in the interactions.

4. **ADD and SUB = 0/5 alone but are crucial in pairs**. SUB is one half of the
   most irreducible emergent escape `{AND,SUB}→x&(x-1)`. Single-op power
   is not a reliable predictor of pair-search utility — the ops that look
   weakest alone can be half of an irreducible pair.

---

## Pair-power ranking

For each pair of nonlinear ops, how many of the 5 targets can `base+{i,j}` reach?

```
  pair       | targets/5
  -----------+----------
  AND+OR     | 2/5
  AND+ADD    | 1/5
  AND+SUB    | 2/5
  AND+MUL    | 2/5
  OR+ADD     | 1/5
  OR+SUB     | 1/5
  OR+MUL     | 3/5    <-- strongest pair
  ADD+SUB    | 0/5
  ADD+MUL    | 1/5
  SUB+MUL    | 1/5
```

**OR+MUL is the strongest pair (3/5)**: MUL reaches `x*x` alone; OR reaches `x|(x<<1)` alone;
together they reach `x|(x*x)`. The emergent pair (`x|(x*x)`) is one of three targets covered.

**ADD+SUB = 0/5**: both ops are individually 0/5, and as a pair still reach nothing. The
emergent escape `{AND,SUB}→x&(x-1)` requires AND too. This shows that not all pairs with
"weak" ops are emergent — the combination must also have the right structural fit.

## Triplet-emergence check

Does any target need 3 ops simultaneously (reachable by some triplet but not any pair)?

```
  No triplet-emergent targets in this set: all 5 targets covered by singles or pairs.
  Emergence saturates at depth 2 for these targets -- pair-search is SUFFICIENT.
```

Pairs are necessary (for the 2 emergent targets) and sufficient (no third level).

---

## Conclusion

Pair-search substrate growth:
- **Fixes the isolated emergent case** (confirmed, not assumed)
- **Is identical to greedy on the rich case** (no regression)
- **Costs O(n²) only at stall points** (acceptable)

The op-power ranking reveals that "single-op reach" is the wrong metric for
identifying important generators — SUB/ADD look powerless alone but enable
the two emergent pairs. The right question is joint reach, not marginal reach.

Design implication for any atom-forge or feature-selection procedure:
**use pair-search (or tuple-search) when greedy stalls**, because stalling
is exactly the signal that the needed generator is an irreducible pair.

See: `emergent_escape.md` for the underlying finding; `CLOSURE_PRINCIPLE.md`
for where this fits in the broader arc.
