# Foundry readiness iteration 5.28

A1 is now a production-integrated adapted calibration control, advancing the
required arm matrix from `7/10` to `8/10`.

The first frozen absolute-only conformance attempt remains a failed result.
The third synthetic Operator-v5 fixture measured a maximum absolute error of
`1.2874603271484375e-5` against the frozen `1e-5` limit. That result was not
overwritten or reclassified.

A disclosed post-failure amendment, explicitly not pristine preregistration,
froze a 48-fixture unseen numerical panel before it was executed. All 48 pass
the frozen elementwise absolute-plus-relative criterion. The nine real source
comparisons retain the stricter original `1e-5` maximum-absolute requirement
and all pass.

The complete runtime mount covers all 23 calibration graphs and 337
call-function invocations. One graph contains three exact fold sites. Sixty-nine
whole-graph executions and nine real folded-subgraph checks pass with a maximum
observed runtime error of `1.3113021850585938e-6`. Unmatched graphs take the
reference fallback.

All 23 strict adapter contract pairs pass both verifiers under one shared
process-tree receipt. Twenty-two hostile contract mutations are rejected by
both verifiers. Candidate construction is charged once, retained state is
immutable, and exactly three direct tool uses are recorded.

The result is adapted A1, not unchanged v5.1. It adds exactly one calibration
signature, does not materialize a rewritten whole graph, does not measure
heldout transfer, and does not beat the fixed portfolio.

Foundry remains `FOUNDRY_V6_NOT_READY`: A6 and A8 are not production-integrated,
V08 is pending, and validation-v6 remains sealed.
