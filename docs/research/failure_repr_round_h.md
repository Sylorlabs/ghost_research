# H1 — failure-representation audit (Round H)

> **Belongs to Round H, experiment H1.** Harness:
> `sparse_poly_discovery/failure_repr_round_h.zig`. Raw results:
> `results/failure_repr_round_h.csv`. Frozen input protocol: G2's 20-target
> corpus and exact 12/4/4 split.

## Verdict

**VALID NEGATIVE: the audited richer response representations do not improve
held-out prior routing.** The four contracts were fixed generic probe banks;
the model was train-standardized 1-NN as in G3.  Contract choice used only the
four validation rows: `full16` won validation at **4/4** (versus cheap6 2/4,
residual10 3/4, orientation10 2/4).  Its untouched held-out result is only
**1/4**, equal to G3's fixed `thresh` baseline (and above neither routing
standard).

This is evidence against the particular "more generic response correlations +
1-NN" lever, not evidence that a richer failure representation or grammar
proposer is impossible.  It provides **no accepted descriptor contract for
H2**: launching a learned-router rematch from it would be a post-hoc repeat of
the same known non-improvement.

## Protocol

- The harness regenerates G2's exact target semantics, target IDs, split seeds,
  4,096 examples per target, and frozen **12 train / 4 validation / 4
  held-out** partition. IDs/names/prior labels are audit/evaluator data only.
- Selector input is solely a target label's agreement with a fixed generic
  bank of probes: count, sum, inversion, run, local, residual-modulo,
  orientation, adjacency, and generic product/additive probes. There is no
  target name, formula text, source block, family field, designated-prior
  field, or target-dependent probe parameter in the descriptor path.
- All distances use standard deviations fitted from train rows only. The
  descriptor contract was selected on validation alone; test rows were printed
  once after the selection was frozen.
- The independent train-to-nontrain nearest-distance guard passes for selected
  `full16`: **1.448328 > 0.05**. Frozen training cardinality is 12.

## Abladtion results

| Contract | Fixed probe dimensions | Validation routing | Selection status |
|---|---:|---:|---|
| `cheap6` | 6 | 2/4 | G3-like baseline |
| `residual10` | 10 | 3/4 | rejected on validation |
| `orientation10` | 10 | 2/4 | rejected on validation |
| `full16` | 16 | 4/4 | selected before held-out read |

The selected contract's held-out target rows are:

| Target (audit-only) | Truth (audit-only) | Selected prior | Exact routing |
|---|---|---|---:|
| TE5 | thresh | ratio | 0 |
| ME5 | mixr | mixr | 1 |
| RE5 | ratio | run | 0 |
| RN5 | run | mixr | 0 |

The result is **1/4 held-out**, the same as G3's fixed routing control. The
validation-perfect/full16 outcome therefore must not be promoted as a learned
routing advance.

## Recommendation

Do not run H2 on this representation. The next valid selector/proposer should
use an observation that measures *search response* (for example, how grammar
families reduce an actual residual under equal budget), rather than adding more
static label--probe agreement statistics. H3's direct grammar-proposer route
remains independently meaningful; any future H2 needs a new pre-registered
descriptor contract and must retain this split, train-only normalization, and
test-isolation protocol.

## Reproduce

```sh
cd sparse_poly_discovery
zig build-exe failure_repr_round_h.zig -O ReleaseFast -femit-bin=failure_repr_round_h
./failure_repr_round_h ../results/failure_repr_round_h.csv
./failure_repr_round_h selftest
```
