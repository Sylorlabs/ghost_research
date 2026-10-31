# Ghost Scientist Operator v5

Operator v5 is the next research track after Tensor v4.  Tensor v4 selected
partitions from a supplied projection grammar.  Operator v5 instead requires a
candidate to emit a complete, typed tensor program plus any compile-time
parameter-construction program needed by that runtime program.

The research question is deliberately narrower than "autonomous science":

> Can a frozen constructor learn when to build and reuse semantically equivalent
> multi-operator tensor programs, on evaluator-hidden real graph artifacts, more
> cheaply than strong fixed and searching controls?

The evaluator rejects untyped strategy labels.  A plan must contain every
runtime node.  It is checked by an evaluator-owned type/shape/layout verifier
and replayed numerically from deterministic source parameters.

Initial language coverage:

- dense linear algebra: `linear`, `matmul`, elementwise broadcast, concatenation;
- reductions and normalization: `reduce_mean`, `rsqrt`, `layer_norm`,
  inference-mode batch normalization;
- layout: `reshape`, `permute`, circular padding and rolling;
- convolution and fusion: `conv2d`, activations, derived/folded parameters;
- sparse graph algebra: explicit CSR `sparse_mm`;
- state-space projection graphs: split/project/concatenate and synthesized
  affine compositions.

This directory is a development surface.  It is not frozen and makes no
held-out, autonomous-primitive, GPU, or production claim yet.

