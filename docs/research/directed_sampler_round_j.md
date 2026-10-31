# J1 — directed grammar enumeration and target-agnostic sampler repair

**Verdict: positive substrate repair; no routing or efficiency claim.** The
directed grammar is now enumerated as exactly **1,270 unique candidates**:
254 non-empty/non-full masks times the five legal residue choices
(`mod 2: 0,1`; `mod 3: 0,1,2`). The previous response-atlas concern is
addressed at the source: all sampler prefixes are generated without
replacement and carry an explicit duplicate-key integrity check. This result
does **not** demonstrate target routing, candidate scoring, or search
efficiency.

## Question

Can later Round J experiments rely on a duplicate-free, permutation-invariant
directed candidate substrate and target-agnostic low-budget prefix samplers?

## Scope and frozen protocol

- Source: `sparse_poly_discovery/directed_sampler_round_j.zig`.
- Candidate representation is `(mask, modulus, residue)`.  Masks range from
  `1..254`; legal residue flavors are exactly `(2,0)`, `(2,1)`, `(3,0)`,
  `(3,1)`, `(3,2)`.
- The program asserts, before writing data, full-set cardinality, legal keys,
  no duplicate canonical key, no missing key, invariance under a fixed
  permutation of the eight mask bits, and invariance under a fixed permutation
  of the five residue flavors.
- It produces three target-blind *without-replacement* streams for each of
  three fixed seeds: Fisher-Yates uniform; a five-flavor stratified stream
  interleaving independently shuffled mask strata; and a fixed affine
  permutation control. The latter is only an ordering control.
- Raw prefix ledgers are written at budgets 25, 100, 300, 635, and 1,270.
  Each ledger records candidate calls, unique keys, unique masks, mod/residue
  counts, mean pairwise mask Hamming distance, and an integrity status.
- There are intentionally no target labels, validation scores, or candidate
  rankings in this artifact. Consequently there cannot be duplicate candidate
  *scores* caused by an indexing alias: each candidate key is visited at most
  once per stream and is the only valid future score-ledger key.

## Reproduction

From `sparse_poly_discovery/`:

```bash
zig build-exe directed_sampler_round_j.zig -femit-bin=directed_sampler_round_j
./directed_sampler_round_j
```

Expected terminal assertion:

```text
J1 PASS: 1270 unique candidates = 254 masks * (2 mod2 residues + 3 mod3 residues); all samplers duplicate-free.
```

The raw result is `results/directed_sampler_round_j.csv` (45 rows plus header:
3 samplers × 3 seeds × 5 prefixes).

## Results

Every row has `integrity=pass`; no prefix contains a duplicate candidate key.
At full coverage, every sampler has exactly 1,270 candidate calls, 1,270
unique candidate keys, 254 masks, 508 mod-2 candidates, and 762 mod-3
candidates. Each of the five legal residue flavors occurs exactly 254 times.

At low budgets, stratification supplies the expected flavor balance. For
example, at prefix 25 it has 5 candidates in each flavor, whereas uniform
prefixes differ by seed (for seed `0xA100...001`: mod-2 13 / mod-3 12; for
seed `...002`: 10 / 15). This is a diversity/coverage property, not evidence
that either order is better for a target. Both uniform and stratified streams
have exactly the same candidate-evaluation cost at a given prefix.

The affine control also has balanced flavor counts, but is deliberately held
as an ordering/permutation control rather than presented as an intelligent
sampler. Mean pairwise mask Hamming distance converges near 4.00 for all
three samplers by full coverage; raw seed-by-prefix values are retained rather
than averaged away.

## Limitations and what follows

- Uniform means a Fisher-Yates permutation of the finite candidate list; it
  is not iid sampling with replacement.
- Stratified means balance across the five predeclared legal residue flavors.
  It does not balance unobserved target properties and does not choose an
  order from failure evidence.
- The mask/remainder spaces are human-defined. This validates enumeration and
  fair prefix controls only; it does not weaken the known human structural
  language limitation.
- A later experiment may attach scores to these keys, but must retain raw
  key-level ledgers and compare against these same target-agnostic prefix
  controls at equal candidate calls.
