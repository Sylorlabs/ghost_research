# Research note: can the out-of-closure generator be DISCOVERED?

**Status:** built, measured. The frontier question from `CLOSURE_PRINCIPLE.md`,
answered at the selection level. Reproduce: `zig build eval` (`[BAND]`, the
"feature search" block; 6 seeds × 15,000 steps).

## The question

`closure_escape_control.md` showed the XOR/bundle substrate is provably blind to
the band predicate, and that *hand-supplying* the sum (`mb_mass`) escapes it,
beating the XOR-substrate readout (11.02 vs 33–163; note: it does NOT beat a tuned
thermostat, which scores 0.00 — see closure_escape_control.md E1 correction). But the sum was supplied by a
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
  sum            |  11.02   <- selected; beats the XOR agents (NOT a tuned thermostat = 0.00)
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
(`mb_mass`), beating the XOR readout (though not a tuned thermostat). Construction-level discovery — the frontier —
is achievable here.

## What this does and does not show

- **Does:** the out-of-closure generator is *discoverable* — by selection (level 1)
  and even by unsupervised construction from raw primitives (level 2, PCA). It is
  not inherently human-supplied.
- **Does not:** construction worked here because the useful feature (the sum)
  **coincides with the dynamics' dominant variance mode.** PCA finds the controllable
  direction; it succeeds when "useful" aligns with "high-variance/controllable",
  which the band dynamics arrange. A useful feature *uncorrelated* with the dominant
  mode would not be found this way.

## Level 3 — the non-circular test (this falsifies Level 2's generality)

`zig build probe` (the hidden-feature block) rigs the opposite of Level 2: the
safety feature is a single cell (`e_0`) while cells 8–15 are a loud correlated
decoy block independent of failure — so the useful feature is **not** salient.
Recovering the true direction `e_0` (cosine; chance ≈ 0.25):

```
  method                       | cosine to true feature
  -----------------------------+-----------------------
  PCA (unsupervised variance)  | 0.000   <- misled by the decoy
  supervised, one-sided        | 0.999   <- recovered
  supervised, two-sided band   | 0.139   <- failed (slab)
```

- **PCA recovers nothing (0.000).** This *falsifies the generality of Level 2*:
  the "PCA constructs the sum" result was circular — it only worked because the
  feature was the top variance axis. Off that special case, unsupervised variance
  is useless or actively misled.
- **Supervised credit-assignment recovers a one-sided non-salient feature (0.999)** —
  using the failure signal, not variance.
- **A two-sided band defeats linear supervision too (0.139):** failures sit on
  both sides of the band, so `mean(fail) ≈ mean(safe)` along `e_0`. The band
  predicate is itself out-of-linear-closure. Discovering a non-salient,
  non-monotone feature needs supervised direction-finding **composed with** a
  nonlinear readout — neither variance nor linear supervision alone suffices.

So the honest discovery ladder: **selection** (works if the generator is in the
library) → **unsupervised construction** (works only if the generator is the
dominant mode — circular) → **supervised construction** (works for non-salient
*monotone* features) → **supervised + nonlinear** (required for the actual band).
Each rung is the closure question one level up — the wcore atom-forge conclusion
(Claim C), confirmed from the discovery side.

## Level 4 — the last rung, demonstrated

`zig build probe` (Item 1 block) trains a tiny MLP (16 → 8 ReLU → 1) on the *same*
hidden two-sided band that beat PCA, selection, and linear supervision:

```
  classifier                    | test accuracy
  ------------------------------+--------------
  majority-class baseline       |   0.570
  linear logistic regression    |   0.523   (the slab — out of linear closure)
  tiny MLP (16->8 ReLU->1)      |   1.000
  MLP input-weight on true cell |   53.0%   (random would be 6.3%)
```

The MLP cracks it perfectly and concentrates its weight on the hidden cell —
supervised credit-assignment **composed with** a nonlinearity recovers and uses a
non-salient, non-monotone feature that none of the lower rungs could. The ladder
is complete.

**The honest bound.** This is a small net doing small-net things — the *textbook*
escape (a two-ReLU unit represents `|w·x − c|`), not a new mechanism. It confirms
the closure principle's prescription (add nonlinearity to escape a linear closure)
rather than discovering anything novel. The real frontier is unchanged: every rung
of "discover the generator" presupposes a discoverer whose own closure already
contains the generator — closure all the way up (Claim C).

## Connection

This closes the loop opened in `CLOSURE_PRINCIPLE.md`: the escape generator is not
inherently human-only. A search over candidate generators finds it, provided the
right generator is *expressible* in the candidate space. That just relocates the
question one level up — to whether the candidate space itself is rich enough —
which is the closure principle applied to the space of generators. It is closure
all the way up, exactly as the wcore arc concluded for atoms.
