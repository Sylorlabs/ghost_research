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

## Level 2 — construction from raw cells (no library, no labels)

Selection from a list is the weak form. The strong form is **construction**: build
the feature from primitives with no candidate offered. `zig build probe` (the
construction block) does this with unsupervised PCA: collect grids under a random
policy on the band, form the 16×16 raw-cell covariance, power-iterate its top
principal component, and compare to the uniform (sum) direction.

```
cosine(top principal component, uniform/sum direction) = 0.9987   (6 seeds × 8000 steps)
```

The top PC is the sum direction, near-exactly — with **no labels and no candidate
list.** The reason is mechanistic: `charge` and `rest` move *all* cells together,
so the dominant variance axis of the raw cells *is* the sum. The out-of-closure
feature is therefore **constructed** unsupervised, and control via it scores 11.02
(`mb_mass`), beating the thermostat. Construction-level discovery — the frontier —
is achievable here.

## What this does and does not show

- **Does:** the out-of-closure generator is *discoverable* — by selection (level 1)
  and even by unsupervised construction from raw primitives (level 2, PCA). It is
  not inherently human-supplied.
- **Does not:** construction worked here because the useful feature (the sum)
  **coincides with the dynamics' dominant variance mode.** PCA finds the controllable
  direction; it succeeds when "useful" aligns with "high-variance/controllable",
  which the band dynamics arrange. A useful feature *uncorrelated* with the dominant
  mode would not be found this way. So the standing frontier sharpens: not "can we
  construct any feature" but "can we construct a useful feature that is **not**
  already salient in the dynamics" — which is again the closure question one level
  up (is the constructor's bias rich enough?), the wcore atom-forge conclusion
  (Claim C).

## Connection

This closes the loop opened in `CLOSURE_PRINCIPLE.md`: the escape generator is not
inherently human-only. A search over candidate generators finds it, provided the
right generator is *expressible* in the candidate space. That just relocates the
question one level up — to whether the candidate space itself is rich enough —
which is the closure principle applied to the space of generators. It is closure
all the way up, exactly as the wcore arc concluded for atoms.
