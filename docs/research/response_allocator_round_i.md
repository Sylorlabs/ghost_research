# I3 — response-guided grammar allocator (Round I)

**Verdict: valid negative.** Under a frozen equal 420-candidate budget, the response-conditioned allocator solves **9/15** independently seeded held-out conditions. That exactly matches the fixed menu (9/15), so it fails its predeclared positive bar: it does not exceed fixed, iid random, and target-blind coverage on untouched holdout.

## Question

Can I1's frozen response evidence allocate an equal candidate budget between global, singleton, symmetric partition, and no-grammar menus better than fixed, iid random, or I4's target-blind directed coverage? I2's symmetric admission is the only partition licence; it has no singleton/cardinality branch.

## Frozen protocol

- The decision API receives precisely I1's eight generic fields: train gain and residual for global, singleton, partition, and adjacency micro-searches. It receives no target name, formula, family, anchor, mask, residue, or audit route.
- Every arm spends **420** candidate evaluations: four 30-candidate I1-style probes (120), then 300 selected candidates. The response policy allocates the 300 proportional to positive gain; the partition allocation closes unless the frozen symmetric gain/residual admission rule passes.
- Each regenerated target uses 600 train / 300 validation / 300 untouched test examples. Five structural holdout conditions (global, singleton, two-cell-to-three-cell partition variant, threshold control, no-grammar control) use three fixed independent seeds: **15** final conditions.
- Controls have identical cost: fixed 75/75/75/75 allocation, iid random allocation with 16 deterministic streams, and I4-style target-blind directed coverage with all 300 post-probe calls sent to the directed grammar.

## Result

| arm | exact held-out conditions | interpretation |
|---|---:|---|
| response guided | 9/15 | no gain over fixed |
| fixed menu | 9/15 | matches response guided |
| iid random mean-exact targets | 6/15 | guided exceeds weak random control |
| target-blind directed coverage | 3/15 | guided exceeds directed-only coverage |

The response rule avoids opening the partition bank for both no-grammar variants, but its 30-probe partition response does not carry enough signal to prioritise the unseen three-cell member. Conversely, fixed equal allocation already gives enough coverage to match guided allocation. I2 can admit multi-cell structure only with a much more expensive full-grammar scan; importing that scan here would consume the equal budget and would not establish routing efficiency.

## Exact conclusion

This rejects the specific hypothesis that I1's short gain/residual response vector, plus I2's symmetric admission, is sufficient for efficient grammar allocation. It does not reject response-driven allocation in general. The next representation must obtain discriminative evidence from search trajectories or near-miss behaviour, then beat this fixed allocation at the same cost.

## Reproduce

```bash
cd /home/micah/Desktop/Sylorlabs/ghost_research/sparse_poly_discovery
zig build-exe response_allocator_round_i.zig -O ReleaseFast -femit-bin=response_allocator_round_i
./response_allocator_round_i
tail -1 ../results/response_allocator_round_i.csv
```

Artifacts: `sparse_poly_discovery/response_allocator_round_i.zig` and `results/response_allocator_round_i.csv`.
