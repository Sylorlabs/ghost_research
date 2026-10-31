# Foundry readiness iteration 5.33

The first accountable-provenance protocol failed its preimplementation
enforcement audit. It named a source-choice root without defining its bytes,
and stored only a candidate-roster root without the opaque identity leaves
needed to mechanically test curator and reviewer nonmembership. No external
trust root or provenance artifact existed, so v1 was retired without external
exposure.

Corrected provenance v2 freezes both constructions. Its source-choice root is
derived from canonical representations of all four public v2 source rows. Its
candidate-roster root is derived from a bounded list of opaque identity
commitments, allowing both validators to reject curator or reviewer roster
membership.

Two independent implementations accept a fully signed synthetic chain. They
verify the externally pinned sponsor key, sponsor-signed trust registry and
candidate boundary, curator and reviewer signatures over identical statement
bytes, the external-log signature, exact candidate and bundle bindings, four
chronology relations, and two roster nonmembership relations. Both reject all
26 frozen hostile cases under a complete process-tree receipt.

The production result is deliberately `WAITING_EXTERNAL_SPONSOR_TRUST_ROOT`.
The real state has no sponsor fingerprint, no v2 bundle (`0/5`), and no
provenance package (`0/13`). No payload was decrypted. Foundry remains
`FOUNDRY_V6_NOT_READY` at `5/6` prerequisites with V08 pending and no
prospective execution.
