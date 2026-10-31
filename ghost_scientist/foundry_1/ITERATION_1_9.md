# Foundry-1.9 ATen macro calibration iteration

The LLM-free forge mined 46 bounded connected ATen patterns from four
calibration application families. Six patterns met cross-family support and
positive structural description-length criteria, for a combined structural
gain of 15.

An independently implemented strict parser, matcher, and FX interpreter then
tested the six typed records against four separately sourced upstream model
families. It found one typed `linear -> relu` match and replayed that subgraph
with zero numerical error. Removing the library removed the match, and four
hostile record mutations were rejected.

## Scientific classification

This result is **calibration only**, not prospective. The validation source
selection was frozen before the forge ran, but the concrete runtime harness and
input shapes were selected afterward. The result therefore tests the mechanism
and adversarial validation path without supporting an unbiased generalization
claim.

All six records are executable search macros over existing ATen operations.
None supplies a distinct runtime rewrite. The native audit therefore
quarantines all six, admits zero, and does not mislabel structural compression
as compiler novelty or speed.

The forge and evaluator were charged through the process-tree resource meter.
Those two local arms pass their bounds, while the missing external controls and
full prospective matrix keep `P3` incomplete.

## Required next phase

Before another forge or validation run, freeze:

1. a new upstream source set;
2. the complete executable harness, modes, seeds, and input shapes;
3. a strong fixed ATen-macro portfolio;
4. the exact search-cost ledger and comparison statistic;
5. resource limits and failure handling; and
6. a no-outcome-driven-intervention rule.

Only evidence generated after that complete freeze can count as prospective.

**Verdict:** `FOUNDRY_V6_NOT_READY`
