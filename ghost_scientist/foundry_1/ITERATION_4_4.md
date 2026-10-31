# Foundry-4.4 runtime-route falsification

The bounded handwritten interpreter is not the production route.

Across all 23 calibration graphs, the framework exports 337 call-function
invocations spanning 41 distinct operator targets. The current typed-DAG
interpreter covers three operators—`aten.add.Tensor`, `aten.mul.Tensor`, and
`aten.relu.default`—representing 53 invocations. That is useful for contract
and state-reset falsification, but it is not a complete runtime.

The route audit requires 100% operator and invocation coverage before a manual
interpreter can establish production correctness. It therefore rejects the
manual route and selects an evaluator-side framework runtime mount. The mount
must bind source and graph digests through the existing contract, execute real
framework graphs and inputs, preserve A3/A9 empty state, retain independent
search verification, and remain disabled for validation-v6 until
authorization.

The preliminary operator census was observed before the route protocol was
written and is disclosed as calibration-only. No prospective claim depends on
the census. The full 23-graph audit passes process-tree accounting.

**Verdict:** `FOUNDRY_V6_NOT_READY`  
**Runtime route:** evaluator-side framework mount required  
**Required arms integrated:** `2/10`
