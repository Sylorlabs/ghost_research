# Research note: can the out-of-closure generator be DISCOVERED?

**Status:** built, measured. The frontier question from `CLOSURE_PRINCIPLE.md`,
answered at the selection level. Reproduce: `zig build eval` (`[BAND]`, the
"feature search" block; 6 seeds × 15,000 steps).

## The question

`closure_escape_control.md` showed the XOR/bundle substrate is provably blind to
the band predicate, and that *hand-supplying* the sum (`mb_mass`) escapes it,
beating the hand-coded thermostat (11.02 vs 20.80). But the sum was supplied by a
human. The deeper question — the real meaning of "invention" — is whether a system
can **discover** the right out-of-closure feature on its own.

## Experiment

`mb_mass` is generalised to regulate any candidate aggregate feature
(`agent.FeatureKind`): `sum`, `max_cell`, `first_cell`, `nonzero_count`. A generic
search runs the same controller with each candidate and keeps whichever achieves
the lowest failure rate — it is **not told** that total mass is the relevant
quantity.

## Results

```
  feature        | fail/1k
  ---------------+--------
  sum            |  11.02   <- selected; beats the hand-coded thermostat (20.80)
  max_cell       |  37.53
  first_cell     | 208.31
  nonzero_count  | 333.31   (= the always-rest floor: useless)
  => search SELECTS 'sum'
```

The separation is decisive: only the sum yields real control; the decoys range
from mediocre (`max_cell`, which correlates with over-charge but is blind to
under-charge) to useless (`nonzero_count` = the trivial floor). A generic
keep-the-best search therefore **discovers the sum autonomously** — selection-level
invention of the out-of-closure generator, no human pointing at "total mass".

## What this does and does not show

- **Does:** the out-of-closure generator is *discoverable*, not necessarily
  human-supplied. Given a library of candidate features and a generic control
  objective, the system finds the one that escapes the substrate's closure.
- **Does not:** this is **selection** from a candidate library, not **construction**
  from primitives. The sum was one of four offered features. True invention —
  synthesising the sum from raw cells with no candidate list — is the harder open
  problem, and is exactly what wcore's atom-forge attempts (and where it bottoms
  out at its fixed VM, Claim C). The honest placement: discovery-by-selection is
  solved here; discovery-by-construction remains the frontier.

## Connection

This closes the loop opened in `CLOSURE_PRINCIPLE.md`: the escape generator is not
inherently human-only. A search over candidate generators finds it, provided the
right generator is *expressible* in the candidate space. That just relocates the
question one level up — to whether the candidate space itself is rich enough —
which is the closure principle applied to the space of generators. It is closure
all the way up, exactly as the wcore arc concluded for atoms.
