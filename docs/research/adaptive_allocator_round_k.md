# K3 — adaptive elimination allocator on K4 hidden holdout

**Verdict: valid negative.** The pre-registered adaptive policy did not beat
the strong target-blind controls on K4's 24 post-freeze targets. At the same
charged **600 candidate calls** (including all exploration), adaptive solved
**10/24**; the predeclared K1-inspired fixed schedule solved **10/24**;
target-blind directed coverage also solved **10/24**; IID random solved 9/24.
The strict Round K success criterion was `adaptive > fixed AND random AND
blind`; it is not met.

Harness: `sparse_poly_discovery/adaptive_allocator_round_k.zig`.
Raw per-target ledger: `results/adaptive_allocator_round_k.csv`.

## Frozen protocol and information boundary

The policy was frozen as a four-bank two-stage policy before reading K4 policy
outcomes:

1. Evaluate the K2-style complete set probes: global 25, singleton 40,
   directed 180, adjacency 5 (**254 calls**).  The policy sees only candidate
   accuracies on the opaque labelled examples.
2. Compute each bank's maximum training score (a permutation-invariant set
   statistic); select the bank with the largest maximum, canonical enum order
   breaking ties; spend the remaining **346 calls** in that bank.

Target kind, mask, partition size, residue, permutation, formula, and target
id are evaluator-private. They are written to the ledger only as post-run
audit fields. All arms run the same 254 exploratory calls and have the same
label access. A probe finding an exact candidate counts as a discovery for
every arm, preventing uncharged exploration.

The primary fixed schedule ignores probe scores and spends its 346 selection
calls in the predeclared K1-style coverage proportions: 25 global, 40
singleton, 5 adjacency, 276 directed. The post-hoc 127-call K1 witness is
explicitly not used as a primary comparison. IID random draws among the same
four banks; blind coverage sends all 346 selection calls to directed. Every
arm therefore has exactly `254 + 346 = 600` charged candidate calls.

## Results

| arm | exploration | selection | total calls | exact solves |
|---|---:|---:|---:|---:|
| adaptive elimination | 254 | 346 | 600 | **10/24** |
| fixed K1-inspired coverage | 254 | 346 | 600 | **10/24** |
| IID random | 254 | 346 | 600 | 9/24 |
| target-blind directed coverage | 254 | 346 | 600 | **10/24** |

The raw ledger contains each target token, target's after-the-fact audit kind,
policy bank choice, charged calls, solve outcome, and integrity gates. The
adaptive policy gets all five K4 thresholds and five directed targets, but
none of the adjacency, XOR, or parity controls. Its bank choices are not a
general grammar classifier: for example, it labels two directed targets as
singleton and several controls as global. This result therefore does not show
that adaptive allocation learned a useful target-specific allocation beyond
the broad coverage already supplied by humans.

## Integrity and reproducibility

Before evaluation the harness asserts the full directed grammar has exactly
1,270 unique `(mask, modulus, residue)` keys. K4's deterministic generator
applies a fresh eight-cell permutation per target; evaluator labels are made
only after that permutation. The policy cannot inspect K4 `audit_*` fields.
The checked result is byte-identical to `selftest`.

```bash
zig build-exe sparse_poly_discovery/adaptive_allocator_round_k.zig -O ReleaseFast \
  -femit-bin=/tmp/adaptive_allocator_round_k \
  --cache-dir /tmp/k3-cache --global-cache-dir /tmp/k3-global
/tmp/adaptive_allocator_round_k results/adaptive_allocator_round_k.csv
/tmp/adaptive_allocator_round_k selftest > /tmp/adaptive_allocator_round_k.selftest.csv
cmp results/adaptive_allocator_round_k.csv /tmp/adaptive_allocator_round_k.selftest.csv
```

## Limits

This is a valid negative for this **max-score adaptive elimination policy**,
not a proof that no adaptive policy can work. The bank vocabulary, candidate
primitives, labelled examples, 254-call probe budget, and canonical tie order
remain human-supplied. K4 contains no standalone singleton target, and its
XOR/parity controls are deliberately outside the four-bank candidate menu;
the experiment tests allocation over the stated menu, not open-ended grammar
invention. A future positive must beat this fixed and blind tie on a newly
committed holdout without encoding the useful allocation in its probe bank.
