# K1 — fixed-policy forensic replay

**Verdict: positive forensic result, not an adaptive-policy result.** J4's
predeclared fixed allocation reaches 12/12 because it buys complete coverage
of the three small banks and enough of the directed prefix to include the
held-out directed witness.  It is a compact four-bank coverage schedule, not
evidence that a general router inferred a target's structure.

Harness: `sparse_poly_discovery/fixed_policy_forensic_round_k.zig`. Raw ledger:
`results/fixed_policy_forensic_round_k.csv`.

## Exact replay and attribution

This is the J4 fixed arm in the identical order and seeds:

```text
global:     30 candidates, calls 1..30
singleton:  48 candidates, calls 31..78
none:        5 candidates, calls 79..83
directed:  301 candidates, calls 84..384
```

The raw ledger writes one attribution row for every bank that has an exact
member, plus every predeclared policy ablation for each of the 12
seed-target cells. Exact first-witness positions are invariant across the
three frozen seeds:

| held-out target | winning bank | candidate index (zero-based) | first fixed call | calls needed in that bank |
|---|---:|---:|---:|---:|
| global (`id=4`) | global | 4 | 5 | 5 |
| singleton (`id=9`) | singleton | 3 | 34 | 4 |
| directed (`id=14`) | directed | 120 | 204 | 121 |
| adjacency (`id=19`, formerly `none`) | none | 0 | 79 | 1 |

The intended singleton bank witness appears at call 34, but there is also an
earlier directed-bank exact witness for that target: directed index 35 (call
119 in J4's fixed order). The direct replay therefore exposes a real
redundancy in the human schedule: singleton coverage is not necessary on this
frozen battery once the directed prefix is present.

The smallest post-hoc bank-prefix cover of the frozen four-target suite is
`global=5, singleton=0, adjacency=1, directed=121`, or **127 calls**. It is
derived from this replay and is *not* a fair new adaptive-policy baseline;
K1 must not turn it into one. J4's 384 selection calls have 257 calls beyond
that finite-battery minimum.

## Predeclared ablations

| allocation | selection calls | solves |
|---|---:|---:|
| full J4 fixed: 30 / 48 / 5 / 301 | 384 | 12/12 |
| remove global | 354 | 9/12 |
| remove singleton | 336 | 12/12 |
| remove adjacency | 379 | 9/12 |
| remove directed / small banks only | 83 | 9/12 |
| directed prefix 100 | 183 | 9/12 |
| directed prefix 200 | 283 | 12/12 |
| post-hoc minimal prefix: 5 / 0 / 1 / 121 | 127 | 12/12 |

Global, adjacency, and directed coverage are necessary for their corresponding
frozen target cells. Singleton coverage is redundant because the directed
prefix happens to reconstruct the singleton cell at directed index 35. The
directed arm's first intended directed witness is index 120, so a 100-key
prefix misses and a 200-key prefix succeeds. The fixed baseline's advantage
in J4 is therefore broad human-designed coverage and a finite directed prefix,
not a trajectory advantage.

## Integrity and limits

The harness asserts the directed candidate universe is exactly 1,270 unique
`(mask, modulus, residue)` keys before any run. It writes `enum_unique=1270`
and `perm_assert=pass` on each row, uses J4's three fixed seeds, and has a
byte-identical `selftest` mode.

The replay remains deliberately narrow. The target identities and routes in
the CSV are audit fields only, but the fixed policy itself is a human-designed
coverage schedule over these four bank classes. The three seeds vary examples,
not target forms. Consequently K1 explains the 12/12 baseline; it does not
show that the schedule will remain minimal or superior on K4's hidden-
structure holdouts.

## Reproduce

```bash
zig build-exe sparse_poly_discovery/fixed_policy_forensic_round_k.zig -O ReleaseFast -femit-bin=fixed_policy_forensic_round_k
./fixed_policy_forensic_round_k results/fixed_policy_forensic_round_k.csv
./fixed_policy_forensic_round_k selftest > /tmp/fixed_policy_forensic_round_k.selftest.csv
cmp results/fixed_policy_forensic_round_k.csv /tmp/fixed_policy_forensic_round_k.selftest.csv
```

The command was run in a temporary-cache build and compared byte-for-byte with
the harness `selftest` output.
