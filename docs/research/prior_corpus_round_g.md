# G2 — leakage-clean prior corpus (Round G)

> **Belongs to Round G, experiment G2.** Harness: `sparse_poly_discovery/prior_corpus_round_g.zig`. Raw manifest: `results/prior_corpus_round_g.csv`.

## Status and verdict

**VALID AS A FROZEN CORPUS; it is not selector evidence.** This artifact repairs the concrete F1 construction failures before G3 fits anything. It contains 20 binary targets in the production 8-cell language already used by `genofgen_assembled.zig`: five count/threshold, five mixed-residue, five product-ratio, and five adjacency/run targets. Each row has an exact executable member of its designated prior grammar, so own-prior reachability is **20/20 at 1.000** on 4,096 deterministic examples.

The selector-facing descriptor is six numeric behavioural measurements only: output rate plus agreement with five fixed cheap probes. Target text, source group, formula, and designated prior are audit-only fields and must not be passed to G3/G5 at inference time.

## Frozen protocol

- Train/validation/test is 3/1/1 within each of the four mechanism blocks: **12/4/4** targets.
- Split seeds are frozen and disjoint: `0xA11CE001` train, `0xB11CE002` validation, `0xC11CE003` test (target id is added only to generate that target's grid).
- The four test members are structural formula variants absent from their respective training subset. This is a held-out-target/seed test; it is **not** a claim of zero-shot selection of an entirely unseen prior class, which would be ill-posed for a closed four-prior selector.
- Labels are not “first prior to certify.” Each target's label is eligible only if its exact designated-prior member scores 1.000, exceeds the better constant baseline by at least 0.20, and exceeds every fixed cross-prior probe by at least 0.05. The CSV records the quantitative benefit and exclusivity margin.

## Validity checks

`prior_corpus_round_g.zig` refuses success unless every row is binary/non-degenerate (rate strictly in `(0.05,0.95)`), own-prior exact, beneficial, and exclusive under the prespecified probe menu. The raw CSV is therefore the source of truth for all 20/20 claims. It also computes the train-standardized minimum distance from each validation/held-out descriptor to every training descriptor; the frozen run is **0.792565**, above the predeclared 0.05 duplicate-warning floor. This is an anti-duplicate guard, not proof that train and test are semantically independent; G3 must retain it and add leakage checks appropriate to its model.

## Scope limits

“Production-derived” here means target semantics and 8-cell data geometry are transcribed from the actual F5 production-shaped battery (`genofgen_assembled.zig`, `FRESH_NAMES`/`freshLabel`), not a new VM like invalid F1. The exact grammar member is an existence/reachability witness, not a blind-search success rate. G2 alone cannot show learned inference, transfer, or autonomous invention; G3/G5 must report those against frozen CSV rows and must reject the corpus if their independent descriptor-distance or leakage checks fail.

## Reproduce

```sh
cd sparse_poly_discovery
zig build-exe prior_corpus_round_g.zig -O ReleaseFast -femit-bin=prior_corpus_round_g
./prior_corpus_round_g ../results/prior_corpus_round_g.csv
./prior_corpus_round_g selftest
```
