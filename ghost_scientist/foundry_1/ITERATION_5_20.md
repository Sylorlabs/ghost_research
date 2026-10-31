# Foundry readiness iteration 5.20

Phase 130 makes one bounded recovery attempt against each exact immutable
Kiddo-family archive required at the current resolver boundary: `kiddo 5.2.4`,
`az 1.3.0`, `fixed 1.30.0`, and `sorted-vec 0.8.10`. Cargo.lock authenticates
all four expected SHA-256 values. No transfer produced checksum-matching bytes,
and no checked-in Git source was relabeled as a published crate.

Phase 131 closes the proposed A1 shortcut. In frozen A1, the reference plan is
identity transport of the artifact's `reference_program`; artifact loading
typechecks that program through the strict 22-operation Operator-v5 runtime.
A hostile `opaque_framework_call` is rejected. Consequently, arbitrary
framework execution cannot be represented as an A1 reference fallback.

This is a no-go result for that shortcut, not a universal impossibility
theorem. A differently named arm may freeze a larger vocabulary later. Frozen
A1 remains unintegrated because only 4/23 graphs are directly expressible and
no calibration graph triggers a non-reference constructor.

Readiness remains `5/6`, P1 remains `3/4`, integration remains `6/10`, and
validation-v6 remains sealed.
