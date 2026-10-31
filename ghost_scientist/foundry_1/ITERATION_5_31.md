# Foundry readiness iteration 5.31

Validation-v6 remains permanently retired from the primary prospective claim.
The replacement validation-v7 intake boundary was frozen before any external
bundle arrived.

The boundary admits exactly five files: a canonical public manifest, its
detached RSA-PSS signature, a public curator key, an opaque encrypted payload,
and its SHA-256 sidecar. Candidate-visible metadata is restricted to opaque
source identifiers, salted commitments, aggregate attestations, ciphertext
metadata, and signing-key identity. Repository names, revisions, semantic
domains, code, graphs, shapes, fixtures, outcomes, salts, and decryption keys
are forbidden from the inbox.

Primary and independently implemented validators accept one synthetic
3072-bit RSA-PSS signed fixture. Both reject all 16 frozen hostile classes,
including plaintext leakage, duplicate commitments, weakened attestations,
digest mismatch, low-entropy ciphertext, key-fingerprint mismatch, signature
mismatch, private-key presence, unknown files, and missing files. The complete
test process is resource metered.

The real inbox contains zero of the five required files, so Phase155 returns
`VALIDATION_V7_IDENTITY_ONLY_INTAKE_WAITING`. No payload was decrypted and no
v7 source, runtime, graph, shape, or outcome was accessed.

Foundry therefore remains `FOUNDRY_V6_NOT_READY`: the arm matrix is `10/10`,
current prerequisites are `5/6`, V08 is pending, and no prospective trial has
run. The synthetic conformance result proves only that the intake lock works.
An external curator must still supply the signed encrypted bundle, and curator
independence must be established separately before authorization or key
release.
