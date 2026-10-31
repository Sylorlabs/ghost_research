# Foundry-1.6 autonomous typed tensor-tool iteration

This iteration addresses the gap between the earlier byte/text witness forge
and the intended tensor-tool research.

## Construction

The LLM-free forge consumed only measured development and validation pairs. It
abstracted artifact-specific input, parameter, constant, and derived-value
names; inferred bounded symbolic constant expressions; clustered identical
source-to-target graph transformations; and required repeated positive measured
support. It emitted four strict typed tool records from 19 supporting pairs.

The four records implement:

1. convolution plus evaluation batch normalization folding;
2. sparse message-passing reassociation;
3. state-space projection parameter composition; and
4. primitive normalization replacement.

These forms were not listed in the phase-10 forge. They were reconstructed from
the historical measured plan pairs. The primitive operation vocabulary and the
training transformations were supplied, so this is autonomous tool
construction within a bounded grammar, not autonomous invention of tensor
semantics.

## Independent evaluation

A separately implemented parser and interpreter does not import the forge or
the legacy rewrite enumerator. It:

- strictly parses tool and expression records;
- matches typed source graphs;
- instantiates complete parameter and runtime programs;
- passes every program through the evaluator-owned whole-program type checker;
- executes reference and candidate programs; and
- rejects hostile grammar mutations.

All four tools transferred across 20 reserved prefreeze/confirmation artifacts.
The maximum absolute numerical difference was about `3.34e-6`, and all four
hostile mutations were rejected. These historical artifacts are
calibration-only; no prospective claim is made.

## Native and resource audit

Every new tool received one metered TorchInductor comparison:

- zero normalized compiler-code duplicates;
- one sparse required-unsupported case; and
- three nonidentical compiler-code cases.

Nonidentical code is not treated as proof of native novelty. All four candidates
therefore remain quarantined, and none is admitted to a prospective library.
The forge, independent evaluator, and compiler workers all have process-tree
resource receipts. `P3` remains incomplete because external controls and the
final arm matrix do not yet exist.

## Verdict

`FOUNDRY_V6_NOT_READY`

The tensor construction mechanism now exists. The next work must freeze this
component and attack external controls and an independently sourced application
workload/invocation trace. Repeating internally authored tensor families would
not satisfy the remaining scientific boundary.
