# J4 — corrected trajectory allocator

**Verdict: terminal negative.** Under the frozen J2 response accounting and a
strict equal-total-cost comparison, the trajectory-guided allocator does not
beat the target-blind fixed allocation. It therefore supplies no evidence that
the human structural-prior choice has been removed.

Harness: `sparse_poly_discovery/trajectory_allocator_round_j.zig`. Raw ledger:
`results/trajectory_allocator_round_j.csv`.

## Protocol

- Every arm is charged **216** frozen J2 response calls plus **384** selection
  calls: **600 candidate calls per target**. Response costs are charged even to
  baselines that do not use the route prediction.
- The response-guided arm receives only J2-style labelled trajectory scores
  (bank best accuracies); it never reads target identity, formula, family,
  anchor, mask, residue, or audit label. It spends its 384 calls inside the
  predicted grammar.
- Fixed is a predeclared, target-blind coverage allocation: all 30 global, 48
  singleton, and five no-grammar candidates plus a 301-member directed prefix.
  IID random samples 384 directed keys; blind coverage is the first 384 unique
  directed keys. J1's 1,270-key unique enumeration and permutation status are
  recorded on every row.
- The ledger spans singleton, two-cell, held-out three-/four-cell partitions,
  global, and no-grammar controls across three frozen seeds. It records raw
  target/route fields only as audit columns, never as inference input.

## Result

The response route is useful as a descriptive signal, but its allocation arm
solves **10/12** frozen-heldout seed-target cells versus fixed coverage's
**12/12** at the same 600-call total (IID random **0/12**; blind directed
coverage **6/12**). The frozen 12/4/4 corpus is retained; train/validation
targets are not scored in this held-out outcome.
It therefore does not strictly improve on fixed coverage and fails J4's
pre-registered bar (strict held-out improvement over fixed, IID random, and
target-blind coverage). The result is a **valid negative**, not a harness
failure: all arms have identical charged budgets, the directed enumeration is
1,270 unique keys, and inference does not ingest audit metadata.

The consequence is operational: J5 may audit this negative and J6 must remain
blocked. A later allocator must beat fixed coverage under the same response
charge, not merely classify the frozen route examples.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/trajectory_allocator_round_j.zig -O ReleaseFast -femit-bin=trajectory_allocator_round_j
./trajectory_allocator_round_j results/trajectory_allocator_round_j.csv
./trajectory_allocator_round_j selftest > /tmp/trajectory_allocator_round_j.selftest.csv
cmp results/trajectory_allocator_round_j.csv /tmp/trajectory_allocator_round_j.selftest.csv
```
