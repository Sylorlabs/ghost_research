# Foundry readiness iteration 5.26

> Superseded by iteration 5.27. The initial runner accepted three right-nested
> dense chains that do not satisfy the frozen constructor's operand direction.
> This file is preserved as diagnostic history.

A1 now has a justified, bounded implementation target.

The frozen whole-graph compatibility audit found no exact v5.1 constructor
pattern, and the opaque-fallback shortcut remains formally rejected. Before
building a broad 41-target lowering layer, this iteration pre-registered a
connected-subgraph reachability test over only operations already mapped to
non-null Operator-v5 runtime operations.

Two independently implemented enumerators agree on every connected mapped
subgraph of sizes two through six. Across all 23 calibration graphs they
enumerate 7,093 subsets. Exactly six subsets match a frozen v5.1 constructor
histogram, and all six pass their constructor-specific dataflow-adjacency
condition:

- three `fold_conv_batch_norm` opportunities in the adversarial image
  generation graph; and
- three `dense_matrix_chain` opportunities across healthcare dense graph
  convolution and graph node classification.

The complete surface remains 23 graphs, 41 targets, 337 calls, and one
historically unsupported workload. The process tree terminated naturally and
was fully metered.

This result is reachability only. It does not implement typed lowering, execute
a v5.1 constructor, prove parameter or constant transport, establish numerical
equivalence, conform A1, or add a production arm.

It does prevent the next phase from becoming an unbounded compatibility
project: the implementation target is now exactly two constructor families
with six calibration opportunities. Production integration remains `7/10`,
V08 remains pending, validation-v6 stays sealed, and the prospective trial is
still unauthorized.
