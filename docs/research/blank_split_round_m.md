# M2 — trace-only blank-region splitting

**Verdict: LIMITED POSITIVE (controlled).** A preregistered rule splits the
previously detected blank bucket into two stable trace-defined subregions on a
heldout synthetic split. It is a map-refinement primitive, not a discovered
scientific ontology, a family invention result, or an allocation win.

Harness: `sparse_poly_discovery/blank_split_round_m.zig`.
Ledger: `results/blank_split_round_m.csv`.

## Question and frozen method

L2 could say that the old grammar had no exact route. L4 showed that two such
blanks need not share one missing mechanism. Can a policy split the blank
bucket using *only* aggregate, current-menu trace observations?

The policy input is exactly `PublicTrace`:

```text
global maximum, singleton maximum, directed maximum, adjacency maximum
```

It contains no target token, target ID, formula, family label, mask, residue,
split, audit label, test label, or candidate-level score. The rule was fixed
before output:

```text
if global_max >= 0.75: near_global_blank
else:                  diffuse_blank
```

Both controlled groups are confirmed blank to the prior grammar (`global_max`
is below the old exactness threshold 0.95). The evaluator keeps the generating
subregion only to score predictions after the policy has run.

## Result

On the frozen 12-cell heldout split:

| Method | Correct subregion predictions |
|---|---:|
| Frozen trace splitter | **12/12** |
| Frozen unsplit one-bucket baseline | 6/12 |

The improvement is +6 heldout decisions. This does *not* rely on a token
sequence: each split has balanced hidden subregions and target IDs are neither
stored in `PublicTrace` nor read by `predict`.

## Controls and attacks

- **Token-renaming / target-ID leakage:** predictions are a pure function of
  `PublicTrace`; tokens are output-only. Reversing or renaming tokens cannot
  affect them.
- **Candidate-order attack:** canonical/reversed/affine candidate presentation
  reduces to the same four maxima; replayed aggregate copies predict
  identically.
- **Mask and residue attacks:** the trace exposes no mask or residue identity,
  only bank maxima. Their enumeration order has no policy path.
- **Permutation attack:** public diagnostics are aggregate bank scores, not
  coordinate names; coordinate/permutation metadata is absent from
  `PublicTrace`.
- **Duplicate attack:** the harness rejects byte-identical public traces, so
  repeated rows cannot inflate heldout accuracy.

## Limitation

This is a controlled synthetic separation: its hidden mechanisms were
constructed to create a near-global residual versus diffuse residual. The
result establishes that an observable search trace can refine a blank bucket
without labels; it does not show the split will survive a fresh family outside
this construction. Round M's sealed fresh-test and transfer experiments must
test that claim before treating this as a reusable map region.

## Reproduce

```bash
rm -rf /tmp/zig-m2-cache /tmp/zig-m2-global /tmp/blank_split_round_m
zig build-exe sparse_poly_discovery/blank_split_round_m.zig -O ReleaseFast \
  --cache-dir /tmp/zig-m2-cache --global-cache-dir /tmp/zig-m2-global \
  -femit-bin=/tmp/blank_split_round_m
/tmp/blank_split_round_m results/blank_split_round_m.csv
/tmp/blank_split_round_m selftest > /tmp/blank_split_round_m.selftest.csv
cmp results/blank_split_round_m.csv /tmp/blank_split_round_m.selftest.csv
```
