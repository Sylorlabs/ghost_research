# Foundry-2.1 autonomous semantic grammar result

Ghost now constructs the tool grammar itself.

From 22 previously uncovered ATen nodes, the LLM-free forge enumerated 31
connected typed DAG candidates. Three had repeated support and positive
description-length gain. For each, the machine selected the operation targets,
inferred the number and order of external inputs, serialized all internal
references and arguments, and emitted a content-addressed executable tool.
There were zero supplied tool forms.

The three selected tools represented nested graph-convolution fragments:

- `mm -> mm -> add`, with four inferred boundary tensors;
- `mm -> add`, with three inferred boundary tensors; and
- `mm -> mm`, with three inferred boundary tensors.

An independently implemented strict parser rejected five hostile mutations.
Its separate matcher and interpreter then executed four pre-forge-frozen
upstream families.

## Prospective result

The candidate library transferred zero times. Its ledger cost was 95 units and
benefit zero. The strong fixed portfolio cost 234 units but matched four times
across two families and covered nine nodes.

The failure is informative rather than incidental. Every semantic tool learned
from repeated graph-convolution structure copied a sparse-layout boundary
constraint. The new forward-forward matrix workload had related `mm -> add`
semantics with dense inputs, so strict typing correctly rejected the apparent
match. The grammar exists and is executable, but its type abstraction is too
concrete to generalize.

All three candidates decompose exactly into stock ATen operations and have no
distinct runtime lowering. Native compilation was explicitly unsupported for
both candidate and stock arms because of sparse tensors. All three remain
rejected as runtime inventions and zero are admitted.

The complete forge/evaluator/native matrix passed process-tree accounting.

## Next falsifiable step

The next forge must infer type variables and admissible layout constraints from
operator-wide calibration evidence. It may generalize a concrete layout only
when independent calibration uses of that operator position support the
generalization. A new validation corpus must be frozen before this forge runs;
validation-v3 is now observed and cannot be reused prospectively.

**Verdict:** `FOUNDRY_V6_NOT_READY`
