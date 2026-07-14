# N1 — Decoupled sealed benchmark

**Verdict: PASS — benchmark foundation; not an invention result.**

Harness: `sparse_poly_discovery/decoupled_benchmark_round_n.zig`  
Public result: `results/decoupled_benchmark_round_n.csv`  
Per-action evaluator ledger: `results/decoupled_benchmark_round_n.ledger.csv`

## Question

Round M was deliberately aligned: public trace structure pointed toward one of
two public predicate tools. Round N needs a benchmark where a trace-only router
cannot identify the winning family. This harness owns the hidden target family
and parameters, emits opaque tokens, public aggregate diagnostics, and (for the
train split only) opaque labelled examples.

There are two independent public-language candidate families:

- `threshold_parity`: parity of two byte-wise threshold predicates;
- `mask_parity`: parity of two byte-wise masked-bit predicates.

The evaluator-private target assignment is balanced (four of each family in
train and two of each in heldout), non-alternating, and deterministic. The four
public diagnostic fields are generated from a seed independent of that
assignment. They carry neither a family name, parameter, candidate identity,
nor score against either family.

## Frozen trace-only leakage check

Before generation, the router and family-prior baseline were both frozen to
`threshold_parity`. On the four opaque heldout targets they both obtain **2/4**.
The router therefore has exactly baseline/chance performance; it is not given a
shortcut from the public trace to the winning family.

All 12 targets have unequal family scores on a hidden test sample (valid) and
their hidden labels contain both classes on that sample (nondegenerate). Token
renaming, presentation/permutation replay, duplicate public-trace invariance,
and private-field scan pass.

## Evaluator/accounting protocol

The harness writes an evaluator-owned state file and every allowed diagnostic
or candidate proposal is an individual ledger row. A persistent 24-call budget
is deliberately exhausted and an additional post-restart call is rejected.
Only the eight training tokens accept evaluator calls; an attempted heldout
query is rejected. The demonstration has 24 charged rows before rejection. Target
formulas, family labels, cutoffs, masks, seeds, and audit material are absent
from public train output and public result columns.

The single-binary version is a reproducible protocol test, **not** an OS
isolation claim: a production evaluator must live in a separately controlled
process/service with a private manifest.

## Interpretation

This is a usable benchmark foundation, not a positive about learning. It
removes Round M's direct trace-to-tool shortcut while retaining a controllable
opaque train/query/test setting. N2 must independently quantify the same
non-leakage claim; later N3/N4 must show that memory/proposal machinery—not the
trace—is responsible for any gain.

## Reproduce

```bash
rm -rf /tmp/zig-n1-cache /tmp/zig-n1-global /tmp/decoupled_benchmark_round_n
zig build-exe sparse_poly_discovery/decoupled_benchmark_round_n.zig -O ReleaseFast \
  --cache-dir /tmp/zig-n1-cache --global-cache-dir /tmp/zig-n1-global \
  -femit-bin=/tmp/decoupled_benchmark_round_n
/tmp/decoupled_benchmark_round_n results/decoupled_benchmark_round_n.csv
/tmp/decoupled_benchmark_round_n selftest
cmp results/decoupled_benchmark_round_n.csv /tmp/decoupled_benchmark_round_n.selftest.csv
```
