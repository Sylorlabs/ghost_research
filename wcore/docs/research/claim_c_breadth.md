# Claim C at breadth — the irreducibility instrument across 16 seeds

**Status:** built, measured. Reproduce: `bash scripts/claim_c_breadth.sh` (from
the repo root; ~6 min, 16 seeds × ~22 s). Raw data: `results/claim_c_breadth.csv`.

## What this tests

Claim C (the wcore arc, §25, `alien_novelty_limit.md`): execution-only search over
a **fixed** primitive set produces novel *compositions*, never a new *atom*. The
irreducibility instrument (`wcore-invent irreducible <seed>`) builds a §24-style
ladder of deep solvers, asks the fingerprint certifier which are "novel", and then
asks the irreducibility test which are actually **irreducible** to a known-atom
composition (vs reducible compositions the certifier false-flags). A single seed
showed 7 novel / 0 irreducible. This sweep turns that into a breadth claim.

## Results (16 seeds)

```
  seeds | certifier "novel" | irreducible | kill-test non-vacuous
  ------+-------------------+-------------+----------------------
   16   |        86         |      1      |        16/16
```

- **85 of 86** certifier-"novel" deep solvers are **reducible** to a known-atom
  composition. Claim C holds at breadth (98.8%): open-ended search keeps producing
  novel *arrangements*, essentially never a new atom.
- **The instrument is non-vacuous:** in all 16 seeds the kill-test correctly flags
  `distinct-count` (a hand-built true outsider) as irreducible. So "0–1 irreducible"
  is a real measurement, not an instrument that always says "reducible".
- **The lone exception (seed 0xD00D, 1 irreducible) is almost certainly a
  budget-limited false negative,** not a new atom. The reducibility test searches
  for a reducing composition only to **depth 4**; a solver needing a depth-5
  reduction is reported "irreducible" without being a genuine outsider. Confirming
  vs refuting it requires a deeper reduction search.

## The honest epistemics (and the tie to the closure principle)

"Irreducible" is **always relative to the reduction budget**: you can never prove a
behaviour is a new atom, only fail to reduce it within a given depth/closure. The
1/86 is exactly that limit showing through. This is the same structure as the
discovery ladder in `asi_attempt/docs/research/feature_discovery.md` and the
parity frontier: every claim of "a genuine new thing" presupposes the closure
you are reducing against — closure all the way up. The breadth result is therefore
a **negative result, done at scale**: across 86 discovered solvers and 16 seeds,
fixed-primitive search produced zero confirmed new atoms, and the one ambiguous
flag is a budget artifact, not a breakthrough. It strengthens Claim C; it does not
overturn it.
