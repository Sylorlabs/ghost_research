# I4 — equal-budget directed-grammar scaling

**Verdict: negative for a search-efficiency advantage; positive only for
deterministic full coverage.** Under exactly equal candidate-evaluation
budgets, target-blind directed enumeration is reliable only once its fixed
permutation has reached the target candidate. It does **not** reach either
directed target below that point; blind random search gets increasingly
competitive as budget grows. This is a useful boundary: H3's gain cannot be
claimed as general efficiency merely because it opens a finite 1,270-member
grammar.

## Question

How does fixed-menu search, blind random directed search, and admitted
directed exhaustive search behave as the same candidate budget grows? This
tests reliability versus search efficiency. It does not assume the admitted
grammar wins: `guided_without_replacement` has no target-label-derived ranking
within the grammar; it is a frozen, target-blind permutation.

## Frozen protocol

- 8-cell grids with values 0–5; 2,400 iid examples per target/seed,
  train/validation/test = 1,200/600/600.
- Fixed seeds: `0xA400000000000001`, `...0002`, `...0003`.
- Targets: singleton directed (`mask 0x08, mod 3, residue 1`), multi-cell
  directed (`mask 0x33, mod 2, residue 1`), and a threshold-count control
  (`count(v>=3) mod 2 = 0`). Their formulas are data-generation-only; all
  arms score candidate predictions on validation and select a single candidate
  for test.
- Directed grammar: 254 nontrivial masks × five legal mod-2/mod-3 residues =
  **1,270 candidates**. Candidate budgets are exactly 25, 100, 300, 635, and
  1,270 validation evaluations for **every** arm.
- Directed exhaustive arm: scans candidates without replacement using frozen
  affine permutation `(809*i + 113) mod 1270` (809 is coprime to 1270). The
  order is constant across targets/seeds and sees no labels beyond ordinary
  candidate validation scoring.
- Blind arm: iid uniform directed draws **with replacement**, 64 fixed
  deterministic trial streams per target/seed/budget. The CSV retains hit
  counts and rates; ties/hits are not discarded.
- Fixed arm: evaluates the 25 legal global threshold candidates, cycling only
  to spend the exact same budget. This is deliberately a family control, not
  a pretend 1,270-member menu.

## Results

All values below are exact test scores for the selected deterministic arm;
random is its exact-member reliability across 64 equal-budget trials.

| target | budget | directed without replacement | blind-random exact rate (three seeds) | fixed threshold |
|---|---:|---:|---:|---:|
| singleton directed | 25 | 0/3 exact | 0/64 each | 0/3 exact |
| singleton directed | 100 | 0/3 exact | 2–3/64 | 0/3 exact |
| singleton directed | 300 | 0/3 exact | 12–13/64 | 0/3 exact |
| singleton directed | 635 | 0/3 exact | 25/64 | 0/3 exact |
| singleton directed | 1270 | **3/3 exact** | 39–40/64 | 0/3 exact |
| multi-cell directed | 25 | 0/3 exact | 1/64 each | 0/3 exact |
| multi-cell directed | 100 | 0/3 exact | 5–6/64 | 0/3 exact |
| multi-cell directed | 300 | 0/3 exact | 8–9/64 | 0/3 exact |
| multi-cell directed | 635 | **3/3 exact** | 31–32/64 | 0/3 exact |
| multi-cell directed | 1270 | **3/3 exact** | 37–39/64 | 0/3 exact |
| threshold control | all | 0/3 exact | 0/64 each | **3/3 exact** |

The raw aggregate rows are in
`results/grammar_scaling_round_i.csv`: each target × seed × budget contains
one exhaustive row, one fixed row, and a 64-trial random aggregate showing
mean validation accuracy, best observed test score, exact-hit rate/count, and
the fixed arm detail. Stdout is an additionally reproducible per-seed ledger.

## Interpretation

The outcome is intentionally less flattering than an H3-style headline:

- At **full grammar coverage**, without-replacement enumeration is deterministic
  (6/6 directed cases) while random reaches exact members only 37–40/64 times.
  That is a reliability/coverage fact.
- At any lower tested budget, the frozen permutation misses the singleton
  target. The multi-cell target appears at 635, but random is already about
  50% exact there. There is no demonstrated guidance-derived early efficiency
  advantage.
- The threshold control is important: directed enumeration does not magically
  solve a non-directed target, whereas its own fixed menu is 3/3 exact at all
  budgets.

Therefore a later allocator may claim a benefit only if its **response signal
changes allocation or ordering and beats this target-blind coverage baseline**
under the same budget. Simply opening a finite grammar and exhaustively
evaluating it is representability expansion, not autonomous aiming.

## Reproduction

```bash
cd /home/micah/Desktop/Sylorlabs/ghost_research/sparse_poly_discovery
zig build-exe grammar_scaling_round_i.zig -O ReleaseFast -femit-bin=grammar_scaling_round_i
./grammar_scaling_round_i
```

This overwrites `results/grammar_scaling_round_i.csv` deterministically.

## Limits

This is a synthetic finite grammar with eight cells, not a production routing
benchmark. The no-replacement order is intentionally target-blind but remains
one arbitrary frozen permutation; the result does not prove no possible
failure-guided ordering can help. It does prove that the current admitted
exhaustive direction has not demonstrated that help. Exact means held-out test
accuracy >= 0.999, not merely a favorable validation score.
